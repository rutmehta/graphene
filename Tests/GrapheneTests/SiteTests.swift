import XCTest
import WebKit
@testable import Graphene

final class SiteTests: XCTestCase {
    @MainActor func testRoutedNewTabUsesDestinationProfile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("routed-profiles-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        let profile = Profile(name: "Work"); app.profiles = [profile]; app.spaces[1].profileID = profile.id
        app.settings.routingRules = [RoutingRule(pattern: "https://profile.invalid/*", spaceID: app.spaces[1].id)]
        app.openTab(url: URL(string: "https://profile.invalid/")!, parent: nil, activate: false)
        app.activeTab?.stop()
        XCTAssertEqual(app.activeTab?.profileID, profile.id)
    }
    @MainActor func testRestoredBlankTabUsesItsOwnSpacesProfile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blank-profiles-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        let profile = Profile(name: "Work"); app.profiles = [profile]; app.spaces[0].profileID = profile.id
        app.activeSpaceID = app.spaces[1].id
        let blank = app.newTab()
        app.activeSpaceID = app.spaces[0].id; app.activeTabID = app.tabs.first?.id; app.persist()
        let restored = AppState(directory: root)
        let tab = try XCTUnwrap(restored.tabs.first { $0.id == blank.id })
        let engine = try XCTUnwrap(tab.engine as? WKWebEngine)
        let expected = Profile.storeID(Profile.defaultID, namespace: ProcessInfo.processInfo.environment["GRAPHENE_DATA_DIR"])
        XCTAssertEqual(engine.webView.configuration.websiteDataStore.identifier, expected)
    }
    @MainActor func testProfileAssignmentSurvivesSessionRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("profiles-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        let profile = Profile(name: "Work")
        app.profiles = [profile]
        app.spaces[0].profileID = profile.id
        app.persist()
        let restored = AppState(directory: root)
        XCTAssertEqual(restored.profiles, [profile])
        XCTAssertEqual(restored.spaces[0].profileID, profile.id)
        XCTAssertEqual(restored.newTab().profileID, profile.id)
    }
    func testBoostStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("boosts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Boosts(directory: root)
        var boost = Boost(host: "example.com"); boost.css = "p { font-size: 20px; }"; boost.javascript = "window.testBoost = true"; boost.selectors = ["#advert"]
        try store.save(boost)
        XCTAssertEqual(Boosts(directory: root).boost("example.com"), boost)
    }
    @MainActor func testBundledNetworkRulesCompileInWebKit() async throws {
        let list = try await ContentBlocker.compile()
        XCTAssertTrue(list.identifier.hasPrefix("graphene-"))
    }
    @MainActor func testImportApplicationIsIdempotentAndDoesNotLoadPins() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        let file = Bundle.module.url(forResource: "arc-sidebar", withExtension: "json", subdirectory: "Fixtures")!
        let batch = try Importer.arc(Data(contentsOf: file))
        _ = await app.applyImport(batch)
        let count = app.tabs.count
        _ = await app.applyImport(batch)
        XCTAssertEqual(app.tabs.count, count)
        let imported = app.tabs.filter(\.isPinned)
        XCTAssertEqual(imported.count, 2)
        XCTAssertTrue(imported.allSatisfy { $0.loadedEngine == nil })
        XCTAssertTrue(app.graph.nodeArray.isEmpty)
    }
    @MainActor func testReaderCollapsesWhitespaceOnlyLinesInWebKit() async throws {
        let engine = WKWebEngine(privateMode: true)
        engine.webView.loadHTMLString("<main><p>First</p>\n   \n   \n<p>Second</p></main>", baseURL: URL(string: "https://example.com"))
        for _ in 0..<100 {
            if await engine.evaluateJavaScript("document.querySelector('main') !== null") as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let text = await engine.evaluateJavaScript(ReaderMode.extractor) as? String
        XCTAssertEqual(text, "First\n\nSecond")
    }
    func testFindCounterWrapsAndResetsForNewQuery() {
        var counter = FindCounter()
        counter.update(query: "a", total: 3, backwards: false, found: true)
        XCTAssertEqual(counter.current, 1)
        counter.update(query: "a", total: 3, backwards: true, found: true)
        XCTAssertEqual(counter.current, 3)
        counter.update(query: "b", total: 0, backwards: false, found: false)
        XCTAssertEqual(counter.current, 0)
    }
    func testChromeBookmarksFixtureExcludesExecutableURLs() throws {
        let file = Bundle.module.url(forResource: "chrome-bookmarks", withExtension: "json", subdirectory: "Fixtures")!
        let result = try Importer.chrome(Data(contentsOf: file))
        XCTAssertEqual(result.bookmarks.count, 2)
        XCTAssertEqual(result.bookmarks.first?.title, "Graphene")
    }
    func testArcSidebarFixturePreservesSpaceAndPinsOnly() throws {
        let file = Bundle.module.url(forResource: "arc-sidebar", withExtension: "json", subdirectory: "Fixtures")!
        let result = try Importer.arc(Data(contentsOf: file))
        XCTAssertEqual(result.spaces.map(\.name), ["Materials"])
        XCTAssertEqual(result.bookmarks.count, 2)
        XCTAssertEqual(result.bookmarks.first { $0.title == "Graphene" }?.space, "Materials")
        XCTAssertEqual(result.bookmarks.filter(\.favorite).count, 1)
    }
    func testProfileStoreIdentityIsNamespaced() {
        let id = UUID()
        XCTAssertEqual(Profile.storeID(id, namespace: "/tmp/a"), Profile.storeID(id, namespace: "/tmp/a"))
        XCTAssertNotEqual(Profile.storeID(id, namespace: "/tmp/a"), Profile.storeID(id, namespace: "/tmp/b"))
        XCTAssertNotEqual(Profile.storeID(id, namespace: "/tmp/a"), id)
        XCTAssertEqual(Profile.storeID(id, namespace: nil), id)
    }
    func testReaderEstimatesTimeWithoutHTML() {
        let article = ReaderArticle(title: "Article", url: URL(string: "https://example.com")!, text: Array(repeating: "word", count: 450).joined(separator: " "))
        XCTAssertEqual(article.minutes, 3)
    }
    func testBoostInjectionQuotesCSSAndScopesHost() throws {
        var boost = Boost(host: "example.com")
        boost.css = "body::after { content: '\"quoted\"'; }"
        boost.selectors = ["#advert"]
        XCTAssertTrue(boost.styleScript.contains("location.hostname"))
        XCTAssertTrue(boost.styleScript.contains("example.com"))
        XCTAssertTrue(boost.renderedCSS.contains("#advert { display: none !important; }"))
        XCTAssertTrue(boost.styleScript.contains("textContent"))
        boost.enabled = false
        XCTAssertEqual(boost.renderedCSS, "")
    }
    func testBundledBlockRulesHaveNetworkSchema() throws {
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: ContentBlocker.data) as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(rules.count, 1900)
        XCTAssertLessThan(ContentBlocker.data.count, 1_500_000)
        for rule in rules {
            let trigger = try XCTUnwrap(rule["trigger"] as? [String: Any])
            XCTAssertNotNil(trigger["url-filter"] as? String)
            XCTAssertEqual((rule["action"] as? [String: String])?["type"], "block")
        }
    }
    func testZoomClampsAndRoundTripsPerHost() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sites-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = SiteSettings(file: file)
        var site = store.site("EXAMPLE.com")
        site.zoom = SiteSettings.zoom(1, factor: 1.1)
        try store.set(site, host: "EXAMPLE.com")
        XCTAssertEqual(SiteSettings(file: file).site("example.com").zoom, 1.1)
        XCTAssertEqual(SiteSettings.zoom(3, factor: 1.1), 3)
        XCTAssertEqual(SiteSettings.zoom(0.25, factor: 0.1), 0.25)
        XCTAssertEqual(SiteSettings.zoom(2, factor: 0), 1)
        XCTAssertEqual(store.site("other.example").zoom, 1)
    }
}
