import XCTest
import AppKit
@testable import Graphene

/// Hands-on sidebar fixes: drag and drop, the Today close glyph, ⌘W on pinned tabs, the
/// scroll-wheel filter, focus rings, the space switch's direction and the one Ask glyph.
@MainActor
final class SidebarInteractionTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Four Today tabs a, b, c, d in the active space.
    private func makeToday() -> (AppState, [String: Tab]) {
        let app = AppState(directory: directory)
        var tabs: [String: Tab] = [:]
        for name in ["a", "b", "c", "d"] {
            app.openTab(url: URL(string: "https://sidebar.invalid/\(name)")!, parent: nil, activate: false)
            tabs[name] = app.tabs.first { $0.url?.lastPathComponent == name }!
        }
        return (app, tabs)
    }

    private func names(_ app: AppState, _ section: TabSection) -> [String] {
        app.visibleTabs.filter { $0.section == section }.compactMap { $0.url?.lastPathComponent }
    }

    // MARK: 1. drag and drop, end to end at the model

    /// Each sidebar gesture ends in `sidebarDrop(payload, on:)` with the payload `onDrag` wrote.
    func testEverySidebarDropTargetMovesTheDraggedTab() {
        let (app, t) = makeToday()
        let payload = { (tab: Tab) in "tab:\(tab.id)" }

        // Today row → favorites grid: a favorite. The drag state that kept the grid open ends.
        app.beginSidebarDrag(t["a"]!.id)
        XCTAssertEqual(app.sidebarDragTabID, t["a"]!.id)
        XCTAssertTrue(app.sidebarDrop(payload(t["a"]!), on: .favorites))
        XCTAssertEqual(t["a"]!.section, .favorites)
        XCTAssertNil(app.sidebarDragTabID)

        // Today row → space label: pinned, with its current page as the pinned page.
        XCTAssertTrue(app.sidebarDrop(payload(t["b"]!), on: .pinned))
        XCTAssertEqual(t["b"]!.section, .pinned)
        XCTAssertEqual(t["b"]!.pinnedURL, t["b"]!.url)

        // Between rows: the lower half of c drops after it, the upper half before it.
        XCTAssertEqual(names(app, .today), ["c", "d"])
        XCTAssertTrue(app.sidebarDrop(payload(t["c"]!), on: .row(t["d"]!.id, after: true)))
        XCTAssertEqual(names(app, .today), ["d", "c"])
        XCTAssertTrue(app.sidebarDrop(payload(t["c"]!), on: .row(t["d"]!.id, after: false)))
        XCTAssertEqual(names(app, .today), ["c", "d"])

        // A pinned row dropped onto a Today row joins Today there (and is no longer pinned).
        XCTAssertTrue(app.sidebarDrop(payload(t["b"]!), on: .row(t["d"]!.id, after: false)))
        XCTAssertEqual(names(app, .today), ["c", "b", "d"])
        XCTAssertNil(t["b"]!.pinnedURL)

        // Onto another Today row's icon slot: a child (G1).
        XCTAssertTrue(app.sidebarDrop(payload(t["d"]!), on: .branch(t["c"]!.id)))
        XCTAssertEqual(t["d"]!.parentTabID, t["c"]!.id)
        XCTAssertFalse(app.sidebarDrop(payload(t["c"]!), on: .branch(t["d"]!.id)), "never under its own descendant")

        // Today hairline: back to Today from favorites.
        XCTAssertTrue(app.sidebarDrop(payload(t["a"]!), on: .today))
        XCTAssertEqual(t["a"]!.section, .today)

        // Dropping a tab on itself or an unknown payload changes nothing.
        XCTAssertFalse(app.sidebarDrop(payload(t["a"]!), on: .row(t["a"]!.id, after: true)))
        XCTAssertFalse(app.sidebarDrop("https://example.com", on: .favorites))
    }

    func testFavoriteTilesReorderAndGroupingMakesAFolder() {
        let (app, t) = makeToday()
        for name in ["a", "b", "c"] { app.sidebarDrop("tab:\(t[name]!.id)", on: .favorites) }
        XCTAssertEqual(names(app, .favorites), ["a", "b", "c"])
        // Tiles split left/right: the right half of a drops after it.
        XCTAssertTrue(app.sidebarDrop("tab:\(t["c"]!.id)", on: .row(t["a"]!.id, after: true)))
        XCTAssertEqual(names(app, .favorites), ["a", "c", "b"])
        XCTAssertTrue(app.sidebarDrop("tab:\(t["b"]!.id)", on: .row(t["a"]!.id, after: false)))
        XCTAssertEqual(names(app, .favorites), ["b", "a", "c"])
        XCTAssertEqual(SidebarDropPlacement.after(location: CGPoint(x: 40, y: 1), size: CGSize(width: 60, height: 48), horizontal: true), true)
        XCTAssertEqual(SidebarDropPlacement.after(location: CGPoint(x: 40, y: 1), size: CGSize(width: 200, height: 36), horizontal: false), false)
        XCTAssertEqual(SidebarDropPlacement.after(location: CGPoint(x: 1, y: 30), size: CGSize(width: 200, height: 36), horizontal: false), true)

        // Held over a Today row: both tabs share a new folder.
        XCTAssertTrue(app.sidebarDrop("tab:\(t["c"]!.id)", on: .group(t["d"]!.id)))
        let folder = t["d"]!.folderID
        XCTAssertNotNil(folder)
        XCTAssertEqual(t["c"]!.folderID, folder)
        XCTAssertEqual(t["c"]!.section, .today)
        // A folder row takes a dropped tab.
        XCTAssertTrue(app.sidebarDrop("tab:\(t["a"]!.id)", on: .folder(folder!)))
        XCTAssertEqual(t["a"]!.folderID, folder)
    }

    func testSpaceDotsTakeTabsAndReorderSpaces() {
        let (app, t) = makeToday()
        let first = app.activeSpaceID
        let second = app.createSpace(name: "Second")
        app.selectSpace(first)
        XCTAssertTrue(app.sidebarDrop("tab:\(t["a"]!.id)", on: .space(second)))
        XCTAssertEqual(t["a"]!.spaceID, second)
        XCTAssertTrue(app.sidebarDrop("space:\(second)", on: .space(first)))
        XCTAssertEqual(app.spaces.map(\.id).prefix(2), [second, first])
    }

    /// The drop targets are hit-testable and no overlay or monitor view takes their events.
    func testSidebarDropTargetsAreHitTestableAndOverlaysPassEvents() throws {
        let sidebar = try source("Sources/Graphene/UI/Sidebar.swift")
        XCTAssertFalse(sidebar.contains("isTargeted: $draggingTab"), "no whole-sidebar drop target competing with the rows")
        XCTAssertTrue(sidebar.contains(".contentShape(Rectangle())\n            .modifier(ShellDropTarget { payload, _ in app.sidebarDrop(payload, on: .favorites) })"),
                      "the favorites grid is hit-testable everywhere, gaps included")
        XCTAssertFalse(sidebar.contains("Button { app.sidebarClick(tab"), "rows and tiles are tap targets, so a drag can start on them")
        XCTAssertEqual(sidebar.components(separatedBy: ".onDrop(").count - 1, 1, "one drop mechanism, in ShellDropTarget")
        XCTAssertTrue(sidebar.contains("ThreadLines") && sidebar.contains(".allowsHitTesting(false).accessibilityHidden(true)"))
        XCTAssertFalse(try source("Sources/Graphene/UI/DragAutoScrollEdge.swift").contains("registerForDraggedTypes"),
                       "the auto-scroll bands are not drag destinations")
        XCTAssertNil(DragAutoScrollEdge.EdgeView().hitTest(.zero))
        XCTAssertNil(SidebarSwipe.SwipeView().hitTest(.zero))
    }

    // MARK: 2. the Today close glyph

    func testTodayRowsShowCloseOnHoverAndSelection() {
        XCTAssertFalse(SidebarRowModel(section: .today, hovered: false, selected: false).showsClose)
        XCTAssertTrue(SidebarRowModel(section: .today, hovered: true, selected: false).showsClose)
        XCTAssertTrue(SidebarRowModel(section: .today, hovered: false, selected: true).showsClose)
        XCTAssertTrue(SidebarRowModel(section: .today, hovered: false, selected: false).closable, "the AX close action is always there")
        for section in [TabSection.pinned, .favorites] {
            XCTAssertFalse(SidebarRowModel(section: section, hovered: true, selected: true).showsClose)
        }
        XCTAssertFalse(SidebarRowModel(section: .today, hovered: true, selected: true, tile: true).showsClose)
    }

    // MARK: 3. ⌘W and the close glyph on pinned tabs

    func testClosingAPinnedTabResetsItWithoutADialog() throws {
        let (app, t) = makeToday()
        let pinned = t["a"]!, base = pinned.url!
        let toasts = app.toasts.items.count
        app.placeTab(pinned.id, section: .pinned)
        pinned.load(URL(string: "https://sidebar.invalid/elsewhere")!)
        app.requestCloseTab(pinned.id)
        XCTAssertTrue(app.tabs.contains { $0.id == pinned.id }, "a pinned tab stays")
        XCTAssertEqual(pinned.section, .pinned)
        XCTAssertEqual(pinned.url, base, "and returns to its pinned page")
        XCTAssertEqual(app.activeTabID, pinned.id)
        XCTAssertEqual(app.toasts.items.count, toasts, "no toast, no dialog")

        // Favorites behave the same.
        app.placeTab(t["b"]!.id, section: .favorites)
        app.requestCloseTab(t["b"]!.id)
        XCTAssertTrue(app.tabs.contains { $0.id == t["b"]!.id })

        // A Today tab closes with the Undo toast; Undo brings it back.
        let today = t["c"]!
        app.requestCloseTab(today.id)
        XCTAssertFalse(app.tabs.contains { $0.id == today.id })
        let toast = try XCTUnwrap(app.toasts.items.last)
        XCTAssertEqual(toast.actionTitle, "Undo")
        toast.action?()
        XCTAssertTrue(app.tabs.contains { $0.url?.lastPathComponent == "c" })

        // The context menu's Unpin and Close act at once; Close archives with Undo.
        app.pin(pinned)
        XCTAssertEqual(pinned.section, .today)
        app.placeTab(pinned.id, section: .pinned)
        app.closeTab(pinned.id)
        XCTAssertFalse(app.tabs.contains { $0.id == pinned.id })
        XCTAssertEqual(app.toasts.items.last?.actionTitle, "Undo")

        let state = try source("Sources/Graphene/App/AppState.swift")
        XCTAssertFalse(state.contains("Unpin or close?"))
        XCTAssertFalse(state.contains("runModal"))
        let menu = try source("Sources/Graphene/UI/TabContextMenu.swift")
        XCTAssertTrue(menu.contains("Button(\"Close\") { app.closeTab(tab.id) }"))
    }

    func testClosingAPinnedSplitPaneKeepsTheTab() {
        let (app, t) = makeToday()
        app.placeTab(t["a"]!.id, section: .pinned)
        app.activate(t["a"]!.id)
        app.openSplit(t["b"]!.id)
        XCTAssertEqual(app.splits.first?.tabIDs.count, 2)
        app.closePane(t["a"]!.id)
        XCTAssertTrue(app.splits.isEmpty)
        XCTAssertTrue(app.tabs.contains { $0.id == t["a"]!.id })
        XCTAssertEqual(app.activeTabID, t["b"]!.id)
    }

    // MARK: 4. scrolling the sidebar

    func testVerticalScrollingPassesThroughTheSwipeMonitor() {
        var filter = SidebarSwipeFilter()
        // A vertical trackpad scroll whose first frames lean sideways: every frame passes untouched.
        let frames: [(NSEvent.Phase, CGFloat, CGFloat)] = [
            (.mayBegin, 0, 0), (.began, 1.5, 0), (.changed, 1, 0.5), (.changed, 0.5, 8), (.changed, 2, 1), (.changed, 0, 14), (.ended, 0, 0)
        ]
        for (phase, dx, dy) in frames {
            XCTAssertEqual(filter.decide(phase: phase, momentumPhase: [], dx: dx, dy: dy, precise: true), .pass)
        }
        // Momentum and wheel mice always pass.
        XCTAssertEqual(filter.decide(phase: [], momentumPhase: .changed, dx: 30, dy: 0, precise: true), .pass)
        XCTAssertEqual(filter.decide(phase: [], momentumPhase: [], dx: 30, dy: 0, precise: false), .pass)
    }

    func testHorizontalSwipeSwitchesSpaceOnce() {
        var filter = SidebarSwipeFilter()
        XCTAssertEqual(filter.decide(phase: .began, momentumPhase: [], dx: -4, dy: 0, precise: true), .pass, "began always reaches the scroll view")
        var decisions: [SidebarSwipeFilter.Decision] = []
        for _ in 0..<10 { decisions.append(filter.decide(phase: .changed, momentumPhase: [], dx: -10, dy: 1, precise: true)) }
        XCTAssertEqual(decisions.filter { $0 == .switchSpace(1) }.count, 1, "a leftward swipe goes to the next space, once")
        XCTAssertFalse(decisions.contains(.pass))
        XCTAssertEqual(filter.decide(phase: .ended, momentumPhase: [], dx: 0, dy: 0, precise: true), .pass)
        // The next gesture starts fresh: rightward goes back.
        _ = filter.decide(phase: .began, momentumPhase: [], dx: 0, dy: 0, precise: true)
        let back = (0..<10).map { _ in filter.decide(phase: .changed, momentumPhase: [], dx: 10, dy: 0, precise: true) }
        XCTAssertTrue(back.contains(.switchSpace(-1)))
    }

    // MARK: 5. focus rings

    func testShellButtonsShowFocusRingsOnlyFromTheKeyboard() throws {
        XCTAssertTrue(FocusSource.isKeyboard(.keyDown))
        XCTAssertFalse(FocusSource.isKeyboard(.leftMouseDown))
        XCTAssertFalse(FocusSource.isKeyboard(nil))
        let sidebar = try source("Sources/Graphene/UI/Sidebar.swift")
        let style = try XCTUnwrap(sidebar.range(of: "struct ShellButtonStyle")).upperBound
        XCTAssertTrue(sidebar[style...].prefix(1400).contains(".focusEffectDisabled()"))
        let wrappers: [(file: String, type: String)] = [
            ("Sources/Graphene/UI/RootView.swift", "struct IconButton"),
            ("Sources/Graphene/UI/PageToolbar.swift", "struct ToolbarGlyphButton"),
            ("Sources/Graphene/UI/Sidebar.swift", "struct SidebarGlyphButton"),
            ("Sources/Graphene/UI/LedgerView.swift", "struct LibraryBarButton"),
        ]
        for wrapper in wrappers {
            let text = try source(wrapper.file)
            let start = try XCTUnwrap(text.range(of: wrapper.type), wrapper.type).upperBound
            XCTAssertTrue(text[start...].prefix(1600).contains(".keyboardFocusRing()"), "\(wrapper.type) rings only for keyboard focus")
        }
        let ledger = try source("Sources/Graphene/UI/LedgerView.swift")
        XCTAssertFalse(ledger.contains(".focusable()\n                    .onKeyPress"), "the thread list takes focus without a ring")
    }

    // MARK: 6. space switch motion

    func testSpaceSwitchSlidesInTheDirectionOfTravel() {
        XCTAssertEqual(SpaceTravel.direction(from: 0, to: 2, delta: nil), 1)
        XCTAssertEqual(SpaceTravel.direction(from: 2, to: 0, delta: nil), -1)
        XCTAssertNil(SpaceTravel.direction(from: 1, to: 1, delta: nil))
        XCTAssertEqual(SpaceTravel.direction(from: 2, to: 0, delta: 1), 1, "next from the last space wraps forward")
        XCTAssertEqual(SpaceTravel.direction(from: 0, to: 2, delta: -1), -1, "previous from the first wraps backward")

        let next = SidebarMotion.spaceSlideOffsets(direction: 1)
        XCTAssertEqual(next.insertion, ShellLayout.spaceSlide, "the next space enters from the right")
        XCTAssertEqual(next.removal, -ShellLayout.spaceSlide, "and the old one leaves to the left")
        let previous = SidebarMotion.spaceSlideOffsets(direction: -1)
        XCTAssertEqual(previous.insertion, -ShellLayout.spaceSlide)
        XCTAssertEqual(previous.removal, ShellLayout.spaceSlide)
        XCTAssertEqual(Motion.gradient.curve, .easeOut(duration: 0.24))
        XCTAssertEqual(Motion.spaceSwitch.curve, .easeOut(duration: 0.18))

        let app = AppState(directory: directory)
        let first = app.activeSpaceID
        _ = app.createSpace(name: "Two")
        let third = app.createSpace(name: "Three")
        XCTAssertEqual(app.spaceTravel, 1)
        app.selectSpace(first)
        XCTAssertEqual(app.spaceTravel, -1)
        app.selectRelativeSpace(-1)
        XCTAssertEqual(app.activeSpaceID, third)
        XCTAssertEqual(app.spaceTravel, -1, "wrapping backward still slides backward")
        app.selectRelativeSpace(1)
        XCTAssertEqual(app.activeSpaceID, first)
        XCTAssertEqual(app.spaceTravel, 1)
    }

    func testChromeCrossFadesBetweenSpaceColours() throws {
        let chrome = try source("Sources/Graphene/UI/Chrome.swift")
        XCTAssertTrue(chrome.contains(".animation(Motion.gradient.reduced(reduceMotion), value: ChromeColors(pal))"))
        let sidebar = try source("Sources/Graphene/UI/Sidebar.swift")
        XCTAssertTrue(sidebar.contains("SidebarMotion.spaceTransition(reduceMotion: reduceMotion, direction: app.spaceTravel)"))
    }

    // MARK: 7. one Ask glyph

    func testAskUsesOneGlyphEverywhere() throws {
        XCTAssertEqual(ShellGlyph.ask, "sparkle")
        let ui = Self.root.appendingPathComponent("Sources/Graphene/UI")
        for file in try FileManager.default.contentsOfDirectory(atPath: ui.path) where file.hasSuffix(".swift") {
            let text = try String(contentsOf: ui.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("\"text.bubble\"") || text.contains("\"bubble.left"), "\(file) uses another chat glyph")
        }
        for file in ["PageToolbar.swift", "LedgerView.swift", "VaultView.swift", "TopTabBar.swift"] {
            XCTAssertTrue(try source("Sources/Graphene/UI/\(file)").contains("ShellGlyph.ask"), file)
        }
    }
}
