import XCTest
@testable import Graphene

final class CommandTests: XCTestCase {
    func testCompletionRequiresInsertionPointAtEnd() {
        XCTAssertTrue(Omnibox.acceptsCompletion("éx", selection: NSRange(location: 2, length: 0)))
        XCTAssertFalse(Omnibox.acceptsCompletion("example", selection: NSRange(location: 0, length: 7)))
        XCTAssertFalse(Omnibox.acceptsCompletion("example", selection: NSRange(location: 3, length: 0)))
    }
    @MainActor func testLayoutPersistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        XCTAssertEqual(app.layout, .sidebar)
        app.layout = .topTabs; app.persist()
        XCTAssertEqual(AppState(directory: directory).layout, .topTabs)
        app.layout = .sidebar; app.persist()
        XCTAssertEqual(AppState(directory: directory).layout, .sidebar)
    }
    func testSuggestionFixtures() {
        XCTAssertEqual(SearchSuggestions.parse(Data(#"["sw",["swift","swiftui","swift"]]"#.utf8), engine: .google), ["swift", "swiftui"])
        XCTAssertEqual(SearchSuggestions.parse(Data(#"[{"phrase":"swift"},{"phrase":"swiftui"}]"#.utf8), engine: .duckduckgo), ["swift", "swiftui"])
        XCTAssertEqual(SearchSuggestions.parse(Data("invalid".utf8), engine: .google), [])
        XCTAssertEqual(SearchSuggestions.parse(Data(#"["x",[1,null]]"#.utf8), engine: .google), [])
    }
    func testFuzzyActionPrefixes() {
        XCTAssertTrue(CommandMatch.matches("ns", title: "New Space"))
        XCTAssertTrue(CommandMatch.matches("tog side", title: "Toggle Sidebar"))
        XCTAssertFalse(CommandMatch.matches("zz", title: "New Space"))
        XCTAssertTrue(CommandMatch.matches("", title: "New Tab"))
    }
    func testQuestionAndCompletionRouting() {
        XCTAssertTrue(Omnibox.isQuestion("How does WebKit work"))
        XCTAssertTrue(Omnibox.isQuestion("compare @Example and @Apple"))
        XCTAssertTrue(Omnibox.isQuestion("Is this local?"))
        XCTAssertFalse(Omnibox.isQuestion("whatwg.org"))
        XCTAssertFalse(Omnibox.isQuestion("https://example.com/?q=what"))
        XCTAssertEqual(Omnibox.completion("exa", candidates: ["https://example.com/path", "example.org"]), "example.com/path")
        XCTAssertNil(Omnibox.completion("", candidates: ["example.com"]))
        XCTAssertNil(Omnibox.completion("other", candidates: ["example.com"]))
    }
    @MainActor func testLittleDisabledForNewAndLegacyProfiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        XCTAssertFalse(app.littleEnabled)
        XCTAssertFalse(app.littlePinnedLinks)
        app.persist()
        let restored = AppState(directory: directory)
        XCTAssertFalse(restored.littleEnabled)
        XCTAssertFalse(restored.littlePinnedLinks)
    }
}

/// The empty command bar (arc-look.md §3.4): recent tabs in this space, then six everyday commands.
@MainActor
final class EmptyCommandBarTests: XCTestCase {
    func testSuggestedCommandsAreTheEverydaySixInOrder() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let tab = app.newTab(); tab.url = URL(string: "https://example.com")
        let suggested = CommandBarSuggestions.actions(app.commandActions).map(\.id)
        XCTAssertEqual(suggested, ["new-tab", "split", "sidebar", "archive", "library", "ask"])
        for specialist in ["site-controls", "boost", "zap"] {
            XCTAssertFalse(suggested.contains(specialist), "\(specialist) appears only when typed")
            XCTAssertTrue(app.commandActions.contains { $0.id == specialist }, "\(specialist) stays reachable by typing")
        }
        XCTAssertEqual(CommandBarSuggestions.section, "Suggested")
    }

    func testLibraryCommandOpensThePopoverWhenTheSidebarShows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        try XCTUnwrap(app.commandActions.first { $0.id == "library" }).run()
        XCTAssertTrue(app.libraryPresented)
        app.libraryPresented = false; app.layout = .topTabs
        try XCTUnwrap(app.commandActions.first { $0.id == "library" }).run()
        XCTAssertFalse(app.libraryPresented)
        XCTAssertEqual(app.activeSurface, .threads)
    }

    func testRecentTabsComeFromThisSpaceCappedAtFive() {
        let here = UUID(), there = UUID()
        func tab(_ space: UUID, url: String?) -> Tab {
            let tab = Tab(engine: WKWebEngine(privateMode: true), privateMode: true)
            tab.spaceID = space; tab.url = url.flatMap(URL.init(string:))
            return tab
        }
        let current = tab(here, url: "https://current.example")
        let blank = tab(here, url: nil)
        let elsewhere = tab(there, url: "https://elsewhere.example")
        let others = (0..<6).map { tab(here, url: "https://site\($0).example") }
        let picked = CommandBarSuggestions.recentTabs([current, blank, elsewhere] + others, space: here, excluding: current.id)
        XCTAssertEqual(picked.map(\.id), others.prefix(5).map(\.id))
        XCTAssertEqual(CommandBarSuggestions.recentTabLimit, 5)
    }
}
