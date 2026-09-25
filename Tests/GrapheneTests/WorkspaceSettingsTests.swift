import XCTest
@testable import Graphene

final class WorkspaceSettingsTests: XCTestCase {
    func testCustomSearchEscapesQueryAndRejectsUnsafeTemplates() {
        guard case .search(let url, _) = Omnibox.resolve("a & b", customSearchURL: "https://example.org/search?q=%s") else { return XCTFail("Expected custom search") }
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "a & b")
        XCTAssertNil(Omnibox.resolve("query", customSearchURL: "javascript:%s"))
        XCTAssertNil(Omnibox.resolve("query", customSearchURL: "https://example.org/no-placeholder"))
    }
    @MainActor func testWindowViewConstructionDoesNotAllocatePhantomTabs() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        let count = app.tabs.count
        _ = BrowserWindowRoot(state: WindowState(app: AppState(sharing: app)))
        XCTAssertEqual(app.tabs.count, count)
    }
    @MainActor func testNoteProvenancePersistsWithoutBrowsingVisit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        app.vault.add(text: "Message excerpt", note: "", url: nil, title: "Message", context: "", spaceID: app.activeSpaceID, provenance: "mail", accountScope: "fixture-account")
        let note = try XCTUnwrap(AppState(directory: root).vault.annotations.first)
        XCTAssertEqual(note.provenance, "mail")
        XCTAssertEqual(note.accountScope, "fixture-account")
        XCTAssertEqual(note.spaceID, app.activeSpaceID)
    }
    @MainActor func testShortcutOverridesConflictAndRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        let shortcut = CommandShortcut(key: "j", command: true, option: true)
        XCTAssertNil(app.remapCommand("board", to: shortcut))
        XCTAssertNotNil(app.remapCommand("threads", to: shortcut))
        XCTAssertEqual(app.commandActions.first { $0.id == "board" }?.hint, "⌥⌘J")
        app.persist()
        XCTAssertEqual(AppState(directory: root).settings.shortcutOverrides["board"], shortcut)
    }
    @MainActor func testBoardPersistenceAndSpaceScope() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("boards.json")
        let store = BoardStore(file: file)
        let space = UUID()
        var item = BoardItem(spaceID: space, title: "Source", text: "A note", url: "https://example.org")
        store.upsert(item)
        item.x = 120; item.width = 320; store.upsert(item)
        let restored = BoardStore(file: file)
        XCTAssertEqual(restored.items(in: space), [item])
        XCTAssertTrue(restored.items(in: UUID()).isEmpty)
        XCTAssertTrue(restored.markdown(spaceID: space).contains("https://example.org"))
        restored.delete(item.id)
        XCTAssertTrue(BoardStore(file: file).items(in: space).isEmpty)
    }
    func testToastQueuePausesAndPreservesOrder() {
        var queue = ToastQueue()
        queue.enqueue(title: "First", seconds: 5)
        queue.enqueue(title: "Second", seconds: 3)
        queue.tick(seconds: 4)
        queue.isPaused = true
        queue.tick(seconds: 10)
        XCTAssertEqual(queue.items.first?.title, "First")
        queue.isPaused = false
        queue.tick(seconds: 1)
        XCTAssertEqual(queue.items.first?.title, "Second")
        queue.tick(seconds: 3)
        XCTAssertTrue(queue.items.isEmpty)
    }
    @MainActor func testRoutingGlobsAndDestination() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        let destination = app.spaces[1].id
        let rule = RoutingRule(pattern: "https://example.org/*", spaceID: destination)
        XCTAssertTrue(rule.matches(URL(string: "https://example.org/a?b=c")!))
        XCTAssertFalse(rule.matches(URL(string: "https://exampleXorg/a")!))
        XCTAssertFalse(rule.matches(URL(string: "https://evil.org/https://example.org/a")!))
        app.settings.routingRules = [rule]
        app.openTab(url: URL(string: "https://example.org/a")!, parent: app.activeTab, activate: false)
        XCTAssertEqual(app.activeSpaceID, destination)
        XCTAssertEqual(app.activeTab?.spaceID, destination)
        app.persist()
        XCTAssertEqual(AppState(directory: root).settings.routingRules, [rule])
    }
    @MainActor func testSettingsRoundTripAndLegacyDefaults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        app.settings.pageGutter = false
        app.settings.askWidth = 480
        app.settings.chatPanelMode = .docked
        app.settings.onboardingComplete = true
        app.persist()
        let restored = AppState(directory: root)
        XCTAssertFalse(restored.settings.pageGutter)
        XCTAssertEqual(restored.settings.askWidth, 480)
        XCTAssertEqual(restored.settings.chatPanelMode, .docked)
        XCTAssertTrue(restored.settings.onboardingComplete)
        let defaults = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertTrue(defaults.pageGutter)
        XCTAssertEqual(defaults.askWidth, 420)
        XCTAssertEqual(defaults.chatPanelMode, .floating)
    }
}
