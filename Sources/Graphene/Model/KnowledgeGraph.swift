import Foundation
import Combine

struct GraphNode: Codable, Identifiable {
    let id: UUID
    var url: String
    var title: String
    var host: String
    var firstVisit: Date
    var lastVisit: Date
    var visitCount: Int
    var spaceID: UUID?
    /// The search query that led here — the "why" a plain history list throws away.
    var query: String?
    var annotationCount: Int
    var snippet: String
    // Persisted layout so the graph doesn't reshuffle every open.
    var x: Double
    var y: Double
}

enum EdgeKind: String, Codable {
    case chronological  // you opened this from that
    case query          // this search led to that page
}

struct GraphEdge: Codable, Identifiable {
    var id: UUID = UUID()
    var from: UUID
    var to: UUID
    var kind: EdgeKind
    var weight: Double
    var label: String?
}

struct GraphVisit: Codable, Identifiable {
    let id: UUID
    let nodeID: UUID
    let threadID: UUID
    let parentNodeID: UUID?
    let spaceID: UUID?
    let date: Date
    let query: String?
}

struct ThreadSummary: Codable {
    var text: String
    var sources: [KnowledgeSource]
    var profileID: UUID
}

/// The knowledge graph: pages as nodes, connected by chronological branching
/// (opened-from) and tied back to the search that started the thread. This is
/// why it's called Graphene — your history *is* a navigable graph, not a list.
/// (Semantic grouping of nodes is a deliberate later layer.)
@MainActor
final class KnowledgeGraph: ObservableObject {
    @Published private(set) var nodes: [UUID: GraphNode] = [:] { didSet { threadCache.removeAll() } }
    @Published private(set) var edges: [GraphEdge] = []
    @Published private(set) var visits: [GraphVisit] = [] { didSet { threadCache.removeAll() } }
    /// `threads(...)` results until the next change of `nodes` or `visits`: the Resume page,
    /// the Threads list, the Ask panel and the command bar ask for them on every redraw.
    private var threadCache: [String: [Thread]] = [:]
    @Published private(set) var summaries: [String: ThreadSummary] = [:]
    func cacheSummary(_ summary: ThreadSummary, threadID: UUID) { summaries[threadID.uuidString] = summary; scheduleSave() }
    @Published private(set) var errorText: String?
    private var canSave = true
    private let file: URL
    private var urlIndex: [String: UUID] = [:]
    private var saveWork: DispatchWorkItem?

    var nodeArray: [GraphNode] { Array(nodes.values) }

    init(file: URL = Paths.graphFile, inMemory: Bool = false) {
        self.file = file; canSave = !inMemory
        if !inMemory { load() }
    }

    // MARK: recording

    /// Record a visit; create or update the node and add a chronological edge
    /// from its parent. Returns the node id so the tab can track its position.
    @discardableResult
    func recordVisit(url: URL, title: String?, spaceID: UUID?, parentNodeID: UUID?, query: String?, date: Date = Date(), continuingThreadID: UUID? = nil, resumeThreadID: UUID? = nil) -> UUID {
        let key = normalize(url)
        let now = date
        let host = url.host ?? ""
        let id: UUID
        if let existing = urlIndex[key], var node = nodes[existing] {
            node.lastVisit = now
            node.visitCount += 1
            if let title, !title.isEmpty { node.title = title }
            if node.query == nil, let query { node.query = query }
            nodes[existing] = node
            id = existing
        } else {
            let seed = seedPosition(near: parentNodeID)
            let node = GraphNode(
                id: UUID(), url: key, title: title ?? host, host: host,
                firstVisit: now, lastVisit: now, visitCount: 1, spaceID: spaceID,
                query: query, annotationCount: 0, snippet: "",
                x: seed.x, y: seed.y
            )
            nodes[node.id] = node
            urlIndex[key] = node.id
            id = node.id
        }

        if let parent = parentNodeID, parent != id {
            let label = query
            addEdge(from: parent, to: id, kind: query != nil ? .query : .chronological, weight: 1, label: label)
        }
        let parentVisit = visits.last { $0.nodeID == parentNodeID && $0.spaceID == spaceID && (continuingThreadID == nil || $0.threadID == continuingThreadID) }
        let continues = query == nil && parentVisit.map { now.timeIntervalSince($0.date) < 40 * 60 } == true
        let resume = resumeThreadID.flatMap { id in visits.contains { $0.threadID == id && ($0.spaceID == spaceID || $0.spaceID == nil) } ? id : nil }
        let threadID = resume ?? (continues ? parentVisit!.threadID : UUID())
        visits.append(GraphVisit(id: UUID(), nodeID: id, threadID: threadID,
                                 parentNodeID: parentNodeID, spaceID: spaceID, date: now, query: query))
        scheduleSave()
        return id
    }

    /// Store a short snippet of the page for previews (and future grouping).
    func attachText(nodeID: UUID, text: String) {
        guard var node = nodes[nodeID], !text.isEmpty else { return }
        node.snippet = String(text.prefix(16000))
        nodes[nodeID] = node
        scheduleSave()
    }

    /// Sites often set their title via JS after the load finishes; back-fill it.
    func setTitle(nodeID: UUID, title: String) {
        guard var node = nodes[nodeID], !title.isEmpty, node.title != title else { return }
        node.title = title
        nodes[nodeID] = node
        scheduleSave()
    }

    func bumpAnnotationCount(nodeID: UUID) {
        guard var node = nodes[nodeID] else { return }
        node.annotationCount += 1
        nodes[nodeID] = node
        scheduleSave()
    }

    /// Every recorded visit of one thread, in recording order.
    func visits(inThread id: UUID) -> [GraphVisit] { visits.filter { $0.threadID == id } }

    func node(for url: URL) -> GraphNode? {
        guard let id = urlIndex[normalize(url)] else { return nil }
        return nodes[id]
    }

    /// A thread of thought: a browsing session (a burst of activity), its pages
    /// in chronological order, and the search that started it.
    struct Thread: Identifiable {
        let id: UUID
        var nodes: [GraphNode]
        var start: Date
        var end: Date
        var title: String
        var query: String?
        var noteCount: Int
        var hosts: [String]
    }

    /// Whether `threads(spaceID:)` would return any thread, without building them: a visit in
    /// scope whose page is known. The command table asks this on every AppState change.
    func hasThreads(spaceID: UUID? = nil) -> Bool {
        visits.last { (spaceID == nil || $0.spaceID == spaceID || $0.spaceID == nil) && nodes[$0.nodeID] != nil } != nil
    }

    func threads(gapMinutes: Double = 40, limit: Int = 100, spaceID: UUID? = nil) -> [Thread] {
        let key = "\(gapMinutes)|\(limit)|\(spaceID?.uuidString ?? "all")"
        if let cached = threadCache[key] { return cached }
        let built = buildThreads(limit: limit, spaceID: spaceID)
        threadCache[key] = built
        return built
    }

    private func buildThreads(limit: Int, spaceID: UUID?) -> [Thread] {
        let scoped = visits.filter { spaceID == nil || $0.spaceID == spaceID || $0.spaceID == nil }
        return Dictionary(grouping: scoped, by: \.threadID).compactMap { id, entries -> Thread? in
            let ordered = entries.sorted { $0.date < $1.date }
            var seen = Set<UUID>()
            let pages = ordered.compactMap { visit -> GraphNode? in
                guard seen.insert(visit.nodeID).inserted, var node = nodes[visit.nodeID] else { return nil }
                node.firstVisit = visit.date
                return node
            }
            guard let first = pages.first, let start = ordered.first?.date, let end = ordered.last?.date else { return nil }
            let query = ordered.compactMap(\.query).first
            var hosts: [String] = []
            for page in pages where !hosts.contains(page.host) { hosts.append(page.host) }
            return Thread(id: id, nodes: pages, start: start, end: end,
                          title: query ?? first.title, query: query,
                          noteCount: pages.reduce(0) { $0 + $1.annotationCount }, hosts: hosts)
        }.sorted { $0.end > $1.end }.prefix(limit).map { $0 }
    }

    func search(_ input: String, spaceID: UUID? = nil, limit: Int = 40) -> [GraphNode] {
        let terms = input.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let allowed = spaceID.map { id in Set(visits.filter { $0.spaceID == id || $0.spaceID == nil }.map(\.nodeID)) }
        let ranked = nodes.values.compactMap { node -> (GraphNode, Int)? in
            guard allowed == nil || allowed!.contains(node.id) else { return nil }
            let title = (node.title + " " + (node.query ?? "")).lowercased()
            let body = (node.snippet + " " + node.url).lowercased()
            let score = terms.reduce(0) { $0 + (title.contains($1) ? 8 : 0) + (body.contains($1) ? 1 : 0) }
            guard terms.isEmpty || score > 0 else { return nil }
            return (node, score)
        }
        return ranked.sorted { $0.1 == $1.1 ? $0.0.lastVisit > $1.0.lastVisit : $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    static func canonicalURL(_ value: String) -> String {
        guard let url = URL(string: value), var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return value }
        c.fragment = nil
        c.queryItems = c.queryItems?.filter { !volatileParams.contains($0.name.lowercased()) }
        if c.queryItems?.isEmpty == true { c.queryItems = nil }
        var key = c.string ?? value
        if key.hasSuffix("/") { key.removeLast() }
        return key
    }

    /// Most-relevant pages for the start page: frequent + recent, de-duplicated by host.
    func topNodes(limit: Int = 6) -> [GraphNode] {
        let now = Date()
        let ranked = nodes.values.sorted { a, b in
            func score(_ n: GraphNode) -> Double {
                let ageDays = now.timeIntervalSince(n.lastVisit) / 86_400
                return Double(n.visitCount) * exp(-ageDays / 21)
            }
            return score(a) > score(b)
        }
        var seenHost = Set<String>()
        var out: [GraphNode] = []
        for n in ranked {
            if seenHost.contains(n.host) { continue }
            seenHost.insert(n.host)
            out.append(n)
            if out.count >= limit { break }
        }
        return out
    }

    func updatePositions(_ positions: [UUID: (Double, Double)]) {
        for (id, p) in positions where nodes[id] != nil {
            nodes[id]?.x = p.0
            nodes[id]?.y = p.1
        }
        scheduleSave()
    }

    // MARK: edges

    private func addEdge(from: UUID, to: UUID, kind: EdgeKind, weight: Double, label: String? = nil) {
        if let i = edges.firstIndex(where: { $0.from == from && $0.to == to && $0.kind == kind }) {
            edges[i].weight = max(edges[i].weight, weight)
            if let label { edges[i].label = label }
            return
        }
        edges.append(GraphEdge(from: from, to: to, kind: kind, weight: weight, label: label))
    }

    // MARK: forget

    func forget(host: String) {
        let doomed = nodes.values.filter { hostMatches($0.host, host) }.map { $0.id }
        let set = Set(doomed)
        for id in doomed { if let n = nodes[id] { urlIndex[n.url] = nil }; nodes[id] = nil }
        edges.removeAll { set.contains($0.from) || set.contains($0.to) }
        visits.removeAll { set.contains($0.nodeID) }
        summaries = summaries.filter { !$0.value.sources.contains { set.contains($0.id) } }
        scheduleSave()
    }

    private func hostMatches(_ h: String, _ target: String) -> Bool {
        let t = target.lowercased()
        let host = h.lowercased()
        return host == t || host.hasSuffix("." + t)
    }

    // MARK: layout seeding

    private func seedPosition(near parentID: UUID?) -> (x: Double, y: Double) {
        if let p = parentID, let parent = nodes[p] {
            return (parent.x + Double.random(in: -40...40), parent.y + Double.random(in: -40...40))
        }
        return (Double.random(in: -200...200), Double.random(in: -200...200))
    }

    // Params that SPAs (esp. Google) rewrite in-place — stripping them keeps a
    // page from spawning near-duplicate nodes as tracking junk changes.
    private static let volatileParams: Set<String> = [
        "sca_esv", "ved", "ei", "source", "sourceid", "oq", "gs_lcrp", "sclient",
        "uact", "bih", "biw", "dpr", "sxsrf", "iflsig", "aqs", "gs_lp", "spf",
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "fbclid", "gclid",
    ]

    private func normalize(_ url: URL) -> String {
        Self.canonicalURL(url.absoluteString)
    }

    // MARK: persistence

    private struct Snapshot: Codable { var nodes: [GraphNode]; var edges: [GraphEdge]; var visits: [GraphVisit]?; var summaries: [String: ThreadSummary]? }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save(wait: false) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Encodes and writes the graph off the main thread, in order. The file holds every page's
    /// text snippet (up to 16 KB each), so encoding it on the main thread after each
    /// navigation stalled the UI for as long as the history was large.
    private static let saveQueue = DispatchQueue(label: "graphene.graph.save", qos: .utility)

    /// Saves now. `wait` (the default, used at quit and by callers that read the file back)
    /// returns after the file is written; the scheduled save does not wait.
    func save(wait: Bool = true) {
        guard canSave else { return }
        let snap = Snapshot(nodes: Array(nodes.values), edges: edges, visits: visits, summaries: summaries)
        let file = self.file
        let write: @Sendable () -> String? = {
            do { try JSONEncoder().encode(snap).write(to: file, options: .atomic); return nil }
            catch { return error.localizedDescription }
        }
        if wait {
            let error = Self.saveQueue.sync(execute: write)
            if errorText != error { errorText = error }
        } else {
            Self.saveQueue.async { [weak self] in
                let error = write()
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { if let self, self.errorText != error { self.errorText = error } }
                }
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let snap: Snapshot
        do { snap = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file)) }
        catch { canSave = false; errorText = "The history file couldn’t be read. It has been left untouched."; return }
        for n in snap.nodes { nodes[n.id] = n; urlIndex[n.url] = n.id }
        edges = snap.edges
        summaries = snap.summaries ?? [:]
        if let recorded = snap.visits {
            visits = recorded
        } else {
            // Preserve old history once, then record each navigation independently.
            var threadID = UUID()
            var previous: GraphNode?
            for node in snap.nodes.sorted(by: { $0.firstVisit < $1.firstVisit }) {
                if let p = previous, node.firstVisit.timeIntervalSince(p.firstVisit) > 2400 || node.query != nil { threadID = UUID() }
                visits.append(GraphVisit(id: UUID(), nodeID: node.id, threadID: threadID,
                                         parentNodeID: previous?.id, spaceID: nil, date: node.firstVisit, query: node.query))
                previous = node
            }
        }
    }
}
