import XCTest
import SwiftUI
import JavaScriptCore
import WebKit
@testable import Graphene

/// G7: annotations and the Vault list (graphene-language.md §5.3).
@MainActor
final class AnnotationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let english = Locale(identifier: "en_US")

    private func note(_ text: String, url: String = "https://example.com/a", title: String = "An article",
                      space: UUID? = nil, hoursAgo: Double = 0, note: String = "") -> Annotation {
        Annotation(id: UUID(), text: text, note: note, url: url, title: title, context: "",
                   created: now.addingTimeInterval(-hoursAgo * 3600), spaceID: space, provenance: "web page", accountScope: nil)
    }

    // MARK: tokens

    func testAnnotationTokens() {
        XCTAssertEqual(ShellLayout.annotationBarHeight, 36)
        XCTAssertEqual(ShellLayout.annotationCardWidth, 320)
        XCTAssertEqual(ShellLayout.annotationGap, 8)
        XCTAssertEqual(ShellType.labelSize, 11)
        let style = WKWebEngine.annotationStyle(Palette(mode: .dark, space: .graphite))
        XCTAssertEqual(style["barHeight"] as? Double, 36)
        XCTAssertEqual(style["cardWidth"] as? Double, 320)
        XCTAssertEqual(style["radius"] as? Double, Double(ShellLayout.popoverRadius))
        XCTAssertEqual(style["dot"] as? Double, 6)
        XCTAssertEqual(style["quoteLineHeight"] as? Double, 1.45)
        XCTAssertTrue((style["highlightActive"] as? String)?.hasSuffix(",0.38)") == true)
        for key in ["elev", "hairline", "ink", "ink2", "ink3", "accent", "elevFill", "quoteRule", "shadow"] {
            XCTAssertTrue((style[key] as? String)?.hasPrefix("rgba(") == true, key)
        }
        // The page scheme decides the card: a dark page gets the dark `elev`.
        let dark = WKWebEngine.annotationStyle(Palette(mode: .light, space: .graphite).page(dark: true))
        XCTAssertEqual(dark["elev"] as? String, WKWebEngine.cssColor(Palette(mode: .dark, space: .graphite).elev))
    }

    func testSelectionBarHasNoBrandNameAndNoYellowHighlight() {
        let script = WKWebEngine.annotateScript
        XCTAssertFalse(script.contains("Save to Graphene"))
        XCTAssertFalse(script.contains("rgba(180,121,79"), "the old yellow highlight is gone")
        XCTAssertFalse(script.contains("surroundContents"))
        for label in ["\"Save\"", "\"Note\"", "\"Ask\"", "\"⌘D\"", "\"Save note\"", "\"Edit\"", "\"Open in Vault\""] {
            XCTAssertTrue(script.contains(label), label)
        }
    }

    // MARK: Vault rows

    func testVaultRowProvenanceFormatting() {
        let research = SpaceInfo(id: UUID(), name: "Research", color: .graphite)
        let saved = note("A passage", title: "Graphene - Wikipedia", space: research.id, hoursAgo: 2)
        let provenance = VaultList.provenance(saved, spaces: [research], now: now, locale: english)
        XCTAssertEqual(provenance.title, "Graphene - Wikipedia")
        XCTAssertEqual(provenance.space, "Research")
        XCTAssertEqual(provenance.line, "Graphene - Wikipedia · Research · 2 hours ago")

        // No title: the host without "www."; an unknown space is left out.
        let untitled = note("x", url: "https://www.example.org/p", title: " ", space: UUID(), hoursAgo: 26)
        XCTAssertEqual(VaultList.provenance(untitled, spaces: [research], now: now, locale: english).line, "example.org · yesterday")
        // Neither title nor address.
        let bare = note("x", url: "", title: "", hoursAgo: 0)
        XCTAssertEqual(VaultList.provenance(bare, spaces: [], now: now, locale: english).title, "Saved note")
    }

    func testVaultListOrderAndFilter() {
        let old = note("Old quote", hoursAgo: 5), new = note("New quote", hoursAgo: 1, note: "Thought")
        XCTAssertEqual(VaultList.sorted([old, new]).map(\.id), [new.id, old.id], "newest first")
        XCTAssertTrue(VaultList.matches(new, filter: "thought"))
        XCTAssertTrue(VaultList.matches(new, filter: "  "))
        XCTAssertTrue(VaultList.matches(new, filter: "example.com"))
        XCTAssertFalse(VaultList.matches(new, filter: "missing"))
    }

    func testByPageGroupsNotesUnderTheirPage() {
        let a1 = note("First on A", url: "https://example.com/a?utm_source=mail", title: "A, older title", hoursAgo: 3)
        let b = note("On B", url: "https://example.com/b", title: "B", hoursAgo: 2)
        let a2 = note("Second on A", url: "https://example.com/a", title: "A", hoursAgo: 1)
        let loose = note("Manual", url: "", title: "", hoursAgo: 4)
        let groups = VaultList.byPage([a1, b, a2, loose])
        XCTAssertEqual(groups.map(\.title), ["A", "B", "Saved note"], "groups ordered by their newest note, titled by it")
        XCTAssertEqual(groups[0].notes.map(\.id), [a2.id, a1.id], "one page despite tracking parameters, newest first")
        XCTAssertEqual(groups[1].notes.map(\.id), [b.id])
        XCTAssertEqual(groups[2].notes.map(\.id), [loose.id])
        XCTAssertEqual(Set(groups.map(\.id)).count, 3)
        XCTAssertTrue(VaultList.byPage([]).isEmpty)
    }

    func testByPageConnectorUsesTheSidebarGeometry() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 80)
        let middle = VaultConnector(tickY: VaultList.tickY, last: false).path(in: rect).boundingRect
        XCTAssertEqual(middle.minX, ShellLayout.threadLineInset)
        XCTAssertEqual(middle.maxX, ShellLayout.threadLineInset + ShellLayout.threadTick, "the tick ends at the note's leading edge")
        XCTAssertEqual(ShellLayout.threadLineInset + ShellLayout.threadTick, ShellLayout.threadIndent + ShellLayout.rowInsetLeading)
        XCTAssertEqual(middle.height, rect.height, "a middle note's vertical runs on to the next")
        let last = VaultConnector(tickY: VaultList.tickY, last: true).path(in: rect).boundingRect
        XCTAssertEqual(last.maxY, VaultList.tickY + ShellLayout.hairline / 2, accuracy: 0.001, "the last note's vertical stops at its tick")
    }

    // MARK: note ↔ mark

    func testNoteMarkIDMapping() throws {
        let saved = note("  The quoted sentence.  ")
        XCTAssertEqual(saved.markID, "note:\(saved.id)")
        XCTAssertEqual(saved.markID, NoteDrag.reference(saved.id))
        XCTAssertEqual(Annotation.noteID(markID: saved.markID), saved.id)
        XCTAssertNil(Annotation.noteID(markID: AppState.sourceHighlightID))
        XCTAssertNil(Annotation.noteID(markID: "note:not-a-uuid"))
        XCTAssertNil(Annotation.noteID(markID: "c1"))
        XCTAssertEqual(saved.passage, CitedPassage(id: saved.markID, text: saved.text))
        XCTAssertNil(saved.passage?.index, "a saved mark carries no citation index")
        XCTAssertNil(note("  \n ").passage, "a page saved without a quote has no mark")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("graphene-g7-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = Vault(file: directory.appendingPathComponent("annotations.json"), directory: directory)
        let first = try XCTUnwrap(vault.add(text: "First quote", note: "", url: URL(string: "https://example.com/a?utm_source=x"), title: "A", context: ""))
        let second = try XCTUnwrap(vault.add(text: "Second quote", note: "Mine", url: URL(string: "https://example.com/a"), title: "A", context: ""))
        vault.add(text: "", note: "Page only", url: URL(string: "https://example.com/a"), title: "A", context: "")
        vault.add(text: "Elsewhere", note: "", url: URL(string: "https://example.com/b"), title: "B", context: "")
        let marked = vault.markedNotes(forURL: try XCTUnwrap(URL(string: "https://example.com/a")))
        XCTAssertEqual(marked.map(\.id), [second.id, first.id])
        XCTAssertEqual(marked.compactMap(\.passage).map(\.id), [second.markID, first.markID])
    }

    // MARK: placement

    private func layout() throws -> JSValue {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("var window = {};")
        context.evaluateScript(WKWebEngine.annotateScript)
        return try XCTUnwrap(context.objectForKeyedSubscript("window")?.objectForKeyedSubscript("__grapheneAnnotateLayout"))
    }
    private func place(_ layout: JSValue, _ kind: String, sel: [String: Double], size: [String: Double], view: [String: Double] = ["width": 1000, "height": 700]) -> (left: Double, top: Double, placement: String) {
        let result = layout.invokeMethod(kind, withArguments: [sel, size, view, 8])
        return (result?.objectForKeyedSubscript("left")?.toDouble() ?? .nan, result?.objectForKeyedSubscript("top")?.toDouble() ?? .nan,
                result?.objectForKeyedSubscript("placement")?.toString() ?? "")
    }

    func testSelectionBarPlacementAboveOrBelow() throws {
        let layout = try layout()
        let bar = ["width": 180.0, "height": 36.0]
        // Room above: 8pt above the selection, centred on it.
        let above = place(layout, "bar", sel: ["left": 400, "top": 300, "right": 600, "bottom": 320], size: bar)
        XCTAssertEqual(above.placement, "above")
        XCTAssertEqual(above.top, 300 - 8 - 36)
        XCTAssertEqual(above.left, 500 - 90)
        // No room above (selection near the viewport top): 8pt below it.
        let below = place(layout, "bar", sel: ["left": 400, "top": 20, "right": 600, "bottom": 40], size: bar)
        XCTAssertEqual(below.placement, "below")
        XCTAssertEqual(below.top, 40 + 8)
        // Exactly enough room still goes above.
        XCTAssertEqual(place(layout, "bar", sel: ["left": 0, "top": 52, "right": 100, "bottom": 70], size: bar).placement, "above")
        // Clamped inside the viewport horizontally.
        XCTAssertEqual(place(layout, "bar", sel: ["left": 0, "top": 300, "right": 20, "bottom": 320], size: bar).left, 8)
        XCTAssertEqual(place(layout, "bar", sel: ["left": 980, "top": 300, "right": 1000, "bottom": 320], size: bar).left, 1000 - 180 - 8)
    }

    func testNoteEditorNeverCoversTheSelection() throws {
        let layout = try layout()
        let card = ["width": 320.0, "height": 130.0]
        func covers(_ p: (left: Double, top: Double, placement: String), _ sel: [String: Double]) -> Bool {
            p.left < sel["right"]! && p.left + 320 > sel["left"]! && p.top < sel["bottom"]! && p.top + 130 > sel["top"]!
        }
        let short = ["left": 100.0, "top": 300.0, "right": 300.0, "bottom": 320.0]
        let right = place(layout, "editor", sel: short, size: card)
        XCTAssertEqual(right.placement, "right"); XCTAssertEqual(right.left, 308); XCTAssertFalse(covers(right, short))
        let nearRight = ["left": 600.0, "top": 300.0, "right": 800.0, "bottom": 320.0]
        let left = place(layout, "editor", sel: nearRight, size: card)
        XCTAssertEqual(left.placement, "left"); XCTAssertFalse(covers(left, nearRight))
        let wide = ["left": 40.0, "top": 200.0, "right": 960.0, "bottom": 280.0]
        let below = place(layout, "editor", sel: wide, size: card)
        XCTAssertEqual(below.placement, "below"); XCTAssertEqual(below.top, 288); XCTAssertFalse(covers(below, wide))
        let wideLow = ["left": 40.0, "top": 500.0, "right": 960.0, "bottom": 620.0]
        let above = place(layout, "editor", sel: wideLow, size: card)
        XCTAssertEqual(above.placement, "above"); XCTAssertFalse(covers(above, wideLow))
        let huge = ["left": 40.0, "top": 100.0, "right": 960.0, "bottom": 650.0]
        let fallback = place(layout, "editor", sel: huge, size: card)
        XCTAssertEqual(fallback.placement, "below"); XCTAssertFalse(covers(fallback, huge), "with no room it opens below and the page scrolls")
    }

    // MARK: live page

    /// A saved note's quote is marked after load as a note-kind mark in the citation style, and
    /// clearing citations leaves it.
    func testSavedNoteIsMarkedAfterLoad() async throws {
        let engine = WKWebEngine(configuration: WKWebViewConfiguration())
        let saved = note("tensile strength of 130 GPa", url: "https://example.com/graphene")
        var asked: [URL] = []
        engine.savedNotes = { url in asked.append(url); return [saved] }
        engine.webView.loadHTMLString("<html><body><p>Graphene has a <b>tensile strength</b> of 130 GPa.</p><p>Second paragraph.</p></body></html>",
                                      baseURL: URL(string: "https://example.com/graphene"))
        var count = 0
        for _ in 0..<100 {
            count = await engine.evaluateJavaScript("document.querySelectorAll('mark[data-graphene-kind=\"note\"]').length") as? Int ?? 0
            if count > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(count, 2, "the quote spans the <b> and the text after it")
        XCTAssertEqual(asked.first?.absoluteString, "https://example.com/graphene")
        let ids = await engine.evaluateJavaScript("[...document.querySelectorAll('mark[data-graphene-kind=\"note\"]')].map(m => m.getAttribute('data-graphene-cite')).join(',')") as? String
        XCTAssertEqual(ids, "\(saved.markID),\(saved.markID)")
        let text = await engine.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertEqual(text?.contains("Graphene has a tensile strength of 130 GPa."), true, "marks never change the text")
        let style = await engine.evaluateJavaScript("document.getElementById('graphene-cite-style') !== null") as? Bool
        XCTAssertEqual(style, true, "saved marks use the citation mark style")

        // A citation beside it comes and goes; the saved mark stays.
        let found = await engine.highlight(passages: [CitedPassage(id: "c1", text: "Second paragraph", index: 1)])
        XCTAssertEqual(found, ["c1"])
        await engine.clearHighlights()
        let citations = await engine.evaluateJavaScript("document.querySelectorAll('mark[data-graphene-cite=\"c1\"]').length") as? Int
        let notes = await engine.evaluateJavaScript("document.querySelectorAll('mark[data-graphene-kind=\"note\"]').length") as? Int
        XCTAssertEqual(citations, 0)
        XCTAssertEqual(notes, 2)
    }

    /// With annotate.js injected: the page's notes and tokens reach it, hovering a saved mark
    /// raises it and shows the margin dot, the dot opens the note card, and a note dropped from
    /// the list loses its mark.
    func testMarginDotAndNoteCardInALivePage() async throws {
        let engine = WKWebEngine()
        let saved = note("tensile strength of 130 GPa", url: "https://example.com/graphene", note: "Check the units")
        var notes = [saved]
        engine.savedNotes = { _ in notes }
        engine.webView.loadHTMLString("<html><body style='margin:40px'><p>Graphene has a tensile strength of 130 GPa.</p></body></html>",
                                      baseURL: URL(string: "https://example.com/graphene"))
        var count = 0
        for _ in 0..<100 {
            count = await engine.evaluateJavaScript("document.querySelectorAll('mark[data-graphene-kind=\"note\"]').length") as? Int ?? 0
            if count > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(count, 1)
        let probe = """
        (() => {
          const root = document.querySelector('[data-graphene]').shadowRoot;
          const mark = document.querySelector('mark[data-graphene-kind="note"]');
          mark.dispatchEvent(new MouseEvent('mouseover', {bubbles: true}));
          const dot = root.querySelector('[aria-label="Show note"]');
          const raised = mark.style.backgroundColor !== '';
          const dotShown = getComputedStyle(dot).display === 'block' && dot.getBoundingClientRect().right <= mark.getBoundingClientRect().left;
          dot.click();
          const card = [...root.children].find(e => e.textContent.includes('Open in Vault'));
          return JSON.stringify({raised, dotShown, card: getComputedStyle(card).display, text: card.textContent,
                                 width: card.offsetWidth, toolbar: root.querySelector('[role="toolbar"]').style.height});
        })()
        """
        let value = await engine.evaluateJavaScript(probe)
        let json = try XCTUnwrap(value as? String)
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(state["raised"] as? Bool, true, "hover raises the mark")
        XCTAssertEqual(state["dotShown"] as? Bool, true, "the dot sits in the margin left of the line")
        XCTAssertEqual(state["card"] as? String, "flex")
        XCTAssertEqual(state["width"] as? Double, Double(ShellLayout.annotationCardWidth))
        XCTAssertEqual(state["toolbar"] as? String, "36px", "the bar takes annotationBarHeight from Swift")
        XCTAssertTrue((state["text"] as? String)?.contains("Check the units") == true)
        XCTAssertTrue((state["text"] as? String)?.contains("tensile strength of 130 GPa") == true)

        notes = []
        await engine.markSavedNotes()
        let left = await engine.evaluateJavaScript("document.querySelectorAll('mark').length") as? Int
        XCTAssertEqual(left, 0, "a deleted note's mark goes")
    }
}
