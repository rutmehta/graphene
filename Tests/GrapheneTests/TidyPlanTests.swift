import XCTest
@testable import Graphene

/// Tidy Today (landing-and-tidy.md §4): the pure planner, and apply with Undo.
@MainActor
final class TidyPlanTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("graphene-tidy-\(UUID())")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func input(_ title: String, host: String? = "example.com", parent: UUID? = nil, thread: UUID? = nil) -> TidyPlan.Input {
        TidyPlan.Input(id: UUID(), title: title, host: host, parentID: parent, threadID: thread)
    }

    // MARK: planner

    func testBranchesAreNeverSplit() {
        let threadA = UUID(), threadB = UUID()
        let root = input("Graphene - Wikipedia", host: "en.wikipedia.org", thread: threadA)
        // A child whose own thread differs still stays with its branch.
        let child = input("Carbon allotropes", host: "en.wikipedia.org", parent: root.id, thread: threadB)
        let grandchild = input("Diamond", host: "diamond.example", parent: child.id, thread: threadB)
        let other = input("Solo page", host: "solo.example", thread: threadB)
        let plan = TidyPlan.make([root, other, child, grandchild])
        XCTAssertEqual(plan.groups.count, 1)
        XCTAssertEqual(plan.groups[0].tabIDs, [root.id, child.id, grandchild.id], "parent before children")
        XCTAssertEqual(plan.groups[0].kind, .branch)
        XCTAssertEqual(plan.loose, [other.id])
    }

    func testSinglesGroupByThreadThenBranchesAbsorbTheirThread() {
        let thread = UUID(), branchThread = UUID()
        let a = input("Swift concurrency guide", host: "swift.org", thread: thread)
        let b = input("Actors in depth", host: "developer.apple.com", thread: thread)
        let root = input("Rust ownership explained today", host: "rust-lang.org", thread: branchThread)
        let child = input("Borrowing", host: "rust-lang.org", parent: root.id, thread: branchThread)
        let sibling = input("Lifetimes", host: "doc.rust-lang.org", thread: branchThread)
        let plan = TidyPlan.make([a, root, b, child, sibling])
        XCTAssertEqual(plan.groups.map(\.tabIDs), [[a.id, b.id], [root.id, child.id, sibling.id]])
        XCTAssertEqual(plan.groups.map(\.kind), [.thread, .branch])
        XCTAssertEqual(plan.groups.map(\.name), ["Swift concurrency guide", "Rust ownership explained"])
        XCTAssertTrue(plan.loose.isEmpty)
        XCTAssertEqual(plan.tidiedCount, 5)
    }

    func testOnePageThreadsGroupByHostAndSinglesStayLoose() {
        let gh1 = input("apple/swift", host: "github.com", thread: UUID())
        let gh2 = input("apple/swift-nio", host: "www.github.com", thread: UUID())
        let lone = input("Weather", host: "weather.example", thread: UUID())
        let blank = input("New Tab", host: nil)
        let plan = TidyPlan.make([blank, gh1, lone, gh2])
        XCTAssertEqual(plan.groups.count, 1)
        XCTAssertEqual(plan.groups[0].kind, .host)
        XCTAssertEqual(plan.groups[0].tabIDs, [gh1.id, gh2.id])
        XCTAssertEqual(plan.groups[0].name, "Github")
        XCTAssertEqual(plan.loose, [blank.id, lone.id], "groups of one stay loose, in list order")
        XCTAssertTrue(TidyPlan.make([lone]).groups.isEmpty)
        XCTAssertTrue(TidyPlan.make([]).groups.isEmpty)
    }

    func testNames() {
        XCTAssertEqual(TidyPlan.shortTitle("Graphene - Wikipedia"), "Graphene")
        XCTAssertEqual(TidyPlan.shortTitle("The quick brown fox jumps"), "The quick brown")
        XCTAssertEqual(TidyPlan.shortTitle("Pricing | Linear"), "Pricing")
        XCTAssertEqual(TidyPlan.shortTitle("Hello, world: a tour"), "Hello, world: a", "punctuation inside is kept")
        XCTAssertEqual(TidyPlan.shortTitle("Notes:"), "Notes")
        XCTAssertNil(TidyPlan.shortTitle("   "))
        XCTAssertEqual(TidyPlan.siteName("en.wikipedia.org"), "Wikipedia")
        XCTAssertEqual(TidyPlan.siteName("www.bbc.co.uk"), "Bbc")
        XCTAssertEqual(TidyPlan.siteName("news.ycombinator.com"), "Ycombinator")
        XCTAssertEqual(TidyPlan.siteName("localhost"), "Localhost")
        XCTAssertNil(TidyPlan.siteName(nil))
        // A branch whose root has no title falls back to its site.
        let root = input("", host: "docs.swift.org")
        let child = input("Closures", host: "docs.swift.org", parent: root.id)
        XCTAssertEqual(TidyPlan.make([root, child]).groups.first?.name, "Swift")
        XCTAssertEqual(AITidy.title("\"Rust  learning notes extra\""), "Rust learning notes", "AI names are trimmed to 3 words")
    }

    /// Acceptance 4: 12 tabs from three threads plus two loose tabs → three folders, two loose.
    func testTwelveTabsFromThreeThreadsPlusTwoLoose() {
        var tabs: [TidyPlan.Input] = []
        for name in ["Alpha topic root", "Beta topic root", "Gamma topic root"] {
            let thread = UUID()
            let root = input(name, host: "\(name.prefix(5).lowercased()).example", thread: thread)
            let c1 = input("\(name) child one", parent: root.id, thread: thread)
            let c2 = input("\(name) child two", parent: root.id, thread: thread)
            let c3 = input("\(name) grandchild", parent: c1.id, thread: thread)
            tabs += [root, c1, c2, c3]
        }
        let loose = [input("Mail", host: "mail.example", thread: UUID()), input("Calendar", host: "cal.example", thread: UUID())]
        let plan = TidyPlan.make(tabs + loose)
        XCTAssertEqual(plan.groups.map(\.name), ["Alpha topic root", "Beta topic root", "Gamma topic root"])
        XCTAssertEqual(plan.groups.map(\.tabIDs.count), [4, 4, 4])
        XCTAssertEqual(plan.loose, loose.map(\.id))
    }

    // MARK: apply and Undo

    private func open(_ app: AppState, _ path: String, host: String = "tidy.invalid", from parent: Tab? = nil, thread: UUID? = nil) -> Tab {
        let url = URL(string: "https://\(host)/\(path)")!
        app.openTab(url: url, parent: parent, activate: false)
        let tab = app.tabs.first { $0.url == url }!
        tab.title = path.capitalized + " page"
        tab.currentThreadID = thread ?? parent?.currentThreadID
        return tab
    }

    func testApplyMakesTodayFoldersKeepsParentsAndUndoRestoresExactly() throws {
        let app = AppState(directory: directory)
        let threadA = UUID(), threadB = UUID()
        let a = open(app, "alpha", thread: threadA)
        let loose1 = open(app, "loose", host: "one.invalid", thread: UUID())
        let a1 = open(app, "alpha-child", from: a)
        let b = open(app, "beta", host: "beta.invalid", thread: threadB)
        let a2 = open(app, "alpha-grandchild", from: a1)
        let b1 = open(app, "beta-child", host: "beta.invalid", from: b)
        let loose2 = open(app, "other", host: "two.invalid", thread: UUID())
        let order = app.tabs.map(\.id)
        let parents = Dictionary(app.tabs.map { ($0.id, $0.parentTabID) }, uniquingKeysWith: { first, _ in first })
        let foldersBefore = app.folders

        let action = try XCTUnwrap(app.allCommandActions.first { $0.id == "tidy-today" })
        XCTAssertEqual(action.title, "Tidy Today")
        XCTAssertEqual(action.hint, "⌃⌥⌘T")
        XCTAssertEqual(action.modifiers, [.command, .option, .control])
        XCTAssertEqual(app.allCommandActions.first { $0.id == "archive-stale" }?.title, "Archive Stale Tabs")
        XCTAssertNil(app.allCommandActions.first { $0.id != "tidy-today" && $0.key == "t" && $0.modifiers == [.command, .option, .control] },
                     "⌃⌥⌘T is not taken by another command")

        let toastsBefore = app.toasts.items.count
        let record = try XCTUnwrap(app.tidyToday())
        let made = app.folders.filter { !foldersBefore.contains($0) }
        XCTAssertEqual(made.map(\.name), ["Alpha page", "Beta page"])
        XCTAssertTrue(made.allSatisfy { $0.section == .today && $0.spaceID == app.activeSpaceID })
        XCTAssertEqual(Set([a, a1, a2].map(\.folderID)), [made[0].id])
        XCTAssertEqual(Set([b, b1].map(\.folderID)), [made[1].id])
        XCTAssertNil(loose1.folderID); XCTAssertNil(loose2.folderID)
        XCTAssertEqual(a1.parentTabID, a.id, "parents are kept inside the folder")
        XCTAssertEqual(a2.parentTabID, a1.id)
        for tab in [a, a1, a2, b, b1] {
            XCTAssertTrue(app.tabs.contains { $0 === tab }, "nothing is closed")
            XCTAssertEqual(tab.section, TabSection.today)
        }
        let layout = app.folderProvenance(made[0].id)
        XCTAssertTrue(layout.hasBranches)
        XCTAssertEqual(layout.rows.map(\.depth), [0, 1, 2], "the folder keeps its connectors")
        XCTAssertFalse(app.todayProvenance().rows.contains { [a.id, b.id].contains($0.id) }, "folder tabs leave the loose list")
        XCTAssertEqual(app.toasts.items.count, toastsBefore + 1)
        let toast = try XCTUnwrap(app.toasts.items.last)
        XCTAssertEqual(toast.title, "Tidied 5 tabs into 2 groups")
        XCTAssertEqual(toast.actionTitle, "Undo")

        let reference = app.tabs.map(\.id)
        XCTAssertEqual(reference, order, "Tidy does not reorder tabs")

        toast.action?()
        XCTAssertEqual(app.folders, foldersBefore)
        XCTAssertEqual(app.tabs.map(\.id), order, "Undo restores the exact order")
        for tab in app.tabs { XCTAssertEqual(tab.parentTabID, parents[tab.id] ?? nil, tab.title); XCTAssertNil(tab.folderID) }
        XCTAssertEqual(app.todayProvenance().rows.map(\.depth), ProvenanceLayout(ids: order, parents: parents.compactMapValues { $0 }).rows.map(\.depth))
        XCTAssertEqual(record.folderIDs, made.map(\.id))

        // Undo after reordering still puts the original order back.
        _ = app.tidyToday()
        app.moveTab(loose2.id, onto: loose1.id, before: true)
        let second = try XCTUnwrap(app.toasts.items.last)
        second.action?()
        XCTAssertEqual(app.tabs.map(\.id), order)
        XCTAssertEqual(app.folders, foldersBefore)
    }

    func testClosingAFolderParentKeepsTheBranchInTheFolder() throws {
        let app = AppState(directory: directory)
        let root = open(app, "root", thread: UUID())
        let middle = open(app, "middle", from: root)
        let leaf = open(app, "leaf", from: middle)
        _ = try XCTUnwrap(app.tidyToday())
        app.closeTab(middle.id)
        XCTAssertEqual(leaf.parentTabID, root.id, "the leaf joins its grandparent inside the folder")
        XCTAssertEqual(leaf.folderID, root.folderID)
    }

    func testNothingToTidy() {
        let app = AppState(directory: directory)
        _ = open(app, "one", host: "one.invalid", thread: UUID())
        let folders = app.folders
        XCTAssertNil(app.tidyToday())
        XCTAssertEqual(app.folders, folders)
        XCTAssertEqual(app.toasts.items.last?.title, "Nothing to tidy in Today.")
    }

    func testSidebarOffersTidyOnTheTodayHairline() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sidebar = try String(contentsOf: root.appendingPathComponent("Sources/Graphene/UI/Sidebar.swift"), encoding: .utf8)
        let divider = try XCTUnwrap(sidebar.range(of: "private struct TodayDivider"))
        let body = sidebar[divider.lowerBound...]
        XCTAssertNotNil(body.range(of: "identifier: \"sidebar.tidy\""), "the Tidy glyph sits beside Clear on hover")
        XCTAssertNotNil(body.range(of: "Button(\"Tidy Today\") { app.tidyToday() }"), "context menu")
        XCTAssertNotNil(body.range(of: "Button(\"Archive Stale Tabs\") { app.archiveStaleTabs() }"))
    }
}
