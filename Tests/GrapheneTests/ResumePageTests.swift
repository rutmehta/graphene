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

    // MARK: entry

    func testNewTabRowOpensResumeAndTheFirstKeyOpensTheCommandBar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("graphene-g3-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        app.openTab(url: URL(string: "https://example.com/page")!, parent: nil, activate: true)
        let page = try XCTUnwrap(app.activeTab)
        let count = app.tabs.count, request = app.resumeFocusRequest

        // "+ New Tab" (row, footer and the command bar's action): a blank Today tab, not the bar.
        app.openResumeTab()
        XCTAssertEqual(app.tabs.count, count + 1)
        XCTAssertNotEqual(app.activeTabID, page.id)
        XCTAssertNil(app.activeTab?.url, "a blank tab shows the Resume page")
        XCTAssertEqual(app.activeTab?.section, .today)
        XCTAssertFalse(app.commandBarPresented)
        XCTAssertEqual(app.resumeFocusRequest, request + 1, "the Resume page takes the keyboard")
        app.openResumeTab()
        XCTAssertEqual(app.tabs.count, count + 1, "a blank selected tab is reused")

        // The first printable key opens the bar in new-tab mode, starting with that key.
        XCTAssertFalse(app.resumeTyped("g", modifiers: .command))
        XCTAssertFalse(app.resumeTyped("\u{F702}"), "arrow keys stay with the page")
        XCTAssertFalse(app.resumeTyped(" "))
        XCTAssertFalse(app.commandBarPresented)
        XCTAssertTrue(app.resumeTyped("g", modifiers: .shift))
        XCTAssertTrue(app.commandBarPresented)
        XCTAssertTrue(app.commandBarCreatesTab)
        XCTAssertEqual(app.commandBarDraft, "g")
        XCTAssertEqual(app.takeResumeKeys(), "", "the field focused before another key")
        XCTAssertFalse(app.resumeTyped("h"), "once open, the bar's field takes the keys")
        let resume = app.activeTabID
        app.commitCommandBar("example.org")
        XCTAssertEqual(app.activeTabID, resume, "the typed query loads in the blank tab")
        XCTAssertEqual(app.tabs.count, count + 1)

        // ⌘T keeps Arc's behaviour: the command bar over the current page.
        app.activate(page.id)
        app.commandActions.first { $0.id == "new-tab" }?.run()
        XCTAssertTrue(app.commandBarPresented)
        XCTAssertTrue(app.commandBarCreatesTab)
        XCTAssertEqual(app.activeTabID, page.id)
        XCTAssertEqual(app.tabs.count, count + 1)
    }

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

    /// Typing "swift" fast: the first key opens the bar, the rest arrive before its field has
    /// focus and are buffered in order, then handed to the field once, after the "s".
    func testBurstTypingOnResumeIsBufferedUntilTheFieldFocuses() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("graphene-g3-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        app.openResumeTab()
        XCTAssertNil(app.resumeKeyBuffer)
        XCTAssertEqual(app.takeResumeKeys(), "", "nothing buffered before the first key")
        for key in ["s", "w", "i", "f", "t"] { XCTAssertTrue(app.resumeTyped(key), key) }
        XCTAssertEqual(app.commandBarDraft, "s", "the first key starts the draft")
        XCTAssertEqual(app.resumeKeyBuffer, "wift", "the rest wait in typing order")
        // Spaces and shifted keys are text; ⌘ shortcuts and arrows are not.
        XCTAssertTrue(app.resumeTyped(" "))
        XCTAssertTrue(app.resumeTyped("U", modifiers: .shift))
        XCTAssertFalse(app.resumeTyped("v", modifiers: .command))
        XCTAssertFalse(app.resumeTyped("\u{F702}"))
        // Delete removes the last buffered key.
        XCTAssertTrue(app.resumeTyped("\u{7F}"))
        XCTAssertEqual(app.resumeKeyBuffer, "wift ")
        XCTAssertTrue(app.resumeTyped("u"))
        XCTAssertEqual(app.takeResumeKeys(), "wift u", "handed over once, in order, for insertion after the first key")
        XCTAssertNil(app.resumeKeyBuffer)
        XCTAssertEqual(app.takeResumeKeys(), "")
        XCTAssertFalse(app.resumeTyped("x"), "after focus the field takes the keys")

        // Dismissing the bar before its field focused drops the buffer.
        app.dismissCommandBar()
        XCTAssertTrue(app.resumeTyped("a"))
        XCTAssertTrue(app.resumeTyped("b"))
        app.dismissCommandBar()
        XCTAssertNil(app.resumeKeyBuffer)
        XCTAssertEqual(app.takeResumeKeys(), "")
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

        // Footnote markers, bracketed superscripts and the spacing around punctuation do not count.
        XCTAssertEqual(CitedPassage.normalized("measured.[7][8] On a microscopic"), "measured.on a microscopic")
        XCTAssertEqual(CitedPassage.normalized("measured. [ 7 ] [ 8 ] On a microscopic"), "measured.on a microscopic")
        XCTAssertEqual(CitedPassage.normalized("Manchester.[citation needed]"), "manchester.")
        XCTAssertEqual(CitedPassage.normalized("carbon ( graphite )"), CitedPassage.normalized("carbon (graphite)"))
        XCTAssertEqual(CitedPassage.normalized("a [ ] b [unclosed"), "a[]b[unclosed")
        XCTAssertEqual(CitedPassage.normalized("soft\u{00AD}hyphen zero\u{200B}width"), "softhyphen zerowidth")
        let wiki = "On a microscopic scale, graphene is the strongest material ever measured.[7][8] The existence of graphene was first theorized in 1947 by Philip R. Wallace."
        XCTAssertTrue(CitedPassage(id: "4", text: "On a microscopic scale, graphene is the strongest material ever measured. [ 7 ] [ 8 ] The existence").matches(in: wiki))
        XCTAssertTrue(CitedPassage(id: "5", text: "measured.The existence of graphene").matches(in: wiki), "a block boundary lost by textContent")
        // Longest run of at least eight words, never fewer and never approximate.
        let run = CitedPassage(id: "6", text: "The existence of graphene was first theorized in 1947 by Andre Geim.")
        XCTAssertEqual(run.matchingRun(in: wiki), "The existence of graphene was first theorized in 1947 by")
        XCTAssertNil(CitedPassage(id: "7", text: "graphene is the strongest material ever tested in labs").matchingRun(in: wiki), "seven words in a row is not enough")
        XCTAssertNil(CitedPassage(id: "8", text: "graphene was the strongest material ever measured by Philip Wallace").matchingRun(in: wiki))
        XCTAssertEqual(CitedPassage(id: "9", text: "The existence of graphene was first theorized in 1947 by Philip R. Wallace.").matchingRun(in: wiki),
                       "The existence of graphene was first theorized in 1947 by Philip R. Wallace.")
    }

    /// The Swift mirror and cite.js normalise identically.
    func testSwiftNormaliserMirrorsCiteScript() throws {
        let script = WKWebEngine.citeScript
        XCTAssertFalse(script.isEmpty, "cite.js is bundled")
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("var window = {}; var document = { addEventListener: function(){} };")
        context.evaluateScript(script)
        let normalize = try XCTUnwrap(context.objectForKeyedSubscript("window")?.objectForKeyedSubscript("__grapheneCite")?.objectForKeyedSubscript("normalize"))
        let samples = ["  Hello\n\n World ", "ÉCOLE\u{00A0}Normale", "a\tb\r\nc", "", "   ", "Straße GROSS", "x  y  z",
                       // Wikipedia's page text, as textContent and as the scraped source shows it.
                       "honeycomb planar nanostructure.[2][3] The name \"graphene\" is derived",
                       "Graphene ( / ˈ ɡ r æ f iː n / ) [ 1 ] is a variety of the element carbon .",
                       "the University of Manchester[10][11] using a piece of graphite.[citation needed]",
                       "measured.Graphene was first", "measured. Graphene was first", "130\u{00A0}GPa (19,000,000 psi)",
                       "[   ] [x] [unclosed", "[" + String(repeating: "a", count: 31) + "] kept", "[" + String(repeating: "a", count: 30) + "] dropped",
                       "zero\u{200B}width soft\u{00AD}hyphen\u{FEFF}bom\u{0085}nel", "İstanbul e\u{301}te 👍🏽 ok", "Philip R. Wallace — (1947)"]
        for sample in samples {
            XCTAssertEqual(normalize.call(withArguments: [sample])?.toString(), CitedPassage.normalized(sample), sample)
        }
        // Both sides pick the same text to mark, whole or as a run.
        let match = try XCTUnwrap(context.objectForKeyedSubscript("window")?.objectForKeyedSubscript("__grapheneCite")?.objectForKeyedSubscript("match"))
        let page = "Graphene is known for its exceptionally high tensile strength, electrical conductivity, transparency.[4] On a microscopic scale, graphene is the strongest material ever measured.[7][8]"
        for passage in ["Graphene is known for its exceptionally high tensile strength , electrical conductivity , transparency . [ 4 ]",
                        "Graphene is known for its exceptionally high tensile strength and is flexible.",
                        "graphene is the strongest material ever measured by anyone",
                        "On a microscopic scale graphene is strong", "transparency.On a microscopic scale, graphene is the strongest material"] {
            let js = match.call(withArguments: [page, passage])
            let swift = CitedPassage(id: "x", text: passage).matchingRun(in: page)
            XCTAssertEqual(js?.isNull == true ? nil : js?.toString(), swift, passage)
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

    /// A page built like Wikipedia's (footnote superscripts and links inside sentences, a hidden
    /// math fallback, a sentence split across two paragraphs): the text Graphene captures for
    /// the model yields passages the page marks, and a partial passage marks its longest run.
    func testHighlightMatchesPassagesFromWikipediaStructuredPage() async throws {
        let engine = WKWebEngine()
        let ref = { (n: String) in "<sup class=\"reference\"><a href=\"#cite_note-\(n)\"><span class=\"cite-bracket\">[</span>\(n)<span class=\"cite-bracket\">]</span></a></sup>" }
        let html = """
        <html><head><title>Graphene - Wikipedia</title></head><body><header>Main menu</header><main><h1>Graphene</h1><div class="mw-parser-output">
        <p><b>Graphene</b> (<span class="IPA">/ˈɡræf.iːn/</span>\(ref("1"))) is a variety of the element <a href="/wiki/Carbon">carbon</a> which occurs naturally in small amounts.</p>
        <p>Graphene is known for its exceptionally high <a href="/wiki/Tensile_strength">tensile strength</a>, <a href="/wiki/Conductivity">electrical conductivity</a>, transparency, and being the thinnest two-dimensional material in the world.\(ref("4")) On a microscopic scale, graphene is the strongest material ever measured.\(ref("7"))\(ref("8"))</p>
        <p>The existence of graphene was first theorized in 1947 by <a href="/wiki/Philip_R._Wallace">Philip R. Wallace</a> during his research on graphite's electronic properties.\(ref("9")) In 2004, the material was isolated and characterized by</p><p><a href="/wiki/Andre_Geim">Andre Geim</a> and Konstantin Novoselov at the University of Manchester.\(ref("10"))<sup class="noprint">[<i>citation needed</i>]</sup></p>
        <p>It has an ultimate tensile strength of 130&nbsp;GPa<span class="mwe-math-element"><span aria-hidden="true">σ</span></span> and a Young's modulus of 1&nbsp;TPa.</p>
        </div></main></body></html>
        """
        engine.webView.loadHTMLString(html, baseURL: URL(string: "https://en.wikipedia.org/wiki/Graphene"))
        for _ in 0..<100 where engine.isLoading || engine.currentURL == nil { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(150))
        let captured = await engine.captureReadableContent().text
        XCTAssertTrue(captured.contains("strongest material ever measured"), captured)
        let source = PageContext.budget([KnowledgeSource(id: UUID(), title: "Graphene - Wikipedia", url: "https://en.wikipedia.org/wiki/Graphene", text: captured, kind: "Tab")], limit: 6000).sources[0]

        // Passages picked from the captured text, as a finished answer's citations pick them.
        let claims = ["On a microscopic scale graphene is the strongest material ever measured.",
                      "Graphene is known for its high tensile strength and electrical conductivity.",
                      "Its existence was first theorized in 1947 by Philip R. Wallace.",
                      "It was isolated in 2004 by Andre Geim and Konstantin Novoselov at the University of Manchester.",
                      "Its ultimate tensile strength is 130 GPa and its Young's modulus is 1 TPa."]
        var passages: [CitedPassage] = []
        for (offset, claim) in claims.enumerated() {
            let text = try XCTUnwrap(PageContext.passage(for: claim, in: source), claim)
            passages.append(CitedPassage(id: "p\(offset)", text: text, index: offset + 1))
            XCTAssertTrue(passages[offset].matches(in: captured), text)
        }
        XCTAssertTrue(passages[3].text.contains("characterized by Andre Geim"), "the sentence spans two paragraphs: \(passages[3].text)")
        let found = await engine.highlight(passages: passages)
        XCTAssertEqual(found, passages.map(\.id), "every passage from the page is found in the page")
        let philip = await engine.evaluateJavaScript("Array.from(document.querySelectorAll('mark[data-graphene-cite=\"p2\"]')).map(m => m.textContent).join('')") as? String
        XCTAssertEqual(philip.map(CitedPassage.normalized), CitedPassage.normalized(passages[2].text))

        // A passage that runs past the page's wording marks only its longest exact run.
        let partial = CitedPassage(id: "run", text: "Graphene is known for its exceptionally high tensile strength and remarkable flexibility.")
        let approximate = CitedPassage(id: "near", text: "Graphene is famous for its very high tensile strength and conductivity.")
        let more = await engine.highlight(passages: [partial, approximate])
        XCTAssertEqual(more, ["run"], "an approximate match is never marked")
        let marked = await engine.evaluateJavaScript("Array.from(document.querySelectorAll('mark[data-graphene-cite=\"run\"]')).map(m => m.textContent).join('')") as? String
        XCTAssertEqual(marked, "Graphene is known for its exceptionally high tensile strength")
        XCTAssertEqual(partial.matchingRun(in: captured), "Graphene is known for its exceptionally high tensile strength")
        await engine.clearHighlights()
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
