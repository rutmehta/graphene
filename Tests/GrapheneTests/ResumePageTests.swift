import XCTest
import SwiftUI
import JavaScriptCore
import WebKit
@testable import Graphene

/// G3: Resume page sections, lattice geometry, citation passage matching and `openSource`
/// (graphene-identity.md §3.3, §3.6; graphene-language.md §4).
@MainActor
final class ResumePageTests: XCTestCase {
    private let space = UUID()
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func node(_ host: String) -> GraphNode {
        GraphNode(id: UUID(), url: "https://\(host)/", title: host, host: host, firstVisit: now, lastVisit: now,
                  visitCount: 1, spaceID: space, query: nil, annotationCount: 0, snippet: "", x: 0, y: 0)
    }
    private func thread(_ title: String, pages: Int, minutesAgo: Double) -> KnowledgeGraph.Thread {
        let nodes = (0..<pages).map { node("site\($0).example") }
        let end = now.addingTimeInterval(-minutesAgo * 60)
        return KnowledgeGraph.Thread(id: UUID(), nodes: nodes, start: end, end: end, title: title, query: nil,
                                     noteCount: 0, hosts: nodes.map(\.host))
    }
    private func note(_ text: String, space: UUID?, minutesAgo: Double, url: String = "https://example.com/a", title: String = "Source") -> Annotation {
        Annotation(id: UUID(), text: text, note: "", url: url, title: title, context: "",
                   created: now.addingTimeInterval(-minutesAgo * 60), spaceID: space, provenance: "web page", accountScope: nil)
    }

    // MARK: tokens

    func testG3TokensMatchSpec() {
        XCTAssertEqual(ShellLayout.newTabColumnWidth, 560)
        XCTAssertEqual(ShellLayout.newTabGap, 24)
        XCTAssertEqual(ShellLayout.latticeCell, 28)
        XCTAssertEqual(ShellLayout.markInset, 1)
        XCTAssertEqual(ShellType.quoteSize, 13)
        XCTAssertEqual(ShellType.quoteSmallSize, 12)
        XCTAssertEqual(ShellType.quoteLineSpacing, 13 * 0.45, accuracy: 0.0001)
        for mode in [ThemeMode.light, .dark] {
            let palette = Palette(mode: mode, space: .tide)
            func alpha(_ color: Color) -> Double { Double(NSColor(color).usingColorSpace(.sRGB)?.alphaComponent ?? -1) }
            XCTAssertEqual(alpha(palette.lattice), 0.04, accuracy: 0.001)
            XCTAssertEqual(alpha(palette.highlight), 0.22, accuracy: 0.001)
            XCTAssertEqual(alpha(palette.highlightActive), 0.38, accuracy: 0.001)
            XCTAssertEqual(alpha(palette.threadLine), mode == .dark ? 0.18 : 0.14, accuracy: 0.001)
            XCTAssertEqual(alpha(palette.quoteRule), alpha(palette.threadLine), accuracy: 0.001)
        }
    }

    func testG3FilesUseTokensNotLiterals() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in ["UI/ResumePage.swift", "UI/Lattice.swift", "UI/SurfaceState.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/Graphene/\(path)"), encoding: .utf8)
            for pattern in [#"\.font\(\.system\(size:"#, #"cornerRadius:\s*[0-9]"#, #"\.opacity\("#] {
                XCTAssertNil(source.range(of: pattern, options: .regularExpression), "\(path) has a literal matching \(pattern)")
            }
        }
    }

    // MARK: resume page sections

    func testFreshProfileShowsOnlySearchAndLattice() {
        let sections = ResumeSections.build(threads: [], notes: [], spaceID: space, favoriteIDs: [UUID()], sidebarCollapsed: false)
        XCTAssertTrue(sections.isEmpty)
        XCTAssertTrue(sections.continueRows.isEmpty && sections.savedRows.isEmpty && sections.favoriteIDs.isEmpty)
    }

    func testContinueShowsNewestThreeThreadsWithCounts() {
        let threads = [thread("Old", pages: 1, minutesAgo: 300), thread("New", pages: 6, minutesAgo: 120),
                       thread("Mid", pages: 2, minutesAgo: 200), thread("Oldest", pages: 4, minutesAgo: 900)]
        let sections = ResumeSections.build(threads: threads, notes: [], spaceID: space, sidebarCollapsed: false)
        XCTAssertEqual(sections.continueRows.map(\.title), ["New", "Mid", "Old"])
        XCTAssertEqual(sections.continueRows.first?.pageCount, 6)
        XCTAssertEqual(sections.continueRows.first?.host, "site0.example")
        XCTAssertFalse(sections.isEmpty)
        XCTAssertEqual(ResumeSections.detail(pageCount: 6, end: now.addingTimeInterval(-7200), now: now), "6 pages · 2h ago")
        XCTAssertEqual(ResumeSections.detail(pageCount: 1, end: now.addingTimeInterval(-30), now: now), "1 page · just now")
        XCTAssertEqual(ResumeSections.relative(now.addingTimeInterval(-5 * 60), now: now), "5m ago")
        XCTAssertEqual(ResumeSections.relative(now.addingTimeInterval(-3 * 86_400), now: now), "3d ago")
    }

    func testSavedHereShowsFourNewestQuotesFromThisSpace() {
        let other = UUID()
        let notes = (0..<6).map { note("Quote \($0)", space: space, minutesAgo: Double($0)) }
            + [note("Elsewhere", space: other, minutesAgo: 0), note("", space: space, minutesAgo: 0),
               note("Manual", space: space, minutesAgo: 0, url: ""), note("Line one\nline two", space: space, minutesAgo: -1)]
        let sections = ResumeSections.build(threads: [], notes: notes, spaceID: space, sidebarCollapsed: false)
        XCTAssertEqual(sections.savedRows.map(\.quote), ["Line one line two", "Quote 0", "Quote 1", "Quote 2"])
        XCTAssertEqual(sections.savedRows.first?.url.absoluteString, "https://example.com/a")
        XCTAssertEqual(sections.savedRows.first?.sourceTitle, "Source")
    }

    func testFavoritesAppearOnlyWithTheSidebarCollapsed() {
        let favorites = [UUID(), UUID()]
        let expanded = ResumeSections.build(threads: [], notes: [], spaceID: space, favoriteIDs: favorites, sidebarCollapsed: false)
        XCTAssertTrue(expanded.favoriteIDs.isEmpty)
        let collapsed = ResumeSections.build(threads: [], notes: [], spaceID: space, favoriteIDs: favorites, sidebarCollapsed: true)
        XCTAssertEqual(collapsed.favoriteIDs, favorites)
        XCTAssertFalse(collapsed.isEmpty)
    }

    // MARK: lattice

    func testLatticeGeometry() {
        let cell = ShellLayout.latticeCell
        XCTAssertEqual(LatticeGeometry.radius(cell: cell), 28 / 3.0.squareRoot(), accuracy: 0.0001)
        XCTAssertEqual(LatticeGeometry.rowPitch(cell: cell), 1.5 * 28 / 3.0.squareRoot(), accuracy: 0.0001)
        let vertices = LatticeGeometry.vertices(center: .zero, cell: cell)
        XCTAssertEqual(vertices.count, 6)
        // Pointy-top: the flat-to-flat width is exactly one cell.
        XCTAssertEqual((vertices.map(\.x).max() ?? 0) - (vertices.map(\.x).min() ?? 0), cell, accuracy: 0.0001)
        let size = CGSize(width: 560, height: 140)
        let centers = LatticeGeometry.centers(in: size, cell: cell)
        XCTAssertEqual(centers.first, .zero)
        // Odd rows shift half a cell; every row is one pitch lower.
        let second = centers.first { $0.y > 0 }
        XCTAssertEqual(second?.x ?? -1, cell / 2, accuracy: 0.0001)
        XCTAssertEqual(second?.y ?? -1, LatticeGeometry.rowPitch(cell: cell), accuracy: 0.0001)
        // The tiling covers the whole rectangle.
        XCTAssertGreaterThanOrEqual((centers.map(\.x).max() ?? 0) + cell / 2, size.width)
        XCTAssertGreaterThanOrEqual((centers.map(\.y).max() ?? 0) + LatticeGeometry.radius(cell: cell), size.height)
        XCTAssertTrue(LatticeGeometry.centers(in: .zero, cell: cell).isEmpty)
        XCTAssertEqual(LatticeGeometry.fadeStart, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testLatticeOnlyInEmptyThreadsAndVault() {
        XCTAssertTrue(SurfaceState<EmptyView>.showsLattice(surface: .threads, symbol: "point.3.connected.trianglepath.dotted", loading: false))
        XCTAssertTrue(SurfaceState<EmptyView>.showsLattice(surface: .vault, symbol: "bookmark", loading: false))
        XCTAssertFalse(SurfaceState<EmptyView>.showsLattice(surface: .vault, symbol: "exclamationmark.triangle", loading: false))
        XCTAssertFalse(SurfaceState<EmptyView>.showsLattice(surface: .threads, symbol: "bookmark", loading: true))
        XCTAssertFalse(SurfaceState<EmptyView>.showsLattice(surface: .mail, symbol: "envelope", loading: false))
        XCTAssertFalse(SurfaceState<EmptyView>.showsLattice(surface: .web, symbol: "exclamationmark.shield", loading: false))
    }

    // MARK: cited passages

    func testCitedPassageNormalisation() {
        XCTAssertEqual(CitedPassage.normalized("  The Tensile\n\tstrength  is 130 GPa. "), "the tensile strength is 130 gpa.")
        XCTAssertEqual(CitedPassage.normalized(" \n "), "")
        let passage = CitedPassage(id: "1", text: "tensile STRENGTH\nis 130 GPa")
        XCTAssertTrue(passage.matches(in: "Graphene has a tensile strength   is 130 GPa, the highest."))
        // Never an approximate match: a paraphrase or a different number does not count.
        XCTAssertFalse(passage.matches(in: "Graphene has a tensile strength of 130 GPa."))
        XCTAssertFalse(CitedPassage(id: "2", text: "  ").matches(in: "anything"))
        XCTAssertNil(passage.index)
        XCTAssertEqual(CitedPassage(id: "3", text: "x", index: 2).index, 2)
    }

    /// The Swift mirror and cite.js normalise identically.
    func testSwiftNormaliserMirrorsCiteScript() throws {
        let script = WKWebEngine.citeScript
        XCTAssertFalse(script.isEmpty, "cite.js is bundled")
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("var window = {}; var document = { addEventListener: function(){} };")
        context.evaluateScript(script)
        let normalize = try XCTUnwrap(context.objectForKeyedSubscript("window")?.objectForKeyedSubscript("__grapheneCite")?.objectForKeyedSubscript("normalize"))
        for sample in ["  Hello\n\n World ", "ÉCOLE\u{00A0}Normale", "a\tb\r\nc", "", "   ", "Straße GROSS", "x  y  z"] {
            XCTAssertEqual(normalize.call(withArguments: [sample])?.toString(), CitedPassage.normalized(sample), sample)
        }
    }

    func testCiteStyleIsCSSFromPaletteTokens() {
        let palette = Palette(mode: .light, space: .tide)
        let style = WKWebEngine.citeStyle(palette)
        XCTAssertEqual(style["inset"] as? Double, 1)
        XCTAssertTrue((style["highlight"] as? String)?.hasSuffix(",0.22)") == true)
        XCTAssertTrue((style["highlightActive"] as? String)?.hasSuffix(",0.38)") == true)
        XCTAssertTrue((style["accent"] as? String)?.hasPrefix("rgba(") == true)
        XCTAssertEqual(WKWebEngine.cssColor(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.5)), "rgba(255,0,0,0.5)")
    }

    /// cite.js in a real page: exact matches across nodes are marked, approximate ones never.
    func testHighlightMarksExactPassagesOnly() async throws {
        let engine = WKWebEngine(configuration: WKWebViewConfiguration())
        engine.webView.loadHTMLString("<html><body><p>Graphene has a <b>tensile strength</b> of 130 GPa.</p><p>Second paragraph.</p></body></html>", baseURL: nil)
        for _ in 0..<100 where engine.isLoading || engine.currentURL == nil { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(100))
        let found = await engine.highlight(passages: [
            CitedPassage(id: "a", text: "TENSILE strength of 130\n GPa", index: 1),
            CitedPassage(id: "b", text: "tensile strength is 130 GPa"),
            CitedPassage(id: "c", text: "130 GPa. Second"),
        ])
        XCTAssertEqual(found, ["a", "c"])
        let marks = await engine.evaluateJavaScript("document.querySelectorAll('mark[data-graphene-cite=\"a\"]').length") as? Int
        XCTAssertEqual(marks, 2, "the passage spans the <b> and the text after it")
        let text = await engine.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertEqual(text?.contains("Graphene has a tensile strength of 130 GPa."), true, "marks never change the text")
        await engine.setActiveHighlight("a")
        let active = await engine.evaluateJavaScript("document.querySelectorAll('mark.active').length") as? Int
        XCTAssertEqual(active, 2)
        await engine.clearHighlights()
        let remaining = await engine.evaluateJavaScript("document.querySelectorAll('mark').length") as? Int
        XCTAssertEqual(remaining, 0)
    }

    func testPrivateEnginesNeverHighlight() async {
        let engine = WKWebEngine(privateMode: true)
        let found = await engine.highlight(passages: [CitedPassage(id: "a", text: "anything")])
        XCTAssertEqual(found, [])
    }

    // MARK: openSource

    func testSourceTargetPrefersExistingTab() {
        let url = URL(string: "https://example.com/page#section")!
        let active = UUID(), here = UUID(), elsewhere = UUID()
        let tabs = [SourceTarget.Candidate(id: active, url: URL(string: "https://other.com")!, spaceID: space),
                    SourceTarget.Candidate(id: elsewhere, url: URL(string: "https://example.com/page")!, spaceID: UUID()),
                    SourceTarget.Candidate(id: here, url: URL(string: "https://example.com/page/")!, spaceID: space)]
        XCTAssertEqual(SourceTarget.choose(url: url, tabs: tabs, activeTabID: active, spaceID: space), .existing(here))
        XCTAssertEqual(SourceTarget.choose(url: url, tabs: Array(tabs.prefix(2)), activeTabID: active, spaceID: space), .existing(elsewhere))
        let blank = SourceTarget.Candidate(id: UUID(), url: nil, spaceID: space)
        XCTAssertEqual(SourceTarget.choose(url: url, tabs: [tabs[0], blank], activeTabID: blank.id, spaceID: space), .reuseActive(blank.id))
        XCTAssertEqual(SourceTarget.choose(url: url, tabs: [tabs[0], blank], activeTabID: active, spaceID: space), .newTab)
    }

    func testOpenSourceSwitchesToExistingTabOrOpensOne() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("graphene-g3-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        let first = app.newTab()
        first.url = URL(string: "https://example.com/source")
        let second = app.newTab()
        second.url = URL(string: "https://other.example/")
        XCTAssertEqual(app.activeTabID, second.id)
        let count = app.tabs.count

        let switched = app.openSource(url: URL(string: "https://example.com/source")!, passage: nil)
        XCTAssertTrue(switched === first)
        XCTAssertEqual(app.activeTabID, first.id)
        XCTAssertEqual(app.tabs.count, count)

        let opened = app.openSource(url: URL(string: "https://example.com/new")!, passage: nil)
        XCTAssertEqual(app.tabs.count, count + 1)
        XCTAssertEqual(app.activeTabID, opened?.id)
        XCTAssertEqual(opened?.url?.absoluteString, "https://example.com/new")
        XCTAssertEqual(app.activeSurface, .web)
    }
}
