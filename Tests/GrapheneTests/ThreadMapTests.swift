import XCTest
import CoreGraphics
import SwiftUI
import AppKit
@testable import Graphene

/// G6 Thread map (graphene-language.md §5.2): the tree layout from a thread's visits, its
/// connector geometry, the ancestor path, Resume from a node, and summary citations.
@MainActor
final class ThreadMapTests: XCTestCase {
    private var directory: URL!
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func visit(_ node: UUID, parent: UUID?, minute: Double, query: String? = nil, thread: UUID) -> GraphVisit {
        GraphVisit(id: UUID(), nodeID: node, threadID: thread, parentNodeID: parent, spaceID: nil,
                   date: start.addingTimeInterval(minute * 60), query: query)
    }

    /// The acceptance tree: A, then B and C from A, then D from C.
    private func acceptance() -> (ThreadLayout, a: UUID, b: UUID, c: UUID, d: UUID) {
        let thread = UUID(), a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let visits = [visit(a, parent: nil, minute: 0, thread: thread), visit(b, parent: a, minute: 1, thread: thread),
                      visit(c, parent: a, minute: 2, thread: thread), visit(d, parent: c, minute: 3, thread: thread)]
        return (ThreadLayout(nodeIDs: [a, b, c, d], visits: visits), a, b, c, d)
    }

    // MARK: layout

    func testRowsAndColumnsFromAVisitTree() throws {
        let (layout, a, b, c, d) = acceptance()
        XCTAssertEqual(layout.nodes.map(\.id), [a, b, c, d])
        XCTAssertEqual(layout.nodes.map(\.column), [0, 1, 1, 2], "A at column 0, B and C at 1, D at 2")
        XCTAssertEqual(layout.nodes.map(\.row), [1, 2, 3, 4], "row 0 holds the start label above the first root")
        XCTAssertEqual(layout.nodes.map(\.parentID), [nil, a, a, c])
        XCTAssertEqual(Set(layout.nodes.map(\.rootID)), [a])
        XCTAssertEqual(layout.headers.count, 1)
        XCTAssertEqual(layout.headers.first?.row, 0)
        XCTAssertEqual(layout.headers.first?.start, start)
        XCTAssertNil(layout.headers.first?.query)
        XCTAssertEqual(layout.rowCount, 5)
        XCTAssertEqual(layout.columnCount, 3)

        let dNode = try XCTUnwrap(layout.node(d))
        XCTAssertEqual(dNode.origin, CGPoint(x: 2 * ShellLayout.threadColumn, y: 4 * ShellLayout.threadRowPitch))
        XCTAssertEqual(dNode.centre, CGPoint(x: 360 + ShellLayout.threadNodeSize / 2, y: 160 + ShellLayout.threadRowPitch / 2))
        XCTAssertEqual(layout.size, CGSize(width: 540, height: 200))
        XCTAssertEqual(ShellLayout.threadNodeSize, 20)
        XCTAssertEqual(ShellLayout.threadColumn, 180)
        XCTAssertEqual(ShellLayout.threadRowPitch, 40)
    }

    func testABranchIsContiguousUnderItsParent() {
        let thread = UUID(), a = UUID(), b = UUID(), c = UUID(), b1 = UUID()
        // B1 is opened from B after C was opened from A: it still sits directly under B.
        let visits = [visit(a, parent: nil, minute: 0, thread: thread), visit(b, parent: a, minute: 1, thread: thread),
                      visit(c, parent: a, minute: 2, thread: thread), visit(b1, parent: b, minute: 3, thread: thread)]
        let layout = ThreadLayout(nodeIDs: [a, b, c, b1], visits: visits)
        XCTAssertEqual(layout.nodes.map(\.id), [a, b, b1, c])
        XCTAssertEqual(layout.nodes.map(\.column), [0, 1, 2, 1])
    }

    func testSearchesStartRootsWithTheQueryAbove() {
        let thread = UUID(), a = UUID(), b = UUID(), search = UUID(), result = UUID()
        let visits = [visit(a, parent: nil, minute: 0, thread: thread), visit(b, parent: a, minute: 1, thread: thread),
                      visit(search, parent: b, minute: 2, query: "hex lattice", thread: thread),
                      visit(result, parent: search, minute: 3, thread: thread)]
        let layout = ThreadLayout(nodeIDs: [a, b, search, result], visits: visits)
        XCTAssertEqual(layout.nodes.map(\.column), [0, 1, 0, 1], "a search is a root even though it had a parent")
        XCTAssertEqual(layout.headers.map(\.row), [0, 3])
        XCTAssertEqual(layout.headers.map(\.query), [nil, "hex lattice"])
        XCTAssertEqual(layout.headers.map(\.start), [start, nil], "one start label, over the first root")
        XCTAssertEqual(layout.nodes.map(\.row), [1, 2, 4, 5])
        XCTAssertNil(layout.node(search)?.parentID)
    }

    func testOnlyTheFirstVisitPlacesANodeAndCyclesStayVisible() {
        let thread = UUID(), a = UUID(), b = UUID()
        // A later revisit of A from B must not move A under B.
        let visits = [visit(a, parent: nil, minute: 0, thread: thread), visit(b, parent: a, minute: 1, thread: thread),
                      visit(a, parent: b, minute: 2, thread: thread)]
        XCTAssertEqual(ThreadLayout(nodeIDs: [a, b], visits: visits).nodes.map(\.column), [0, 1])
        // Legacy data where each first visit names the other as parent still shows both.
        let cycle = [visit(a, parent: b, minute: 0, thread: thread), visit(b, parent: a, minute: 1, thread: thread)]
        let layout = ThreadLayout(nodeIDs: [a, b], visits: cycle)
        XCTAssertEqual(Set(layout.nodes.map(\.id)), [a, b])
        XCTAssertEqual(layout.ancestors(of: b).count, layout.node(b).map { $0.column + 1 })
        // Parents outside the thread do not count.
        let outside = [visit(a, parent: UUID(), minute: 0, thread: thread)]
        XCTAssertNil(ThreadLayout(nodeIDs: [a], visits: outside).node(a)?.parentID)
    }

    // MARK: connectors

    func testConnectorGeometry() throws {
        let (layout, a, b, c, d) = acceptance()
        XCTAssertEqual(layout.connectors.map(\.parentID), [a, c], "one path per parent")
        let fromA = try XCTUnwrap(layout.connectors.first { $0.parentID == a })
        XCTAssertEqual(fromA.childIDs, [b, c])
        XCTAssertEqual(fromA.x, 10, "down the centre of A's favicon slot")
        XCTAssertEqual(fromA.top, 40 + 20 + 10, "from the bottom of A's slot")
        XCTAssertEqual(fromA.childYs, [100, 140])
        XCTAssertEqual(fromA.bottom, 140, "to the last child's row")
        XCTAssertEqual(fromA.endX, 180, "into the child's slot at column 1")
        XCTAssertEqual(ThreadConnector.cornerRadius, 6)
        XCTAssertEqual(fromA.path().boundingBoxOfPath, CGRect(x: 10, y: 70, width: 170, height: 70))

        let fromC = try XCTUnwrap(layout.connectors.first { $0.parentID == c })
        XCTAssertEqual(fromC.childIDs, [d])
        XCTAssertEqual(fromC.path().boundingBoxOfPath, CGRect(x: 190, y: 150, width: 170, height: 30))

        // An elbow alone: vertical, a 6pt corner, then the horizontal.
        let toB = fromA.path(to: [b])
        XCTAssertEqual(toB.boundingBoxOfPath, CGRect(x: 10, y: 70, width: 170, height: 30))
        XCTAssertTrue(strokeContains(toB, CGPoint(x: 10, y: 80)))
        XCTAssertTrue(strokeContains(toB, CGPoint(x: 100, y: 100)))
        XCTAssertFalse(strokeContains(toB, CGPoint(x: 10, y: 100)), "the corner is rounded, not square")
        XCTAssertTrue(fromA.path(to: []).isEmpty)
    }

    private func strokeContains(_ path: CGPath, _ point: CGPoint) -> Bool {
        path.copy(strokingWithWidth: 1, lineCap: .butt, lineJoin: .miter, miterLimit: 10).contains(point)
    }

    // MARK: ancestor path

    func testAncestorPathOfTheSelectedNode() {
        let (layout, a, b, c, d) = acceptance()
        XCTAssertEqual(layout.ancestors(of: d), [a, c, d], "clicking D marks A→C→D")
        XCTAssertEqual(layout.ancestors(of: a), [a])
        XCTAssertEqual(layout.ancestors(of: UUID()), [])
        XCTAssertEqual(layout.activeChildren(selected: d), [a: c, c: d])
        XCTAssertEqual(layout.activeChildren(selected: b), [a: b])
        XCTAssertEqual(layout.activeChildren(selected: nil), [:])
        XCTAssertEqual(layout.branch(from: c).map(\.id), [c, d])
        XCTAssertEqual(layout.branch(from: a).map(\.id), [a, b, c, d])
        XCTAssertEqual(layout.branch(from: b).map(\.id), [b])
    }

    // MARK: text and motion

    func testNodeTextStartLabelAndMotion() {
        XCTAssertEqual(ThreadLayout.truncatedTitle("Short title"), "Short title")
        let long = ThreadLayout.truncatedTitle("A title that runs well past the map's limit")
        XCTAssertEqual(long.count, 26)
        XCTAssertTrue(long.hasSuffix("…"))
        // Tuesday 22 September 2026, 14:05 UTC.
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 14, minute: 5))!
        XCTAssertEqual(ThreadLayout.startLabel(date, locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!), "Tue 14:05")
        XCTAssertEqual(ThreadLayout.fadeDelay(column: 0), 0)
        XCTAssertEqual(ThreadLayout.fadeDelay(column: 2), 0.08, accuracy: 0.0001)
        XCTAssertEqual(ThreadLayout.fadeDelay(column: 12), 0.2, "the stagger is capped at 200ms")
        XCTAssertEqual(ThreadLayout.connectorDraw, 0.2)
        XCTAssertEqual(ThreadLayout.recolour, 0.12)
        XCTAssertEqual(ThreadLayout.summaryWidth, 320)
        XCTAssertEqual(ThreadLayout.hoverCardWidth, 320)
    }

    // MARK: citations

    func testSummaryCitationsMapToNodes() {
        let a = UUID(), b = UUID(), elsewhere = UUID()
        let sources = [KnowledgeSource(id: a, title: "A", url: "https://a.invalid", text: "alpha", kind: "Thread"),
                       KnowledgeSource(id: elsewhere, title: "E", url: "https://e.invalid", text: "echo", kind: "Thread"),
                       KnowledgeSource(id: b, title: "B", url: "https://b.invalid", text: "bravo", kind: "Thread")]
        let citations = ThreadSummaryView.citations("Bravo comes later [3]. Alpha first [1]. Echo [2].", sources: sources, threadID: UUID())
        XCTAssertEqual(citations.map(\.index), citations.map(\.sourceNumber), "chips carry the model's source numbers")
        let nodes: Set<UUID> = [a, b]
        let mapped = Dictionary(uniqueKeysWithValues: citations.map { ($0.sourceNumber, ThreadLayout.nodeID(for: $0, sources: sources, in: nodes)) })
        XCTAssertEqual(mapped[1], a)
        XCTAssertEqual(mapped[3], b)
        XCTAssertEqual(mapped[2], .some(nil), "a source that is not a map node highlights nothing")
        var outOfRange = citations[0]; outOfRange.sourceNumber = 9
        XCTAssertNil(ThreadLayout.nodeID(for: outOfRange, sources: sources, in: nodes))
    }

    // MARK: actions

    /// Records A, B and C from A, D from C in the app's graph and returns the thread.
    private func recordAcceptance(_ app: AppState) throws -> (KnowledgeGraph.Thread, [String: UUID]) {
        var ids: [String: UUID] = [:]
        func record(_ name: String, parent: String?, minute: Double) {
            ids[name] = app.graph.recordVisit(url: URL(string: "https://map.invalid/\(name)")!, title: name.uppercased(),
                                              spaceID: app.activeSpaceID, parentNodeID: parent.flatMap { ids[$0] }, query: nil,
                                              date: Date().addingTimeInterval(minute * 60 - 600))
        }
        record("a", parent: nil, minute: 0); record("b", parent: "a", minute: 1)
        record("c", parent: "a", minute: 2); record("d", parent: "c", minute: 3)
        let thread = try XCTUnwrap(app.currentThreads.first { $0.nodes.count == 4 })
        return (thread, ids)
    }

    func testResumeFromANodeOpensItsBranchAsLinkedTodayTabs() throws {
        let app = AppState(directory: directory)
        let (thread, ids) = try recordAcceptance(app)
        let before = app.tabs.count
        let opened = app.resumeThread(from: ids["c"]!, in: thread)
        XCTAssertEqual(opened.map { $0.url?.lastPathComponent }, ["c", "d"], "C and D, not A or B")
        XCTAssertEqual(app.tabs.count, before + 2)
        let (c, d) = (opened[0], opened[1])
        XCTAssertNil(c.parentTabID)
        XCTAssertEqual(d.parentTabID, c.id, "D is C's child tab")
        XCTAssertEqual(app.activeTabID, c.id)
        XCTAssertTrue(opened.allSatisfy { $0.section == .today && $0.resumeThreadID == thread.id && $0.currentThreadID == thread.id })
        XCTAssertEqual(c.currentNodeID, ids["a"], "the revisit of C is recorded under A")
        XCTAssertEqual(d.currentNodeID, ids["c"])
        let rows = app.todayProvenance().rows
        XCTAssertEqual(rows.first { $0.id == d.id }?.depth, 1, "the sidebar draws D indented under C")
        XCTAssertEqual(rows.first { $0.id == d.id }?.parentID, c.id)

        XCTAssertTrue(app.resumeThread(from: UUID(), in: thread).isEmpty)
    }

    func testClickAndCommandClickOpenANode() throws {
        let app = AppState(directory: directory)
        let (thread, ids) = try recordAcceptance(app)
        let current = app.newTab()
        let count = app.tabs.count
        app.openThreadNode(ids["d"]!, in: thread, asChild: false)
        XCTAssertEqual(app.tabs.count, count, "a click loads the page in the current tab")
        XCTAssertEqual(current.url?.lastPathComponent, "d")
        XCTAssertEqual(current.currentNodeID, ids["c"])
        XCTAssertEqual(current.resumeThreadID, thread.id)

        app.openThreadNode(ids["b"]!, in: thread, asChild: true)
        XCTAssertEqual(app.tabs.count, count + 1)
        let child = try XCTUnwrap(app.activeTab)
        XCTAssertEqual(child.url?.lastPathComponent, "b")
        XCTAssertEqual(child.parentTabID, current.id, "⌘-click opens a child of the current tab")
    }

    func testNoteOpensTheVaultNoteOrStartsOne() throws {
        let app = AppState(directory: directory)
        let (thread, ids) = try recordAcceptance(app)
        app.openThreadNote(ids["a"]!, in: thread)
        XCTAssertTrue(app.noteComposerPresented, "no note yet: the page opens with the composer")
        XCTAssertEqual(app.activeTab?.url?.lastPathComponent, "a")
        app.noteComposerPresented = false

        app.vault.add(text: "A quote", note: "", url: URL(string: "https://map.invalid/b"), title: "B", context: "", spaceID: app.activeSpaceID)
        let note = try XCTUnwrap(app.vault.annotations(forURL: "https://map.invalid/b").first)
        app.openThreadNote(ids["b"]!, in: thread)
        XCTAssertEqual(app.vaultSelectionID, note.id)
        XCTAssertEqual(app.activeSurface, .vault)
        XCTAssertFalse(app.noteComposerPresented)
    }

    // MARK: panes and click semantics (language verification fixes)

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private func ledgerSource() throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent("Sources/Graphene/UI/LedgerView.swift"), encoding: .utf8)
    }

    func testThreadListIsATokenWideColumn() throws {
        XCTAssertEqual(ShellLayout.threadListWidth, 260)
        XCTAssertEqual(ThreadPanes.listWidth, ShellLayout.threadListWidth)
        let source = try ledgerSource()
        XCTAssertTrue(source.contains(".frame(width: ThreadPanes.listWidth)"), "the thread list is sized by the token")
        XCTAssertNil(source.range(of: #"\.frame\(width:\s*[0-9]"#, options: .regularExpression), "no literal pane widths")
    }

    func testHeaderIsASingleStripUnderTheLibraryBar() throws {
        XCTAssertEqual(ShellLayout.threadHeaderHeight, 44)
        XCTAssertEqual(ThreadPanes.headerHeight, ShellLayout.threadHeaderHeight)
        XCTAssertEqual(ThreadPanes.counts(pages: 4, sites: 1, notes: 2), "4 pages · 1 site · 2 notes")
        XCTAssertEqual(ThreadPanes.counts(pages: 1, sites: 2, notes: 0), "1 page · 2 sites · 0 notes")
        let app = AppState(directory: directory)
        let (thread, _) = try recordAcceptance(app)
        let host = NSHostingView(rootView: ThreadHeaderStrip(thread: thread, notes: 2).environmentObject(app))
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 200)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, ShellLayout.threadHeaderHeight, accuracy: 0.5, "title, counts and Continue browsing share one 44pt row")
        let source = try ledgerSource()
        XCTAssertTrue(source.contains("ThreadHeaderStrip(thread: thread, notes: notes.count)"), "the detail shows the header strip")
    }

    func testSummaryColumnAppearsOnlyWithASummary() {
        XCTAssertFalse(ThreadPanes.showsSummary(text: "", working: false, error: nil), "no summary yet: the tree has the whole width")
        XCTAssertFalse(ThreadPanes.showsSummary(text: "", working: false, error: ""))
        XCTAssertTrue(ThreadPanes.showsSummary(text: "", working: true, error: nil), "streaming")
        XCTAssertTrue(ThreadPanes.showsSummary(text: "A summary [1].", working: false, error: nil), "a summary exists")
        XCTAssertTrue(ThreadPanes.showsSummary(text: "", working: false, error: "No provider"), "an error has somewhere to show")
        XCTAssertFalse(ThreadSummaryModel().showsColumn)
    }

    func testPanesAreSeparatedBySpaceNotRules() throws {
        let source = try ledgerSource()
        XCTAssertNil(source.range(of: #"Rectangle\(\)\.fill\(app\.pal\.hairline\)\.frame\(width:"#, options: .regularExpression), "no vertical pane dividers")
        let rows = try XCTUnwrap(source.range(of: "private struct ThreadRow")).lowerBound
        XCTAssertFalse(source[..<rows].contains("app.pal.hairline"), "no Saved on this Mac divider")
        XCTAssertFalse(source.contains("fillSelectedStroke"), "the selected node has no outline")
        XCTAssertTrue(source.contains("selected ? app.pal.tileFill"), "the selected node's fill shows on the white card")
        let light = Palette(mode: .light, space: .graphite)
        XCTAssertEqual(light.tileFill, light.rowHover, "light tileFill is the visible rowHover, not translucent white")
    }

    func testClickTable() {
        XCTAssertEqual(ThreadNodeClick.action(clickCount: 1, command: false), .select)
        XCTAssertEqual(ThreadNodeClick.action(clickCount: 1, command: true), .select)
        XCTAssertEqual(ThreadNodeClick.action(clickCount: 2, command: false), .open)
        XCTAssertEqual(ThreadNodeClick.action(clickCount: 2, command: true), .openAsChild)
        XCTAssertEqual(ThreadNodeClick.action(clickCount: 3, command: false), .open)
        XCTAssertEqual(ThreadNodeClick.action(clickCount: 0, command: false), .select)
    }

    func testClickSelectsAndStaysInThreadsDoubleClickOpens() throws {
        let app = AppState(directory: directory)
        let (thread, ids) = try recordAcceptance(app)
        let current = app.newTab()
        let before = current.url, count = app.tabs.count
        app.show(.threads)

        XCTAssertFalse(app.openSelectedThreadNode(in: thread), "Return with nothing selected does nothing")
        app.clickThreadNode(ids["d"]!, in: thread, clickCount: 1, command: false)
        XCTAssertEqual(app.selectedThreadNodeID, ids["d"])
        XCTAssertEqual(app.activeSurface, .threads, "a single click keeps the map on screen")
        XCTAssertEqual(current.url, before, "and does not load the page")
        XCTAssertEqual(app.threadLayout(thread).activeChildren(selected: app.selectedThreadNodeID), [ids["a"]!: ids["c"]!, ids["c"]!: ids["d"]!])

        app.clickThreadNode(ids["d"]!, in: thread, clickCount: 2, command: false)
        XCTAssertEqual(app.activeSurface, .web, "a double-click opens the page")
        XCTAssertEqual(app.tabs.count, count, "in the current tab")
        XCTAssertEqual(current.url?.lastPathComponent, "d")

        app.show(.threads)
        app.clickThreadNode(ids["b"]!, in: thread, clickCount: 2, command: true)
        let child = try XCTUnwrap(app.activeTab)
        XCTAssertEqual(app.tabs.count, count + 1)
        XCTAssertEqual(child.url?.lastPathComponent, "b")
        XCTAssertEqual(child.parentTabID, current.id, "⌘-double-click opens a child of the current tab")

        app.activate(current.id); app.show(.threads)
        app.clickThreadNode(ids["c"]!, in: thread, clickCount: 1, command: false)
        XCTAssertEqual(app.activeSurface, .threads)
        XCTAssertTrue(app.openSelectedThreadNode(in: thread), "Return opens the selected node")
        XCTAssertEqual(current.url?.lastPathComponent, "c")
        XCTAssertEqual(app.activeSurface, .web)
    }
}
