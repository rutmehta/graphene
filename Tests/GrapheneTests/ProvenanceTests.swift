import XCTest
@testable import Graphene

/// G1 provenance rows (graphene-identity.md §3.1): Today tabs opened from another Today tab
/// are drawn as its children.
@MainActor
final class ProvenanceTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Open A, open two links from A, then one link from the second child.
    private func makeBranch() -> (AppState, a: Tab, c1: Tab, c2: Tab, d: Tab) {
        let app = AppState(directory: directory)
        func open(_ path: String, from parent: Tab?) -> Tab {
            app.openTab(url: URL(string: "https://provenance.invalid/\(path)")!, parent: parent, activate: false)
            return app.tabs.first { $0.url?.path == "/\(path)" }!
        }
        let a = open("a", from: nil)
        let c1 = open("c1", from: a), c2 = open("c2", from: a)
        let d = open("d", from: c2)
        return (app, a, c1, c2, d)
    }

    private func depths(_ app: AppState) -> [String] {
        app.todayProvenance().rows.compactMap { row in
            app.tabs.first { $0.id == row.id }?.url.map { "\($0.lastPathComponent):\(row.depth)" }
        }
    }

    func testDepthRowsFromATabTree() {
        let (app, a, _, c2, d) = makeBranch()
        XCTAssertEqual(depths(app), ["a:0", "c1:1", "c2:1", "d:2"], "children follow their parent, oldest first")
        let layout = app.todayProvenance()
        XCTAssertTrue(layout.hasBranches)
        XCTAssertEqual(layout.rows.first { $0.id == a.id }?.descendants, 3)
        XCTAssertEqual(layout.rows.first { $0.id == d.id }?.parentID, c2.id)
        XCTAssertEqual(layout.rows.first { $0.id == d.id }?.rootID, a.id)

        // Depth clamps for indentation only.
        let ids = (0..<6).map { _ in UUID() }
        var parents: [UUID: UUID] = [:]
        for index in 1..<ids.count { parents[ids[index]] = ids[index - 1] }
        let deep = ProvenanceLayout(ids: ids, parents: parents)
        XCTAssertEqual(deep.rows.map(\.depth), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(deep.rows.map(\.indent), [0, 1, 2, 3, 3, 3])

        // Pinned tabs never participate; a flat space has no branches at all.
        app.placeTab(a.id, section: .pinned)
        XCTAssertNil(app.branchParent(of: app.tabs.first { $0.url?.lastPathComponent == "c1" }!.id))
        let flat = ProvenanceLayout(ids: ids, parents: [ids[0]: UUID()])
        XCTAssertFalse(flat.hasBranches)
        XCTAssertTrue(flat.connectors(activeID: ids[0]).isEmpty)
    }

    func testClosingAParentPromotesItsChildrenInPlace() {
        let (app, a, c1, c2, d) = makeBranch()
        app.closeTab(c2.id)
        XCTAssertEqual(d.parentTabID, a.id, "the closed child's child joins its grandparent")
        XCTAssertEqual(depths(app), ["a:0", "c1:1", "d:1"])

        app.closeTab(a.id)
        XCTAssertNil(c1.parentTabID); XCTAssertNil(d.parentTabID)
        XCTAssertFalse(app.todayProvenance().hasBranches)
        let today = app.visibleTabs.filter { $0.section == .today }.compactMap { $0.url?.lastPathComponent }
        XCTAssertEqual(today, ["c1", "d"], "promoted roots take the parent's position, no gap")
    }

    func testDraggingAChildMakesItARootAndDropOnIconAdopts() {
        let (app, a, c1, c2, d) = makeBranch()
        app.moveTab(d.id, onto: a.id, before: true)
        XCTAssertNil(d.parentTabID)
        XCTAssertEqual(depths(app), ["d:0", "a:0", "c1:1", "c2:1"])

        app.adoptTab(d.id, under: c1.id)
        XCTAssertEqual(d.parentTabID, c1.id)
        XCTAssertEqual(depths(app), ["a:0", "c1:1", "d:2", "c2:1"])
        app.adoptTab(a.id, under: d.id)
        XCTAssertNil(a.parentTabID, "a tab cannot become the child of its own descendant")

        app.detachFromParent(c2.id)
        XCTAssertNil(c2.parentTabID)
        XCTAssertEqual(app.branchChildren(of: a.id).map(\.id), [c1.id])
    }

    func testClosingABranchArchivesItWithOneUndo() {
        let (app, a, _, _, _) = makeBranch()
        let archived = app.archivedTabs.count, toasts = app.toasts.items.count
        app.closeBranch(a.id)
        XCTAssertEqual(app.archivedTabs.count, archived + 4)
        XCTAssertEqual(app.toasts.items.count, toasts + 1)
        XCTAssertEqual(app.toasts.items.last?.title, "Archived 4 tabs")
        XCTAssertFalse(app.tabs.contains { $0.url?.host == "provenance.invalid" })

        app.toasts.items.last?.action?()
        XCTAssertEqual(app.archivedTabs.count, archived)
        XCTAssertEqual(depths(app), ["a:0", "c1:1", "c2:1", "d:2"], "undo restores the branch with its links")
    }

    func testCollapsedBranchHidesChildrenAndCounts() {
        let (app, a, _, c2, d) = makeBranch()
        app.setBranch(a.id, collapsed: true)
        let layout = app.todayProvenance()
        let blank = app.tabs[0].id
        XCTAssertEqual(layout.rows.map(\.id), [blank, a.id])
        XCTAssertEqual(layout.rows.last?.collapsed, true)
        XCTAssertEqual(layout.rows.last?.descendants, 3)
        app.setBranch(d.id, collapsed: true)
        XCTAssertFalse(app.collapsedBranchIDs.contains(d.id), "a row without children has no branch")
        app.activate(d.id)
        XCTAssertTrue(app.collapsedBranchIDs.isEmpty, "selecting a hidden tab opens its branch")
        XCTAssertEqual(app.todayProvenance().rows.count, 5)
        XCTAssertEqual(app.branchChildren(of: a.id).map(\.id).count, 2)
        XCTAssertEqual(app.branchChildren(of: c2.id).map(\.id), [d.id])
    }

    func testBranchCommandsAreRegisteredWithoutConflicts() throws {
        let (app, a, _, _, _) = makeBranch()
        app.activate(a.id)
        let collapse = try XCTUnwrap(app.allCommandActions.first { $0.id == "collapse-branch" })
        let expand = try XCTUnwrap(app.allCommandActions.first { $0.id == "expand-branch" })
        XCTAssertEqual(collapse.title, "Collapse Branch")
        XCTAssertEqual(expand.title, "Expand Branch")
        XCTAssertEqual(collapse.key, .leftArrow)
        XCTAssertEqual(expand.key, .rightArrow)
        XCTAssertEqual(collapse.modifiers, [.command, .option, .control])
        XCTAssertEqual(expand.modifiers, [.command, .option, .control])
        XCTAssertEqual([collapse.hint, expand.hint], ["⌃⌥⌘←", "⌃⌥⌘→"])
        // The ⌃⌥⌘ arrow family: no other command uses these two shortcuts.
        for action in [collapse, expand] {
            let shortcut = CommandShortcut(action: action)
            XCTAssertEqual(app.allCommandActions.filter { CommandShortcut(action: $0) == shortcut }.map(\.id), [action.id])
        }
        XCTAssertTrue(collapse.enabled)
        XCTAssertFalse(expand.enabled, "an open branch has nothing to expand")
    }

    func testBranchCommandsActOnTheSelectedTabsBranch() throws {
        let (app, a, c1, c2, d) = makeBranch()
        func run(_ id: String) { app.commandActions.first { $0.id == id }?.run() }
        // Selected parent: its branch collapses and expands.
        app.activate(a.id)
        XCTAssertEqual(app.selectedBranchID, a.id)
        run("collapse-branch")
        XCTAssertEqual(app.collapsedBranchIDs, [a.id])
        XCTAssertNil(app.commandActions.first { $0.id == "collapse-branch" }, "disabled once collapsed")
        run("expand-branch")
        XCTAssertTrue(app.collapsedBranchIDs.isEmpty)
        // Selected leaf child: the branch it hangs from collapses and the parent takes the selection.
        app.activate(c1.id)
        XCTAssertEqual(app.selectedBranchID, a.id)
        run("collapse-branch")
        XCTAssertEqual(app.collapsedBranchIDs, [a.id])
        XCTAssertEqual(app.activeTabID, a.id, "the selection stays visible")
        run("expand-branch")
        XCTAssertTrue(app.collapsedBranchIDs.isEmpty)
        // A child that is itself a parent acts on its own branch.
        app.activate(c2.id)
        app.setSelectedBranch(collapsed: true)
        XCTAssertEqual(app.collapsedBranchIDs, [c2.id])
        XCTAssertEqual(app.activeTabID, c2.id)
        XCTAssertFalse(app.todayProvenance().rows.contains { $0.id == d.id })
        // A tab in no branch: nothing to do.
        app.setSelectedBranch(collapsed: false)
        app.activate(app.tabs[0].id)
        XCTAssertNil(app.selectedBranchID)
        XCTAssertFalse(try XCTUnwrap(app.allCommandActions.first { $0.id == "collapse-branch" }).enabled)
    }

    func testRestoreDropsOrphanParents() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let parent = UUID(), child = UUID(), orphan = UUID(), missing = UUID()
        let session = """
        {"version":2,"activeIndex":0,"tabs":[
          {"pinned":false,"url":"https://p.invalid/","id":"\(parent)"},
          {"pinned":false,"url":"https://c.invalid/","id":"\(child)","parentTabID":"\(parent)"},
          {"pinned":false,"url":"https://o.invalid/","id":"\(orphan)","parentTabID":"\(missing)"}]}
        """
        try Data(session.utf8).write(to: directory.appendingPathComponent("session.json"))
        let app = AppState(directory: directory)
        XCTAssertEqual(app.tabs.first { $0.id == child }?.parentTabID, parent)
        XCTAssertNil(app.tabs.first { $0.id == orphan }?.parentTabID)

        // Round trip: the link is persisted.
        app.persist()
        let saved = try JSONDecoder().decode(AppState.SessionData.self, from: Data(contentsOf: directory.appendingPathComponent("session.json")))
        XCTAssertEqual(saved.tabs.first { $0.id == child }?.parentTabID, parent)

        // Archive restore: a child reopened after its parent closed comes back as a root.
        app.closeTab(child)
        app.closeTab(parent)
        let reopenedChild = app.archivedTabs.firstIndex { $0.id == child }!
        app.restoreArchive(app.archivedTabs[reopenedChild].archiveID!)
        XCTAssertNil(app.tabs.first { $0.url?.host == "c.invalid" }?.parentTabID)
    }

    func testConnectorGeometryForAThreeRowBranch() {
        let a = UUID(), b = UUID(), c = UUID(), other = UUID()
        let layout = ProvenanceLayout(ids: [a, b, c, other], parents: [b: a, c: a])
        let connectors = layout.connectors(activeID: c)
        XCTAssertEqual(connectors.count, 1, "one path per parent")
        let line = connectors[0]
        XCTAssertTrue(line.active, "the branch holding the selection uses threadLineActive")
        XCTAssertEqual(line.x, ShellLayout.threadLineInset)
        // From the bottom of A's 20pt icon slot (row centre 18 + 10) to C's icon centre (2 × 40 + 18).
        XCTAssertEqual(line.vertical, CGRect(x: 17, y: 28, width: 1, height: 70.5))
        // Ticks run from the vertical (x 17) to the child's icon slot edge (x 28), starting past the 1pt vertical.
        XCTAssertEqual(line.ticks, [CGRect(x: 18, y: 57.5, width: 10, height: 1), CGRect(x: 18, y: 97.5, width: 10, height: 1)])
        XCTAssertEqual(ShellLayout.threadTick, 11)
        let childSlot = ShellLayout.threadIndent + ShellLayout.rowInsetLeading
        XCTAssertEqual(line.x + ShellLayout.threadTick, childSlot)
        XCTAssertTrue(line.ticks.allSatisfy { $0.minX == line.vertical.maxX && $0.maxX == childSlot }, "the tick enters the child's icon slot")
        XCTAssertFalse(layout.connectors(activeID: other)[0].active)

        // While the vertical animates, it is drawn to its animated bottom and ticks appear as it reaches them.
        let full = ProvenanceConnector.drawn(vertical: line.vertical, ticks: line.ticks, top: line.vertical.minY, bottom: line.vertical.maxY)
        XCTAssertEqual(full, [line.vertical] + line.ticks)
        let half = ProvenanceConnector.drawn(vertical: line.vertical, ticks: line.ticks, top: 28, bottom: 60)
        XCTAssertEqual(half, [CGRect(x: 17, y: 28, width: 1, height: 32), line.ticks[0]])
        XCTAssertEqual(ProvenanceConnector.drawn(vertical: line.vertical, ticks: line.ticks, top: 28, bottom: 28), [CGRect(x: 17, y: 28, width: 1, height: 0)])

        // A nested parent's line moves in by its indent.
        let nested = ProvenanceLayout(ids: [a, b, c], parents: [b: a, c: b]).connectors(activeID: nil)
        XCTAssertEqual(nested.map(\.x), [17, 37])
        XCTAssertEqual(ShellLayout.threadIndent, 20)
        XCTAssertEqual(ShellLayout.threadMaxDepth, 3)
    }
}
