import Foundation
import Combine
import CoreGraphics
import SwiftUI

/// The three Board card kinds (graphene-language.md §5.6).
enum BoardCardKind: String, Codable, Equatable {
    /// A web page: favicon, title, host and a thumbnail.
    case page
    /// The user's own words: a title line and a body.
    case note
    /// Text clipped from a page, set in the quote face with its provenance beneath.
    case quote
}

struct BoardItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var spaceID: UUID
    var title: String
    var text: String = ""
    var url: String? = nil
    var x: Double = 24
    var y: Double = 24
    var width: Double = 240
    var height: Double = 180
    /// Saved from G9 on; older boards decode without it and infer the kind from `url`.
    var kind: BoardCardKind? = nil
    /// The clipped page text of a quote card; `text` holds the user's note on it.
    var quote: String? = nil

    /// The card's kind: saved, else a card with a link is a page and one without is a note.
    var cardKind: BoardCardKind { kind ?? (url == nil ? .note : .page) }

    static let minSize = CGSize(width: 180, height: 120)
    static let maxSize = CGSize(width: 800, height: 800)
    static let maxOrigin: Double = 4000

    /// A new card's size: page cards leave room for the 16:10 thumbnail. Lattice-snapped.
    static func defaultSize(for kind: BoardCardKind) -> CGSize {
        switch kind {
        case .page: return BoardGrid.snap(size: CGSize(width: 252, height: 218))
        case .note: return BoardGrid.snap(size: CGSize(width: 224, height: 145))
        case .quote: return BoardGrid.snap(size: CGSize(width: 252, height: 170))
        }
    }
}

@MainActor final class BoardStore: ObservableObject {
    @Published private(set) var entries: [BoardItem] = []
    @Published private(set) var errorText: String?
    private let file: URL?
    private var canSave = true
    init(file: URL?) {
        self.file = file
        if let file, FileManager.default.fileExists(atPath: file.path) {
            do { entries = try JSONDecoder().decode([BoardItem].self, from: Data(contentsOf: file)) }
            catch { canSave = false; errorText = "Boards couldn’t be read. The original file is untouched." }
        }
    }
    func items(in spaceID: UUID) -> [BoardItem] { entries.filter { $0.spaceID == spaceID } }
    func upsert(_ item: BoardItem) {
        guard canSave else { return }
        var item = item
        item.x = min(BoardItem.maxOrigin, max(0, item.x)); item.y = min(BoardItem.maxOrigin, max(0, item.y))
        item.width = min(BoardItem.maxSize.width, max(BoardItem.minSize.width, item.width))
        item.height = min(BoardItem.maxSize.height, max(BoardItem.minSize.height, item.height))
        let previous = entries
        if let index = entries.firstIndex(where: { $0.id == item.id }) { entries[index] = item }
        else { entries.append(item) }
        if !save() { entries = previous }
    }
    func delete(_ id: UUID) {
        guard canSave else { return }
        let previous = entries; entries.removeAll { $0.id == id }
        if !save() { entries = previous }
    }
    /// Removes every card on one space's Board.
    func clear(spaceID: UUID) {
        guard canSave else { return }
        let previous = entries; entries.removeAll { $0.spaceID == spaceID }
        if !save() { entries = previous }
    }
    func markdown(spaceID: UUID) -> String {
        "# Board\n\n" + items(in: spaceID).map { item in
            let title = item.title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            let heading = item.url.map { "[\(title)](<\($0)>)" } ?? title
            var lines = "- \(heading)"
            if let quote = item.quote, !quote.isEmpty {
                lines += "\n  > " + quote.replacingOccurrences(of: "\n", with: "\n  > ")
            }
            if !item.text.isEmpty { lines += "\n  " + item.text.replacingOccurrences(of: "\n", with: "\n  ") }
            return lines
        }.joined(separator: "\n\n") + "\n"
    }
    private func save() -> Bool {
        guard let file else { return true }
        do { try JSONEncoder().encode(entries).write(to: file, options: .atomic); errorText = nil; return true }
        catch { errorText = error.localizedDescription; return false }
    }
}

// MARK: - Lattice snapping

/// The Board canvas is the hex lattice (`ShellLayout.latticeCell`): a card's origin snaps to
/// the nearest hexagon centre, its width to whole cells and its height to whole row pitches.
enum BoardGrid {
    /// Nearest lattice centre at or right/below the canvas origin.
    static func snap(_ point: CGPoint, cell: CGFloat = ShellLayout.latticeCell) -> CGPoint {
        let pitch = LatticeGeometry.rowPitch(cell: cell)
        let nearestRow = Int((max(0, point.y) / pitch).rounded())
        var best = CGPoint.zero, bestDistance = CGFloat.infinity
        for row in max(0, nearestRow - 1)...(nearestRow + 1) {
            let offset = row.isMultiple(of: 2) ? 0 : cell / 2
            let column = max(0, ((point.x - offset) / cell).rounded())
            let candidate = CGPoint(x: column * cell + offset, y: CGFloat(row) * pitch)
            let distance = hypot(candidate.x - point.x, candidate.y - point.y)
            if distance < bestDistance { best = candidate; bestDistance = distance }
        }
        return best
    }

    /// Width in whole cells and height in whole row pitches, never below `BoardItem.minSize`
    /// nor above `BoardItem.maxSize`.
    static func snap(size: CGSize, cell: CGFloat = ShellLayout.latticeCell) -> CGSize {
        let pitch = LatticeGeometry.rowPitch(cell: cell)
        func fit(_ value: CGFloat, step: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
            let steps = min(floor(upper / step), max(ceil(lower / step), (value / step).rounded()))
            return steps * step
        }
        return CGSize(width: fit(size.width, step: cell, min: BoardItem.minSize.width, max: BoardItem.maxSize.width),
                      height: fit(size.height, step: pitch, min: BoardItem.minSize.height, max: BoardItem.maxSize.height))
    }

    /// The clearance a placed card keeps from every other card: half a cell.
    static let placementGap: CGFloat = ShellLayout.latticeCell / 2
    /// The row width placement fills when the canvas width is unknown: four page cards.
    static var defaultRowWidth: CGFloat {
        let page = BoardItem.defaultSize(for: .page).width
        return 4 * page + 5 * ShellLayout.latticeCell
    }

    /// Where a new card of `size` goes when it arrives without a position: the first lattice
    /// centre, scanning left to right and then top to bottom, whose card frame keeps
    /// `placementGap` clear of every frame in `occupied`. A row ends where the card would pass
    /// `rowWidth` (the first column is always tried). Candidates start half a cell in from the
    /// canvas edge so a card never touches it.
    static func firstFreeOrigin(for size: CGSize, avoiding occupied: [CGRect], rowWidth: CGFloat = defaultRowWidth,
                                cell: CGFloat = ShellLayout.latticeCell) -> CGPoint {
        let pitch = LatticeGeometry.rowPitch(cell: cell)
        let margin = cell / 2, gap = placementGap
        let blocked = occupied.map { $0.insetBy(dx: -gap, dy: -gap) }
        let firstRow = Int(ceil(margin / pitch))
        let lastRow = Int(CGFloat(BoardItem.maxOrigin) / pitch)
        guard firstRow <= lastRow else { return CGPoint(x: margin, y: margin) }
        for row in firstRow...lastRow {
            let y = CGFloat(row) * pitch
            let offset = row.isMultiple(of: 2) ? 0 : cell / 2
            var x = offset
            while x < margin { x += cell }
            let rowStart = x
            while x == rowStart || x + size.width <= rowWidth {
                let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
                if !blocked.contains(where: { $0.intersects(frame) }) { return frame.origin }
                x += cell
                if x > CGFloat(BoardItem.maxOrigin) { break }
            }
        }
        return CGPoint(x: margin, y: CGFloat(lastRow) * pitch)
    }

    /// `item` moved by `translation` and snapped to the lattice.
    static func moved(_ item: BoardItem, by translation: CGSize) -> BoardItem {
        var copy = item
        let point = snap(CGPoint(x: item.x + translation.width, y: item.y + translation.height))
        copy.x = min(BoardItem.maxOrigin, Double(point.x)); copy.y = min(BoardItem.maxOrigin, Double(point.y))
        return copy
    }

    /// `item` resized by `translation` and snapped to the lattice.
    static func resized(_ item: BoardItem, by translation: CGSize) -> BoardItem {
        var copy = item
        let size = snap(size: CGSize(width: item.width + translation.width, height: item.height + translation.height))
        copy.width = Double(size.width); copy.height = Double(size.height)
        return copy
    }
}

// MARK: - Automatic connectors

/// One provenance connector between two cards: `parent`'s page opened `child`'s page.
struct BoardLink: Identifiable, Hashable {
    let parent: UUID
    let child: UUID
    var id: String { "\(parent.uuidString)>\(child.uuidString)" }
}

/// Board connectors derived from the knowledge graph (graphene-language.md §5.6). A connector
/// joins two cards when the most recent visit between their pages' nodes, in either direction,
/// records one as the other's parent. There is no manual connector.
enum BoardLinks {
    /// Corner radius of the connector's elbows.
    static let cornerRadius: CGFloat = 6
    /// Width of the `pageBg` stroke under a connector that clears the lattice beneath it.
    static let knockoutWidth: CGFloat = 3

    /// Links between `cards` (card id and its page's graph node) from `visits`.
    static func derive(cards: [(id: UUID, nodeID: UUID?)], visits: [GraphVisit]) -> [BoardLink] {
        let nodes = Set(cards.compactMap(\.nodeID))
        guard nodes.count > 1 else { return [] }
        struct Pair: Hashable { let parent: UUID; let child: UUID }
        var latest: [Pair: Date] = [:]
        for visit in visits {
            guard let parent = visit.parentNodeID, parent != visit.nodeID, nodes.contains(parent), nodes.contains(visit.nodeID) else { continue }
            let pair = Pair(parent: parent, child: visit.nodeID)
            if latest[pair].map({ visit.date >= $0 }) ?? true { latest[pair] = visit.date }
        }
        guard !latest.isEmpty else { return [] }
        var links: [BoardLink] = []
        for (i, a) in cards.enumerated() {
            guard let nodeA = a.nodeID else { continue }
            for b in cards[(i + 1)...] {
                guard let nodeB = b.nodeID, nodeA != nodeB else { continue }
                let forward = latest[Pair(parent: nodeA, child: nodeB)], backward = latest[Pair(parent: nodeB, child: nodeA)]
                switch (forward, backward) {
                case let (f?, r?): links.append(f >= r ? BoardLink(parent: a.id, child: b.id) : BoardLink(parent: b.id, child: a.id))
                case (.some, nil): links.append(BoardLink(parent: a.id, child: b.id))
                case (nil, .some): links.append(BoardLink(parent: b.id, child: a.id))
                case (nil, nil): break
                }
            }
        }
        return links
    }

    /// Links between `items` using `graph`'s nodes (by canonical URL) and visits.
    @MainActor static func derive(items: [BoardItem], graph: KnowledgeGraph) -> [BoardLink] {
        let cards = items.map { item in (id: item.id, nodeID: item.url.flatMap(URL.init(string:)).flatMap { graph.node(for: $0)?.id }) }
        return derive(cards: cards, visits: graph.visits)
    }

    /// The connector's endpoints: the parent frame's right-edge midpoint and the child frame's
    /// left-edge midpoint.
    static func endpoints(parent: CGRect, child: CGRect) -> (from: CGPoint, to: CGPoint) {
        (CGPoint(x: parent.maxX, y: parent.midY), CGPoint(x: child.minX, y: child.midY))
    }

    /// An elbow from `from` to `to`: out horizontally, across at the midpoint, in horizontally,
    /// with `cornerRadius` corners (smaller when the elbow is too short for them).
    static func path(from: CGPoint, to: CGPoint, radius: CGFloat = cornerRadius) -> Path {
        var path = Path()
        path.move(to: from)
        let midX = (from.x + to.x) / 2
        let dy = to.y - from.y
        let r = min(radius, abs(dy) / 2, abs(midX - from.x))
        guard r > 0 else {
            if abs(dy) < 0.5 { path.addLine(to: to) }
            else { path.addLine(to: CGPoint(x: midX, y: from.y)); path.addLine(to: CGPoint(x: midX, y: to.y)); path.addLine(to: to) }
            return path
        }
        let corner1 = CGPoint(x: midX, y: from.y), corner2 = CGPoint(x: midX, y: to.y)
        path.addArc(tangent1End: corner1, tangent2End: corner2, radius: r)
        path.addArc(tangent1End: corner2, tangent2End: to, radius: r)
        path.addLine(to: to)
        return path
    }
}
