import XCTest
import AppKit
@testable import Graphene

/// Finding 1: getting between the web and the library surfaces. Finding 2: Ask requests and
/// skill chips send instead of leaving a draft.
@MainActor
final class LibraryNavigationAskTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent("Sources/Graphene/\(path)"), encoding: .utf8)
    }
    private func makeApp() -> (AppState, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (AppState(directory: root), root)
    }

    // MARK: library bar

    func testTheSwitcherFollowsTheLandingTiles() {
        let tiles = ResumeSummary().tiles
        XCTAssertEqual(LibrarySwitcher.items.map(\.surface), tiles.map(\.surface), "Threads, Vault, Board, Mail: the landing page's order")
        XCTAssertEqual(LibrarySwitcher.items.map(\.glyph), tiles.map(\.glyph))
        XCTAssertEqual(LibrarySwitcher.items.map(\.title), tiles.map(\.name))
        XCTAssertEqual(LibrarySwitcher.backTitle, "Back to web")
        XCTAssertEqual(LibrarySwitcher.backGlyph, "chevron.left")
    }

    func testTheSwitcherHelpQuotesEachShortcut() {
        let (app, root) = makeApp()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(LibrarySwitcher.help(LibrarySwitcher.backTitle, command: "web", app: app), "Back to web (⌥⌘1)")
        XCTAssertEqual(LibrarySwitcher.items.map { LibrarySwitcher.help($0.title, command: $0.command, app: app) },
                       ["Threads (⌥⌘2)", "Vault (⌥⌘4)", "Board (⌥⌘5)", "Mail (⌥⌘3)"])
        XCTAssertEqual(LibrarySwitcher.help("Threads", hint: ""), "Threads")
    }

    func testEveryLibraryBarCarriesTheBackButtonAndTheSwitcher() throws {
        let bar = try source("UI/LedgerView.swift")
        XCTAssertTrue(bar.contains("LibraryBarButton(LibrarySwitcher.backTitle, system: LibrarySwitcher.backGlyph"), "the chevron back to the web")
        XCTAssertTrue(bar.contains("{ app.show(.web) }"))
        XCTAssertTrue(bar.contains("LibrarySwitcherView(current: surface, showsTitles: true)"), "the switcher after the title")
        XCTAssertTrue(bar.contains("selected: item.surface == current, showsTitle: showsTitles"))
        // Back chevron, then the title, then the switcher.
        let back = try XCTUnwrap(bar.range(of: "LibrarySwitcher.backTitle, system:")), title = try XCTUnwrap(bar.range(of: "Text(title).font(ShellType.title)"))
        let switcher = try XCTUnwrap(bar.range(of: "LibrarySwitcherView(current: surface, showsTitles: true)"))
        XCTAssertLessThan(back.lowerBound, title.lowerBound)
        XCTAssertLessThan(title.lowerBound, switcher.lowerBound)
        for (path, surface) in [("LedgerView", "threads"), ("VaultView", "vault"), ("EaselView", "board"), ("MailView", "mail")] {
            XCTAssertTrue(try source("UI/\(path).swift").contains("surface: .\(surface))"), "\(path) names its surface so its bar shows the switcher")
        }
        XCTAssertFalse(try source("UI/ArchiveView.swift").contains("surface: ."), "the archive keeps its plain bar")
    }

    func testEscapeOnALibrarySurfaceReturnsToTheWeb() {
        func escape(_ surface: Surface, key: UInt16 = 53, modifiers: NSEvent.ModifierFlags = [], text: Bool = false, bar: Bool = false, sheet: Bool = false, overlay: Bool = false) -> Bool {
            LibraryEscape.returnsToWeb(keyCode: key, modifiers: modifiers, surface: surface, editingText: text, commandBar: bar, sheet: sheet, overlay: overlay)
        }
        for surface in [Surface.threads, .vault, .board, .mail] { XCTAssertTrue(escape(surface), "\(surface)") }
        XCTAssertFalse(escape(.web), "the web surface keeps Escape for the page")
        XCTAssertFalse(escape(.threads, text: true), "a text field keeps Escape")
        XCTAssertFalse(escape(.threads, bar: true), "the command bar keeps Escape")
        XCTAssertFalse(escape(.threads, sheet: true))
        XCTAssertFalse(escape(.threads, overlay: true))
        XCTAssertFalse(escape(.threads, modifiers: .command))
        XCTAssertFalse(escape(.threads, key: 36), "Return is not Escape")
        XCTAssertTrue(LibraryEscape.editingText(NSTextView()))
        XCTAssertTrue(LibraryEscape.editingText(NSTextField()))
        XCTAssertFalse(LibraryEscape.editingText(NSView()))
        XCTAssertFalse(LibraryEscape.editingText(nil))
    }

    func testThePageToolbarOpensTheLibraryBeforeTheChatGlyph() throws {
        let toolbar = try source("UI/PageToolbar.swift")
        let library = try XCTUnwrap(toolbar.range(of: "ToolbarLibraryButton()"))
        let chat = try XCTUnwrap(toolbar.range(of: "identifier: \"toolbar.chat\""))
        XCTAssertLessThan(library.lowerBound, chat.lowerBound, "Library sits before the chat sparkle")
        XCTAssertEqual(ToolbarLibraryButton.glyph, "books.vertical")
        let popover = try source("UI/LibraryButton.swift")
        XCTAssertTrue(popover.contains("LibraryMenu { presented = false }"), "the toolbar opens the same library list")
        XCTAssertTrue(popover.contains("LibraryMenu { app.libraryPresented = false }"), "the footer glyph stays")
        XCTAssertTrue(popover.contains(".contentShape(Rectangle())"), "entries take clicks across their width")
    }

    func testBackToTheWebReselectsTheTabYouLeft() {
        let (app, root) = makeApp()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = app.newTab(), second = app.newTab()
        app.activate(first.id); app.activate(second.id)
        XCTAssertTrue(app.sidebarRowState(second, pal: app.pal).selected)
        app.show(.threads)
        XCTAssertEqual(app.activeSurface, .threads)
        XCTAssertFalse(app.sidebarRowState(second, pal: app.pal).selected, "on a library surface no Today row reads as current")
        XCTAssertFalse(app.sidebarRowState(second, pal: app.pal).highlighted)
        app.show(.vault); app.show(.web)
        XCTAssertEqual(app.activeSurface, .web)
        XCTAssertEqual(app.activeTabID, second.id, "the tab you left is selected again")
        XCTAssertTrue(app.sidebarRowState(second, pal: app.pal).selected)
        // A tab that went away while the library was showing: the space's last active tab instead.
        app.show(.mail)
        app.tabs.removeAll { $0.id == second.id }
        app.show(.web)
        XCTAssertEqual(app.activeTabID, first.id)
    }

    // MARK: Ask sends

    func testASkillChipSendsItsInstruction() async {
        let explain = ChatSkill.defaults[1]
        XCTAssertEqual(explain.trigger, "/explain")
        XCTAssertEqual(ChatSkill.invocation(explain, draft: ""), "/explain", "an empty composer runs the skill on its own")
        XCTAssertEqual(ChatSkill.invocation(explain, draft: "  "), "/explain")
        XCTAssertEqual(ChatSkill.invocation(explain, draft: "the second paragraph"), "/explain the second paragraph", "a draft follows the trigger")

        let (app, root) = makeApp()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(root: root), controller = ChatController(), provider = RecordingProvider()
        controller.send(ChatSkill.invocation(explain, draft: ""), sources: [], app: app, store: store, providerOverride: provider)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(provider.requests.count, 1)
        let request = provider.requests.first?.last?.content ?? ""
        XCTAssertTrue(request.contains(PageContext.questionLabel + explain.instructions), "the expanded instruction is what the model is asked")
        XCTAssertEqual(controller.chat?.messages.filter { $0.role == .user }.map(\.content), ["/explain"], "a sent turn, not a draft")
    }

    func testTheCommandBarsAskIsSentOnceGroundedOnThePage() async throws {
        let (app, root) = makeApp()
        defer { try? FileManager.default.removeItem(at: root) }
        let page = app.newTab(), other = app.newTab()
        app.activate(page.id)
        app.commandBarPresented = true
        app.sendToAsk("What is graphene?")
        XCTAssertTrue(app.knowledgeSearchPresented, "the panel opens")
        XCTAssertFalse(app.commandBarPresented)
        let pending = try XCTUnwrap(app.askRequest)
        XCTAssertTrue(pending.sends)
        XCTAssertEqual(pending.tabIDs, [page.id], "grounded on the current page")

        // Before the panel is ready (not mounted, or still loading its chat) the request waits on the app.
        let controller = ChatController(), store = ChatStore(root: root), provider = RecordingProvider()
        XCTAssertNil(controller.claim(from: app, ready: false))
        XCTAssertEqual(app.askRequest?.id, pending.id)
        // Once ready it is taken exactly once, however often the view asks.
        let taken = try XCTUnwrap(controller.claim(from: app, ready: true))
        XCTAssertEqual(taken.id, pending.id)
        XCTAssertNil(app.askRequest)
        XCTAssertNil(controller.claim(from: app, ready: true))
        app.askRequest = pending
        XCTAssertNil(controller.claim(from: app, ready: true), "a request already taken is never sent twice")
        controller.send(taken.query, sources: [], app: app, store: store, providerOverride: provider)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(controller.chat?.messages.filter { $0.role == .user }.map(\.content), ["What is graphene?"])

        // @-mentioned tabs replace the current page as the grounding.
        app.commandContextIDs = [other.id]
        app.sendToAsk("Compare them")
        XCTAssertEqual(app.askRequest?.tabIDs, [other.id])
        // Ask on Page (no question) only opens the panel.
        app.sendToAsk("")
        XCTAssertEqual(app.askRequest?.sends, false)
    }

    func testTheChatPanelSendsWhatItReceives() throws {
        let chat = try source("UI/ChatView.swift")
        XCTAssertTrue(chat.contains(".task(id: app.askRequest?.id) { await receive() }"))
        XCTAssertTrue(chat.contains("ready = true; await receive()"), "a request that arrived before the panel mounted is taken once it is ready")
        XCTAssertTrue(chat.contains("if request.sends { run(request.query) }"))
        XCTAssertTrue(chat.contains("Button { run(ChatSkill.invocation(skill, draft: query)) }"), "a skill chip runs")
        XCTAssertTrue(chat.contains("if let reason = registry.unavailableReason { query = text; controller.error = reason"), "no model: the reason is shown, not a silent draft")
    }
}

private final class RecordingProvider: LanguageModelProvider {
    var requests: [[ChatMessage]] = []
    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        requests.append(messages)
        return AsyncThrowingStream { continuation in continuation.yield("Answer."); continuation.finish() }
    }
}
