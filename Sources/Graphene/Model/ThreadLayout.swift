import Foundation
import CoreGraphics

/// The Thread map as a tree in time (graphene-language.md §5.2): columns are depth, rows are
/// order. Roots (a visit with no parent in the thread, or one that came from a search) sit at
/// column 0; every page is a node at `x = column × threadColumn`, `y = row × threadRowPitch`,
/// with rows from a depth-first walk so a branch is contiguous under its parent, exactly like
/// the sidebar's `ThreadBranch.rows`. Pure: built from a thread's visits, no view state.
struct ThreadLayout: Equatable {
    struct Node: Identifiable, Equatable {
        let id: UUID
        let row: Int
        /// The depth in the tree; 0 for roots.
        let column: Int
        /// The node this page was first opened from in the thread; nil for roots.
        let parentID: UUID?
        let rootID: UUID
        /// Top-left of the node's row band, at the start of its favicon slot.
        var origin: CGPoint {
            CGPoint(x: CGFloat(column) * ShellLayout.threadColumn, y: CGFloat(row) * ShellLayout.threadRowPitch)
        }
        /// Centre of the favicon slot.
        var centre: CGPoint {
            CGPoint(x: origin.x + ShellLayout.threadNodeSize / 2, y: origin.y + ShellLayout.threadRowPitch / 2)
        }
    }

    /// A label row above a root: the thread's start time over the first root, and the search
    /// query (in quotes) over every root that came from a search.
    struct Header: Identifiable, Equatable {
        let row: Int
        let rootID: UUID
        let query: String?
        /// Set only on the header above the first root.
        let start: Date?
        var id: UUID { rootID }
    }

    let nodes: [Node]
    let headers: [Header]
    let connectors: [ThreadConnector]
    /// Rows used, header rows included.
    let rowCount: Int
    /// Columns used (deepest column + 1).
    let columnCount: Int
    private let index: [UUID: Int]

    /// `nodeIDs` in chronological order (the thread's pages); `visits` are the thread's visits.
    init(nodeIDs: [UUID], visits: [GraphVisit], start: Date? = nil) {
        let allowed = Set(nodeIDs)
        var first: [UUID: GraphVisit] = [:]
        for visit in visits.sorted(by: { $0.date < $1.date }) where allowed.contains(visit.nodeID) && first[visit.nodeID] == nil {
            first[visit.nodeID] = visit
        }
        var parents: [UUID: UUID] = [:], queries: [UUID: String] = [:]
        for (id, visit) in first {
            if let query = visit.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
                queries[id] = query  // a search starts its own root
            } else if let parent = visit.parentNodeID, parent != id, allowed.contains(parent) {
                parents[id] = parent
            }
        }
        let branch = ThreadBranch.rows(ids: nodeIDs, parents: parents)
        let threadStart = start ?? visits.map(\.date).min()
        var nodes: [Node] = [], headers: [Header] = [], row = 0
        var stack: [UUID] = [], root = branch.first?.id ?? UUID()
        for entry in branch {
            if entry.depth == 0 {
                root = entry.id
                let isFirst = nodes.isEmpty
                if isFirst || queries[entry.id] != nil {
                    headers.append(Header(row: row, rootID: entry.id, query: queries[entry.id], start: isFirst ? threadStart : nil))
                    row += 1
                }
            }
            // Pre-order: the parent is the open node one level up.
            stack.removeLast(max(0, stack.count - entry.depth))
            nodes.append(Node(id: entry.id, row: row, column: entry.depth, parentID: stack.last, rootID: root))
            stack.append(entry.id)
            row += 1
        }
        var index: [UUID: Int] = [:]
        for (i, node) in nodes.enumerated() { index[node.id] = i }
        var children: [UUID: [Node]] = [:], order: [UUID] = []
        for node in nodes {
            guard let parent = node.parentID else { continue }
            if children[parent] == nil { order.append(parent) }
            children[parent, default: []].append(node)
        }
        self.connectors = order.compactMap { id in
            guard let parent = index[id].map({ nodes[$0] }), let kids = children[id] else { return nil }
            return ThreadConnector(parent: parent, children: kids)
        }
        self.nodes = nodes
        self.headers = headers
        self.rowCount = row
        self.columnCount = (nodes.map(\.column).max() ?? -1) + 1
        self.index = index
    }

    init(thread: KnowledgeGraph.Thread, visits: [GraphVisit]) {
        self.init(nodeIDs: thread.nodes.map(\.id), visits: visits.filter { $0.threadID == thread.id }, start: thread.start)
    }

    func node(_ id: UUID) -> Node? { index[id].map { nodes[$0] } }

    /// Root first, ending with `id`; empty when `id` is not in the map.
    func ancestors(of id: UUID) -> [UUID] {
        var path: [UUID] = [], cursor: UUID? = id
        while let current = cursor, let node = node(current), !path.contains(current) {
            path.insert(current, at: 0)
            cursor = node.parentID
        }
        return path
    }

    /// For each connector on the selected node's ancestor path, the child it leads to.
    func activeChildren(selected id: UUID?) -> [UUID: UUID] {
        guard let id else { return [:] }
        let path = ancestors(of: id)
        var result: [UUID: UUID] = [:]
        for (parent, child) in zip(path, path.dropFirst()) { result[parent] = child }
        return result
    }

    /// The node and every node below it in its branch, in row order: what Resume reopens.
    func branch(from id: UUID) -> [Node] {
        guard let start = index[id] else { return [] }
        let depth = nodes[start].column
        var result = [nodes[start]]
        for node in nodes[(start + 1)...] {
            guard node.column > depth else { break }
            result.append(node)
        }
        return result
    }

    /// The content size of the node grid (labels to the right of the last column are extra).
    var size: CGSize {
        CGSize(width: CGFloat(columnCount) * ShellLayout.threadColumn, height: CGFloat(rowCount) * ShellLayout.threadRowPitch)
    }

    // MARK: node text

    /// Map titles truncate at this many characters.
    static let titleLimit = 26
    static func truncatedTitle(_ title: String, limit: Int = titleLimit) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The start label at the top of the root column: weekday and 24-hour time, "Tue 14:05".
    static func startLabel(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEHHmm")
        return formatter.string(from: date)
    }

    // MARK: summary citations

    /// The map node a summary citation points at: the model's `[n]` indexes the sources it was
    /// given, and each thread source carries its node's id.
    static func nodeID(for citation: ChatCitation, sources: [KnowledgeSource], in nodeIDs: Set<UUID>) -> UUID? {
        guard sources.indices.contains(citation.sourceNumber - 1) else { return nil }
        let id = sources[citation.sourceNumber - 1].id
        return nodeIDs.contains(id) ? id : nil
    }

    // MARK: sizes and motion (graphene-language.md §5.2, §6)

    /// The summary column and the node hover card.
    static let summaryWidth: CGFloat = 320
    static let hoverCardWidth: CGFloat = 320
    /// Gap between a node's title and its host.
    static let hostGap: CGFloat = 6
    /// Nodes fade in by depth: this much later per column, never more than `fadeCap`.
    static let fadeStagger = 0.04
    static let fadeCap = 0.2
    static let fadeDuration = 0.12
    /// Connectors draw from parent to child over this long.
    static let connectorDraw = 0.2
    /// The ancestor path recolours over this long.
    static let recolour = 0.12
    static func fadeDelay(column: Int) -> Double { min(Double(max(0, column)) * fadeStagger, fadeCap) }
}

/// The space-wide map (graphene-language.md §5.2): with no thread selected, every thread in the
/// space as its own tree, in the list's order (newest first), each a `ThreadLayout` with its own
/// start label. The view stacks them with `sectionGap` between. Pure: visits are grouped once.
struct ThreadForest {
    struct Tree: Identifiable {
        let thread: KnowledgeGraph.Thread
        let layout: ThreadLayout
        var id: UUID { thread.id }
    }
    let trees: [Tree]

    init(threads: [KnowledgeGraph.Thread], visits: [GraphVisit]) {
        let byThread = Dictionary(grouping: visits, by: \.threadID)
        trees = threads.map { thread in
            Tree(thread: thread, layout: ThreadLayout(nodeIDs: thread.nodes.map(\.id), visits: byThread[thread.id] ?? [], start: thread.start))
        }
    }

    /// Pages across every tree.
    var pageCount: Int { trees.reduce(0) { $0 + $1.layout.nodes.count } }
}

/// What a click on a map or list node does: one click selects, a double-click opens the page
/// in the current tab, ⌘-double-click opens it as a child of the current tab.
enum ThreadNodeClick: Equatable {
    case select
    case open
    case openAsChild

    static func action(clickCount: Int, command: Bool) -> ThreadNodeClick {
        guard clickCount >= 2 else { return .select }
        return command ? .openAsChild : .open
    }
}

/// The Threads surface's panes (graphene-language.md §5.2): a `threadListWidth` thread list,
/// then the selected thread's `threadHeaderHeight` header strip over the tree, and the summary
/// column only once a summary exists, is streaming or has something to say.
enum ThreadPanes {
    static let listWidth = ShellLayout.threadListWidth
    static let headerHeight = ShellLayout.threadHeaderHeight

    /// Whether the summary column is on screen. Until it is, "Summarize thread" is a glyph in
    /// the library bar and the tree has the whole detail width.
    static func showsSummary(text: String, working: Bool, error: String?) -> Bool {
        working || !text.isEmpty || !(error ?? "").isEmpty
    }

    /// The header strip's metadata: "4 pages · 1 site · 2 notes".
    static func counts(pages: Int, sites: Int, notes: Int) -> String {
        func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        return [count(pages, "page"), count(sites, "site"), count(notes, "note")].joined(separator: " · ")
    }

    /// The All threads strip's metadata: "3 threads · 12 pages".
    static func forestCounts(threads: Int, pages: Int) -> String {
        func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        return count(threads, "thread") + " · " + count(pages, "page")
    }
}

/// One path per parent (graphene-identity.md §3.1's connector vocabulary, turned sideways for
/// the map): a vertical `threadLine` down the parent's favicon column from the bottom of its
/// slot to the last child's row, and a horizontal into each child's slot, rounded at the corner.
struct ThreadConnector: Identifiable, Equatable {
    let parentID: UUID
    let childIDs: [UUID]
    let parentColumn: Int
    /// The vertical's x: the centre of the parent's favicon slot.
    let x: CGFloat
    /// Where the vertical starts: the bottom of the parent's favicon slot.
    let top: CGFloat
    /// Each child's centre line, top to bottom.
    let childYs: [CGFloat]
    /// Where each horizontal ends: the leading edge of the child's slot.
    let endX: CGFloat
    var id: UUID { parentID }
    /// The corner between the vertical and a horizontal.
    static let cornerRadius: CGFloat = 6

    init(parent: ThreadLayout.Node, children: [ThreadLayout.Node]) {
        parentID = parent.id
        childIDs = children.map(\.id)
        parentColumn = parent.column
        x = parent.centre.x
        top = parent.centre.y + ShellLayout.threadNodeSize / 2
        childYs = children.map(\.centre.y)
        endX = CGFloat(parent.column + 1) * ShellLayout.threadColumn
    }

    /// The vertical's end: the last child's centre line.
    var bottom: CGFloat { childYs.last ?? top }

    /// The path into the given children (all of them by default), each an elbow from the top of
    /// the vertical. The elbows share the vertical, so stroking the whole path once draws it once.
    func path(to children: Set<UUID>? = nil) -> CGPath {
        let path = CGMutablePath()
        let r = Self.cornerRadius
        for (id, y) in zip(childIDs, childYs) where children?.contains(id) ?? true {
            path.move(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x, y: max(top, y - r)))
            path.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
        }
        return path
    }
}
