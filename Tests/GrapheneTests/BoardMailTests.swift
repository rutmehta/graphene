import XCTest
import SwiftUI
@testable import Graphene

/// G9 (graphene-language.md §5.6, §5.7): Board connectors from the graph, lattice snapping, card
/// kinds from drops; Mail conversations, collapse counts, the unread dot and child-tab links.
@MainActor
final class BoardMailTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func card(_ url: String, space: UUID) -> BoardItem { BoardItem(spaceID: space, title: url, url: url) }

    // MARK: Board connectors

    func testBoardLinksFollowTheVisitTree() {
        let graph = KnowledgeGraph(file: root.appendingPathComponent("graph.json"), inMemory: true)
        let space = UUID(), start = Date(timeIntervalSince1970: 1_000)
        let a = graph.recordVisit(url: URL(string: "https://a.example/")!, title: "A", spaceID: space, parentNodeID: nil, query: nil, date: start)
        let b = graph.recordVisit(url: URL(string: "https://b.example/")!, title: "B", spaceID: space, parentNodeID: a, query: nil, date: start + 10)
        graph.recordVisit(url: URL(string: "https://c.example/")!, title: "C", spaceID: space, parentNodeID: b, query: nil, date: start + 20)
        graph.recordVisit(url: URL(string: "https://d.example/")!, title: "D", spaceID: space, parentNodeID: nil, query: nil, date: start + 30)
        let cardA = card("https://a.example/", space: space), cardB = card("https://b.example/", space: space)
        let cardC = card("https://c.example/?utm_source=x", space: space), cardD = card("https://d.example/", space: space)

        let links = BoardLinks.derive(items: [cardA, cardB, cardC, cardD], graph: graph)
        XCTAssertEqual(Set(links), [BoardLink(parent: cardA.id, child: cardB.id), BoardLink(parent: cardB.id, child: cardC.id)],
                       "parent→child pairs only, matched by canonical URL; the unrelated page has none")
        XCTAssertEqual(BoardLinks.derive(items: [cardA, cardC], graph: graph), [], "grandparent and grandchild are not joined")
        XCTAssertEqual(BoardLinks.derive(items: [cardB, cardC, cardD], graph: graph), [BoardLink(parent: cardB.id, child: cardC.id)],
                       "deleting A removes its connector and keeps the rest")
        XCTAssertEqual(BoardLinks.derive(items: [cardA, cardB, card("notes", space: space)], graph: graph).count, 1)
    }

    func testBoardLinkDirectionComesFromTheMostRecentVisit() {
        let parent = UUID(), child = UUID(), cardP = UUID(), cardC = UUID(), thread = UUID()
        func visit(_ node: UUID, from: UUID?, at time: TimeInterval) -> GraphVisit {
            GraphVisit(id: UUID(), nodeID: node, threadID: thread, parentNodeID: from, spaceID: nil, date: Date(timeIntervalSince1970: time), query: nil)
        }
        let cards = [(id: cardP, nodeID: Optional(parent)), (id: cardC, nodeID: Optional(child))]
        XCTAssertEqual(BoardLinks.derive(cards: cards, visits: [visit(child, from: parent, at: 1)]), [BoardLink(parent: cardP, child: cardC)])
        XCTAssertEqual(BoardLinks.derive(cards: cards, visits: [visit(child, from: parent, at: 1), visit(parent, from: child, at: 2)]),
                       [BoardLink(parent: cardC, child: cardP)], "a later visit the other way flips the connector")
        XCTAssertEqual(BoardLinks.derive(cards: [(id: cardP, nodeID: Optional(parent)), (id: cardC, nodeID: Optional(parent))],
                                         visits: [visit(parent, from: parent, at: 1)]), [], "no self connectors")
    }

    func testConnectorRunsFromParentRightEdgeToChildLeftEdgeWithSixPointCorners() {
        let ends = BoardLinks.endpoints(parent: CGRect(x: 0, y: 0, width: 100, height: 60), child: CGRect(x: 200, y: 100, width: 100, height: 40))
        XCTAssertEqual(ends.from, CGPoint(x: 100, y: 30))
        XCTAssertEqual(ends.to, CGPoint(x: 200, y: 120))
        XCTAssertEqual(BoardLinks.cornerRadius, 6)
        let bounds = BoardLinks.path(from: ends.from, to: ends.to).boundingRect
        XCTAssertEqual(bounds.minX, 100, accuracy: 0.01); XCTAssertEqual(bounds.maxX, 200, accuracy: 0.01)
        XCTAssertEqual(bounds.minY, 30, accuracy: 0.01); XCTAssertEqual(bounds.maxY, 120, accuracy: 0.01)
        let straight = BoardLinks.path(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 50, y: 10)).boundingRect
        XCTAssertEqual(straight.height, 0, accuracy: 0.01, "level cards get a straight connector")
    }

    // MARK: Snapping

    func testCardsSnapToTheLattice() {
        let cell = ShellLayout.latticeCell, pitch = LatticeGeometry.rowPitch(cell: cell)
        XCTAssertEqual(BoardGrid.snap(CGPoint(x: 30, y: 2)), CGPoint(x: cell, y: 0))
        let odd = BoardGrid.snap(CGPoint(x: 40, y: pitch + 3))
        XCTAssertEqual(odd.x, cell * 1.5, accuracy: 0.001, "odd rows are offset half a cell")
        XCTAssertEqual(odd.y, pitch, accuracy: 0.001)
        XCTAssertEqual(BoardGrid.snap(CGPoint(x: -20, y: -20)), .zero)
        for point in [CGPoint(x: 123, y: 77), CGPoint(x: 611, y: 402)] {
            let snapped = BoardGrid.snap(point)
            XCTAssertTrue(LatticeGeometry.centers(in: CGSize(width: 1000, height: 1000), cell: cell).contains { hypot($0.x - snapped.x, $0.y - snapped.y) < 0.001 },
                          "\(point) snaps onto a lattice centre")
        }

        let size = BoardGrid.snap(size: CGSize(width: 250, height: 200))
        XCTAssertEqual(size.width, 9 * cell, accuracy: 0.001)
        XCTAssertEqual(size.height, 8 * pitch, accuracy: 0.001)
        let tiny = BoardGrid.snap(size: CGSize(width: 10, height: 10))
        XCTAssertGreaterThanOrEqual(tiny.width, BoardItem.minSize.width); XCTAssertGreaterThanOrEqual(tiny.height, BoardItem.minSize.height)
        XCTAssertEqual(tiny.width.truncatingRemainder(dividingBy: cell), 0, accuracy: 0.001)
        let huge = BoardGrid.snap(size: CGSize(width: 5000, height: 5000))
        XCTAssertLessThanOrEqual(huge.width, BoardItem.maxSize.width); XCTAssertLessThanOrEqual(huge.height, BoardItem.maxSize.height)

        var item = BoardItem(spaceID: UUID(), title: "Card"); item.x = 0; item.y = 0
        let moved = BoardGrid.moved(item, by: CGSize(width: 57, height: 1))
        XCTAssertEqual(moved.x, 2 * cell, accuracy: 0.001); XCTAssertEqual(moved.y, 0, accuracy: 0.001)
        let resized = BoardGrid.resized(item, by: CGSize(width: 20, height: 30))
        XCTAssertEqual(resized.width.truncatingRemainder(dividingBy: cell), 0, accuracy: 0.001)
    }

    // MARK: Placement

    func testNewCardsTakeTheFirstFreeLatticeCell() {
        let cell = ShellLayout.latticeCell, pitch = LatticeGeometry.rowPitch(cell: cell)
        let size = BoardItem.defaultSize(for: .page)
        let first = BoardGrid.firstFreeOrigin(for: size, avoiding: [], rowWidth: 1000)
        XCTAssertEqual(first.x, cell / 2, accuracy: 0.001, "the first cell, half a cell in from the edge")
        XCTAssertEqual(first.y, pitch, accuracy: 0.001)
        XCTAssertEqual(BoardGrid.snap(first), first, "on a lattice centre")

        var frames = [CGRect(origin: first, size: size)]
        let second = BoardGrid.firstFreeOrigin(for: size, avoiding: frames, rowWidth: 1000)
        XCTAssertEqual(second.y, first.y, accuracy: 0.001, "left to right before top to bottom")
        XCTAssertGreaterThanOrEqual(second.x, frames[0].maxX + BoardGrid.placementGap)
        XCTAssertLessThan(second.x, frames[0].maxX + BoardGrid.placementGap + cell, "the nearest free cell, not a later one")
        frames.append(CGRect(origin: second, size: size))
        let third = BoardGrid.firstFreeOrigin(for: size, avoiding: frames, rowWidth: 1000)
        XCTAssertEqual(third.y, first.y, accuracy: 0.001)
        frames.append(CGRect(origin: third, size: size))
        let wrapped = BoardGrid.firstFreeOrigin(for: size, avoiding: frames, rowWidth: 1000)
        XCTAssertGreaterThan(wrapped.y, first.y, "a full row wraps to the next free row")
        XCTAssertLessThanOrEqual(wrapped.x, cell, "at the start of the row")
        for frame in frames {
            XCTAssertFalse(frame.intersects(CGRect(origin: wrapped, size: size)), "never overlaps a card")
        }

        // A gap between cards is used before the rows below them.
        let hole = [CGRect(x: 0, y: 0, width: 200, height: 300), CGRect(x: 600, y: 0, width: 200, height: 300)]
        let note = BoardItem.defaultSize(for: .note)
        let filled = BoardGrid.firstFreeOrigin(for: note, avoiding: hole, rowWidth: 1000)
        XCTAssertLessThan(filled.y, 300, "fits between the two cards")
        XCTAssertGreaterThan(filled.x, 200); XCTAssertLessThan(filled.x + note.width, 600)

        // A narrow canvas still places the card, in the first column.
        let narrow = BoardGrid.firstFreeOrigin(for: size, avoiding: [], rowWidth: 100)
        XCTAssertEqual(narrow.x, cell / 2, accuracy: 0.001)
    }

    func testAddWithoutAPositionNeverOverlapsAndDropsKeepTheirCell() throws {
        let app = AppState(directory: root)
        let a = app.addBoardCard(BoardDropCard(kind: .page, title: "A", url: "https://example.org/a"), rowWidth: 1200)
        let b = app.addBoardCard(BoardDropCard(kind: .page, title: "B", url: "https://example.org/b"), rowWidth: 1200)
        let note = app.addBoardCard(BoardDropCard(kind: .note, title: "Note"), rowWidth: 1200)
        let frames = app.boards.items(in: app.activeSpaceID).map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        XCTAssertEqual(frames.count, 3)
        for (i, f) in frames.enumerated() { for g in frames[(i + 1)...] { XCTAssertFalse(f.intersects(g), "\(f) overlaps \(g)") } }
        XCTAssertEqual(a.y, b.y, accuracy: 0.001); XCTAssertGreaterThan(b.x, a.x)
        XCTAssertGreaterThan(note.x, b.x, "Add note goes beside the cards, not over them")

        let dropped = app.addBoardCard(BoardDropCard(kind: .note, title: "Dropped"), at: CGPoint(x: 40, y: 30))
        XCTAssertEqual(CGPoint(x: dropped.x, y: dropped.y), BoardGrid.snap(CGPoint(x: 40, y: 30)), "a drop keeps its snapped position")
    }

    func testVaultAddToBoardMakesAQuoteCard() throws {
        let app = AppState(directory: root)
        app.vault.add(text: "Graphene is a single layer of carbon.", note: "for the intro", url: URL(string: "https://en.wikipedia.org/wiki/Graphene"),
                      title: "Graphene - Wikipedia", context: "", spaceID: app.activeSpaceID)
        let note = try XCTUnwrap(app.vault.annotations.first)
        let existing = app.addBoardCard(BoardDropCard(kind: .page, title: "Graphene - Wikipedia", url: "https://en.wikipedia.org/wiki/Graphene"))
        let item = try XCTUnwrap(app.addNoteToBoard(note.id))
        XCTAssertEqual(item.kind, .quote, "a quote card, not a page card")
        XCTAssertEqual(item.cardKind, .quote)
        XCTAssertEqual(item.quote, "Graphene is a single layer of carbon.")
        XCTAssertEqual(item.text, "for the intro")
        XCTAssertEqual(BoardCardText.provenance(item), "Graphene - Wikipedia · en.wikipedia.org")
        XCTAssertEqual(CGSize(width: item.width, height: item.height), BoardItem.defaultSize(for: .quote))
        XCTAssertFalse(CGRect(x: item.x, y: item.y, width: item.width, height: item.height)
            .intersects(CGRect(x: existing.x, y: existing.y, width: existing.width, height: existing.height)))
        XCTAssertEqual(app.boards.items(in: app.activeSpaceID).last, item, "saved")
        XCTAssertNil(app.addNoteToBoard(UUID()), "a deleted note adds nothing")

        let vault = try String(contentsOf: Self.sources.appendingPathComponent("UI/VaultView.swift"), encoding: .utf8)
        XCTAssertTrue(vault.contains("app.addNoteToBoard(note.id)"), "the Vault bar action uses the drop path")
    }

    private static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/Graphene")

    func testConnectorSitsAboveTheLatticeOnAKnockout() throws {
        let easel = try String(contentsOf: Self.sources.appendingPathComponent("UI/EaselView.swift"), encoding: .utf8)
        let lattice = try XCTUnwrap(easel.range(of: "Lattice(fade: false)"))
        let knockout = try XCTUnwrap(easel.range(of: ".stroke(app.pal.pageBg, lineWidth: BoardLinks.knockoutWidth)"))
        let line = try XCTUnwrap(easel.range(of: ".stroke(app.pal.threadLine, lineWidth: ShellLayout.hairline)"))
        XCTAssertLessThan(lattice.lowerBound, knockout.lowerBound, "drawn after (above) the lattice")
        XCTAssertLessThan(knockout.lowerBound, line.lowerBound, "the threadLine stroke sits on the knockout")
        XCTAssertGreaterThan(BoardLinks.knockoutWidth, ShellLayout.hairline)
    }

    // MARK: Card kinds

    func testDropPayloadsMakeTheRightCardKind() throws {
        let app = AppState(directory: root)
        app.vault.add(text: "Quoted words", note: "Mine", url: URL(string: "https://example.org/q"), title: "Source", context: "", spaceID: app.activeSpaceID)
        app.vault.add(text: " ", note: "Only a note", url: URL(string: "https://example.org/n"), title: "Loose", context: "", spaceID: app.activeSpaceID)
        let quote = try XCTUnwrap(app.vault.annotations.first { $0.title == "Source" })
        let note = try XCTUnwrap(app.vault.annotations.first { $0.title == "Loose" })
        XCTAssertEqual(app.boardDropCard(for: "note:\(quote.id)")?.kind, .quote)
        XCTAssertEqual(app.boardDropCard(for: "note:\(quote.id)")?.quote, "Quoted words")
        XCTAssertEqual(app.boardDropCard(for: "note:\(note.id)")?.kind, .note)
        XCTAssertEqual(app.boardDropCard(for: "https://example.org/page")?.kind, .page)
        XCTAssertEqual(app.boardDropCard(for: "Just words")?.kind, .note)
        app.openTab(url: URL(string: "https://example.org/tab")!, parent: nil, activate: false)
        let tab = try XCTUnwrap(app.tabs.first { $0.url?.absoluteString == "https://example.org/tab" })
        XCTAssertEqual(app.boardDropCard(for: "tab:\(tab.id)")?.kind, .page)
    }

    func testBoardItemsDecodeWithoutAKindAndInferIt() throws {
        let space = UUID()
        let legacy = #"[{"id":"\#(UUID())","spaceID":"\#(space)","title":"Old","text":"","url":"https://e.org","x":1,"y":2,"width":240,"height":180},"# +
            #"{"id":"\#(UUID())","spaceID":"\#(space)","title":"Plain","text":"t","x":1,"y":2,"width":240,"height":180}]"#
        let items = try JSONDecoder().decode([BoardItem].self, from: Data(legacy.utf8))
        XCTAssertEqual(items.map(\.cardKind), [.page, .note])
        var quote = BoardItem(spaceID: space, title: "Source", url: "https://www.example.org/a"); quote.kind = .quote; quote.quote = "Words"
        let round = try JSONDecoder().decode(BoardItem.self, from: JSONEncoder().encode(quote))
        XCTAssertEqual(round.cardKind, .quote); XCTAssertEqual(round.quote, "Words")
        XCTAssertEqual(BoardCardText.provenance(round), "Source · example.org")
        XCTAssertEqual(ShellLayout.boardCardRadius, ShellLayout.popoverRadius)
    }

    func testClearAndExportKeepQuotes() {
        let store = BoardStore(file: nil), space = UUID(), other = UUID()
        var quote = BoardItem(spaceID: space, title: "Source", text: "Mine", url: "https://e.org"); quote.kind = .quote; quote.quote = "Line one\nLine two"
        store.upsert(quote); store.upsert(BoardItem(spaceID: other, title: "Elsewhere"))
        XCTAssertTrue(store.markdown(spaceID: space).contains("  > Line one\n  > Line two\n  Mine"))
        store.clear(spaceID: space)
        XCTAssertTrue(store.items(in: space).isEmpty)
        XCTAssertEqual(store.items(in: other).count, 1)
    }

    // MARK: Mail

    private func message(_ id: String, thread: String?, subject: String = "Plans", minutes: Double, unread: Bool = false) -> MailItem {
        MailItem(id: id, from: "Ana", address: "ana@example.org", subject: subject, preview: "…", date: Date(timeIntervalSince1970: minutes * 60),
                 unread: unread, initial: "A", colorHex: "000000", body: [], threadID: thread)
    }

    func testConversationsGroupByThreadThenSubject() {
        let items = [message("1", thread: "t1", minutes: 1), message("2", thread: "t2", subject: "Other", minutes: 5),
                     message("3", thread: "t1", subject: "Re: Plans", minutes: 9),
                     message("4", thread: nil, subject: "Lunch", minutes: 2), message("5", thread: nil, subject: "RE: fwd:  lunch", minutes: 3)]
        let conversations = MailConversation.group(items)
        XCTAssertEqual(conversations.map(\.id), ["thread:t1", "thread:t2", "subject:lunch"], "newest activity first")
        XCTAssertEqual(conversations[0].messages.map(\.id), ["1", "3"], "oldest first: the first message heads the thread")
        XCTAssertEqual(conversations[2].messages.map(\.id), ["4", "5"])
        XCTAssertEqual(MailConversation.normalizedSubject("Re[2]: Fw: Budget"), "budget")
    }

    func testConversationsCollapseToTheLatestThreeReplies() throws {
        let items = (0..<6).map { message("m\($0)", thread: "t", minutes: Double($0)) }
        let conversation = try XCTUnwrap(MailConversation.group(items).first)
        XCTAssertEqual(conversation.hiddenCount(expanded: false), 2)
        XCTAssertEqual(conversation.visibleReplies(expanded: false).map(\.id), ["m3", "m4", "m5"])
        XCTAssertEqual(conversation.rows(expanded: false).map(\.id), ["m0", "more", "m3", "m4", "m5"])
        XCTAssertEqual(conversation.hiddenCount(expanded: true), 0)
        XCTAssertEqual(conversation.rows(expanded: true).map(\.id), ["m0", "fewer", "m1", "m2", "m3", "m4", "m5"])
        if case .more(let count) = conversation.rows(expanded: false)[1] { XCTAssertEqual(count, 2) } else { XCTFail("expected the N more row") }

        let connector = try XCTUnwrap(conversation.connector(expanded: false))
        XCTAssertEqual(connector.childRows, [2, 3, 4])
        XCTAssertEqual(connector.vertical.minY, MailLayout.rowHeight / 2 + ShellLayout.iconSlot / 2, accuracy: 0.001)
        XCTAssertEqual(connector.ticks.first?.midY ?? 0, 2 * MailLayout.rowHeight + MailLayout.rowHeight / 2, accuracy: 0.001)
        XCTAssertEqual(connector.x, ShellLayout.threadLineInset)
        XCTAssertEqual(MailLayout.rowHeight, 44)

        let short = try XCTUnwrap(MailConversation.group(Array(items.prefix(3))).first)
        XCTAssertEqual(short.hiddenCount(expanded: false), 0)
        XCTAssertEqual(short.rows(expanded: true).map(\.id), ["m0", "m1", "m2"], "no toggle for three or fewer replies")
        XCTAssertNil(MailConversation.group([items[0]]).first?.connector(expanded: false), "a lone message has no connector")
    }

    func testUnreadDotRule() {
        XCTAssertTrue(message("u", thread: nil, minutes: 0, unread: true).showsUnreadDot)
        XCTAssertFalse(message("r", thread: nil, minutes: 0).showsUnreadDot)
    }

    func testMailLinksOpenAsChildTabsOfTheCurrentTab() throws {
        let app = AppState(directory: root)
        app.openTab(url: URL(string: "https://example.org/current")!, parent: nil, activate: true)
        let current = try XCTUnwrap(app.activeTab)
        app.show(.mail)
        app.openMailLink(URL(string: "https://example.org/from-mail")!)
        let child = try XCTUnwrap(app.tabs.first { $0.url?.absoluteString == "https://example.org/from-mail" })
        XCTAssertEqual(child.parentTabID, current.id)
        XCTAssertEqual(app.activeTabID, child.id)
        let count = app.tabs.count
        app.openMailLink(URL(string: "mailto:someone@example.org")!)
        XCTAssertEqual(app.tabs.count, count, "only web links open")
    }
}
