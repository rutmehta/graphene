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

/// The knowledge graph: pages as nodes, connected by chronological branching
/// (opened-from) and tied back to the search that started the thread. This is
/// why it's called Graphene — your history *is* a navigable graph, not a list.
/// (Semantic grouping of nodes is a deliberate later layer.)
@MainActor
final class KnowledgeGraph: ObservableObject {
    @Published private(set) var nodes: [UUID: GraphNode] = [:]
    @Published private(set) var edges: [GraphEdge] = []
    private var urlIndex: [String: UUID] = [:]
    private var saveWork: DispatchWorkItem?

    var nodeArray: [GraphNode] { Array(nodes.values) }

    init() { load() }

    // MARK: recording

    /// Record a visit; create or update the node and add a chronological edge
    /// from its parent. Returns the node id so the tab can track its position.
    @discardableResult
    func recordVisit(url: URL, title: String?, spaceID: UUID?, parentNodeID: UUID?, query: String?) -> UUID {
        let key = normalize(url)
        let now = Date()
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
        scheduleSave()
        return id
    }

    /// Store a short snippet of the page for previews (and future grouping).
    func attachText(nodeID: UUID, text: String) {
        guard var node = nodes[nodeID], !text.isEmpty else { return }
        node.snippet = String(text.prefix(2000))
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

    func node(for url: URL) -> GraphNode? {
        guard let id = urlIndex[normalize(url)] else { return nil }
        return nodes[id]
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
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        comps.fragment = nil
        if let items = comps.queryItems {
            let kept = items.filter { !Self.volatileParams.contains($0.name.lowercased()) }
            comps.queryItems = kept.isEmpty ? nil : kept
        }
        var s = comps.string ?? url.absoluteString
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    // MARK: persistence

    private struct Snapshot: Codable { var nodes: [GraphNode]; var edges: [GraphEdge] }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func save() {
        let snap = Snapshot(nodes: Array(nodes.values), edges: edges)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: Paths.graphFile)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Paths.graphFile),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        for n in snap.nodes { nodes[n.id] = n; urlIndex[n.url] = n.id }
        edges = snap.edges
    }
}
