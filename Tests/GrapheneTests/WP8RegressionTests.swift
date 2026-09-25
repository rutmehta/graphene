import XCTest
import AppKit
@testable import Graphene

final class WP8RegressionTests: XCTestCase {
    @MainActor func testGlobalThumbnailBound() {
        let cache = ThumbnailCache(capacity: 2)
        let a = UUID(), b = UUID(), c = UUID(), image = NSImage(size: NSSize(width: 1, height: 1))
        cache.put(image, for: a); cache.put(image, for: b); cache.put(image, for: a); cache.put(image, for: c)
        XCTAssertEqual(Set(cache.images.keys), [a, c])
    }
    func testBranchesPreserveSiblingsAndSurviveCycles() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let rows = ThreadBranch.rows(ids: [a, b, c, d], parents: [b:a, c:a, d:b])
        XCTAssertEqual(rows.map(\.id), [a, b, d, c]); XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 1])
        XCTAssertEqual(ThreadBranch.rows(ids: [a,b], parents: [a:b,b:a]).count, 2)
    }
    func testPageFontLegacyDefaultsAndRoundTrip() throws {
        XCTAssertNil(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).pageFont)
        var settings = Settings(); settings.pageFont = .serif
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)).pageFont, .serif)
        XCTAssertEqual(PageFont.website.css, "")
    }
    @MainActor func testNoteDropsRespectPrivacyAndDeduplicate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        app.vault.add(text: "Saved quote", note: "My note", url: URL(string: "https://example.org")!, title: "Example", context: "", spaceID: app.activeSpaceID)
        let note = try XCTUnwrap(app.vault.annotations.first)
        let payload = "note:\(note.id)"
        XCTAssertEqual(app.noteDropSources([payload, payload]).map(\.text), ["Saved quote\n\nMy note"])
        XCTAssertTrue(app.noteDropSources(["note:not-a-uuid", "tab:\(note.id)"]).isEmpty)
        app.excludedHosts.insert("example.org")
        XCTAssertTrue(app.noteDropSources([payload]).isEmpty)
    }
    @MainActor func testExactFindUsesSameRangesForCountAndSelection() async throws {
        let engine = WKWebEngine(privateMode: true)
        engine.webView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        engine.webView.loadHTMLString("<main><p>Alpha <b>beta</b> alpha beta</p><p style='display:none'>alpha beta</p><p>ALPHA BETA</p></main>", baseURL: URL(string: "https://example.org"))
        for _ in 0..<100 {
            if await engine.evaluateJavaScript("document.querySelector('main') !== null") as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let first = await engine.evaluateJavaScript(FindCounter.script(query: "alpha beta", backwards: false)) as? [String: Int]
        XCTAssertEqual(first?["total"], 3); XCTAssertEqual(first?["current"], 1)
        let next = await engine.evaluateJavaScript(FindCounter.script(query: "alpha beta", backwards: false)) as? [String: Int]
        XCTAssertEqual(next?["current"], 2)
        let previous = await engine.evaluateJavaScript(FindCounter.script(query: "alpha beta", backwards: true)) as? [String: Int]
        XCTAssertEqual(previous?["current"], 1)
    }
}
