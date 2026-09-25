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
