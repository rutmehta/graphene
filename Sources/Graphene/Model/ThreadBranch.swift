import Foundation
import CoreGraphics

struct ThreadBranch: Identifiable, Equatable {
    let id: UUID
    let depth: Int
    static func rows(ids: [UUID], parents: [UUID: UUID]) -> [ThreadBranch] {
        let allowed = Set(ids)
        var seen = Set<UUID>(), rows: [ThreadBranch] = []
        func walk(_ id: UUID, depth: Int) {
            guard seen.insert(id).inserted else { return }
            rows.append(ThreadBranch(id: id, depth: depth))
            for child in ids where child != id && parents[child] == id { walk(child, depth: depth + 1) }
        }
        for id in ids where parents[id] == nil || parents[id] == id || !allowed.contains(parents[id]!) { walk(id, depth: 0) }
        // Corrupt or legacy cycles must not hide sources or recurse indefinitely.
        for id in ids where !seen.contains(id) { walk(id, depth: 0) }
        return rows
    }
}

/// One Today row in provenance order (graphene-identity.md §3.1).
struct ProvenanceRow: Identifiable, Equatable {
    let id: UUID
    /// True depth in the branch; `indent` clamps it to `threadMaxDepth`.
    let depth: Int
    /// The participating parent, nil for roots.
    let parentID: UUID?
    /// The root of the branch this row belongs to.
    let rootID: UUID
    /// Every row below this one in its branch, hidden or not.
    let descendants: Int
    /// The branch is collapsed; its descendants are not in `rows`.
    let collapsed: Bool
    var indent: Int { min(depth, ShellLayout.threadMaxDepth) }
}

/// Today tabs arranged as branches: roots keep their order, children follow their parent
/// in `ids` order (oldest first, because children are appended after their siblings).
struct ProvenanceLayout: Equatable {
    /// The visible rows, top to bottom.
    let rows: [ProvenanceRow]
    /// False when no row has a parent: the list renders exactly as a flat Today list.
    let hasBranches: Bool

    init(ids: [UUID], parents: [UUID: UUID], collapsed: Set<UUID> = []) {
        let allowed = Set(ids)
        let linked = parents.filter { allowed.contains($0.key) && allowed.contains($0.value) && $0.key != $0.value }
        guard !linked.isEmpty else {
            rows = ids.map { ProvenanceRow(id: $0, depth: 0, parentID: nil, rootID: $0, descendants: 0, collapsed: false) }
            hasBranches = false
            return
        }
        let branch = ThreadBranch.rows(ids: ids, parents: linked)
        // Pre-order: a row's descendants are the rows after it until the depth returns to its own.
        var counts = Array(repeating: 0, count: branch.count), open: [Int] = []
        for (index, row) in branch.enumerated() {
            while let last = open.last, branch[last].depth >= row.depth { open.removeLast() }
            for ancestor in open { counts[ancestor] += 1 }
            open.append(index)
        }
        var all: [ProvenanceRow] = [], root = branch.first?.id ?? UUID()
        for (index, row) in branch.enumerated() {
            if row.depth == 0 { root = row.id }
            all.append(ProvenanceRow(id: row.id, depth: row.depth, parentID: row.depth > 0 ? linked[row.id] : nil, rootID: root,
                                     descendants: counts[index], collapsed: counts[index] > 0 && collapsed.contains(row.id)))
        }
        var visible: [ProvenanceRow] = [], hiddenBelow: Int?
        for row in all {
            if let depth = hiddenBelow, row.depth > depth { continue }
            hiddenBelow = row.collapsed ? row.depth : nil
            visible.append(row)
        }
        rows = visible
        hasBranches = true
    }

    /// Vertical hairlines and ticks for the visible rows, in the rows' own coordinate space
    /// (row `i` spans `i × rowPitch` to `i × rowPitch + rowHeight`).
    func connectors(activeID: UUID?) -> [ProvenanceConnector] {
        guard hasBranches else { return [] }
        let activeRoot = rows.first { $0.id == activeID }?.rootID
        var index: [UUID: Int] = [:]
        for (i, row) in rows.enumerated() { index[row.id] = i }
        var children: [UUID: [Int]] = [:]
        for (i, row) in rows.enumerated() { if let parent = row.parentID { children[parent, default: []].append(i) } }
        return rows.enumerated().compactMap { i, parent in
            guard let kids = children[parent.id], let last = kids.last else { return nil }
            return ProvenanceConnector(parentID: parent.id, parentRow: i, parentIndent: parent.indent, childRows: kids,
                                       lastChildRow: last, active: activeRoot != nil && parent.rootID == activeRoot)
        }
    }
}

/// One path per parent: a hairline down the parent's icon column and a tick into each child.
struct ProvenanceConnector: Equatable {
    let parentID: UUID
    let parentRow: Int
    let parentIndent: Int
    let childRows: [Int]
    let lastChildRow: Int
    /// The branch holds the selected tab and draws in `threadLineActive`.
    let active: Bool
    /// Row metrics: the sidebar's by default; Mail conversations pass their 44pt rows.
    var rowPitch: CGFloat = ShellLayout.rowPitch
    var rowHeight: CGFloat = ShellLayout.rowHeight

    private func iconCentreY(_ row: Int) -> CGFloat {
        CGFloat(row) * rowPitch + rowHeight / 2
    }
    var x: CGFloat { CGFloat(parentIndent) * ShellLayout.threadIndent + ShellLayout.threadLineInset }
    /// From the bottom of the parent's icon slot to the centre of the last child's icon.
    var vertical: CGRect {
        let top = iconCentreY(parentRow) + ShellLayout.iconSlot / 2
        let bottom = iconCentreY(lastChildRow) + ShellLayout.hairline / 2
        return CGRect(x: x, y: top, width: ShellLayout.hairline, height: max(0, bottom - top))
    }
    /// Each tick runs `threadTick` from the vertical to the child's icon slot edge. It starts just
    /// right of the vertical so the translucent strokes never overlap.
    var ticks: [CGRect] {
        childRows.map { CGRect(x: x + ShellLayout.hairline, y: iconCentreY($0) - ShellLayout.hairline / 2,
                               width: ShellLayout.threadTick - ShellLayout.hairline, height: ShellLayout.hairline) }
    }
    /// The path while its vertical is drawn from `top` down to `bottom` (the length animates on
    /// collapse and expand): ticks appear once the vertical reaches them.
    static func drawn(vertical: CGRect, ticks: [CGRect], top: CGFloat, bottom: CGFloat) -> [CGRect] {
        let line = CGRect(x: vertical.minX, y: top, width: vertical.width, height: max(0, bottom - top))
        return [line] + ticks.filter { $0.minY <= bottom }
    }
}
