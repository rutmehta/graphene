import XCTest
import WebKit
@testable import Graphene

/// The Ask citation path against the real Wikipedia page, end to end without the UI: load in a
/// `WKWebEngine`, capture as Ask does, trim to the on-device budget, assign the answer's
/// citations and mark them in the page. Opt-in (`GRAPHENE_LIVE_WEB=1`); needs the network.
@MainActor
final class LiveCitationTests: XCTestCase {
    static let url = URL(string: "https://en.wikipedia.org/wiki/Graphene")!
    /// The answer the on-device model gave in the D6 re-verification (identity-fixes-2 check 3).
    static let answer = """
    Source [1]: Graphene - Wikipedia
    Tensile strength: 130 GPa [1]
    First isolated: Andre Geim and Konstantin Novoselov in 2004. [1]
    """

    func testLiveWikipediaAnswerCitationsMarkThePage() async throws {
        guard ProcessInfo.processInfo.environment["GRAPHENE_LIVE_WEB"] == "1" else { throw XCTSkip("Opt-in live web test (GRAPHENE_LIVE_WEB=1)") }
        let engine = WKWebEngine()
        // A viewport, so marks have a box to measure (the Ask panel's scroll inset).
        engine.webView.frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        engine.load(Self.url)
        let deadline = Date().addingTimeInterval(45)
        try await Task.sleep(for: .milliseconds(500))
        while Date() < deadline, engine.isLoading || engine.currentURL == nil { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(engine.isLoading, "the page loaded")
        try await Task.sleep(for: .milliseconds(500))
        let tabID = UUID()
        let tabURL = try XCTUnwrap(engine.currentURL)
        print("LIVE url:", tabURL.absoluteString, "title:", engine.pageTitle ?? "nil")

        // The Ask capture (ChatView.attach) and the on-device budget (ChatController.send).
        let captured = await engine.captureSnapshotText()
        print("LIVE captured \(captured.count) characters; head:", String(captured.prefix(400)).debugDescription)
        XCTAssertFalse(captured.isEmpty, "Ask captured the page")
        let attached = KnowledgeSource(id: tabID, title: engine.pageTitle ?? "", url: tabURL.absoluteString, text: captured, kind: "Tab")
        let budget = PageContext.budget([attached], limit: 6000)
        print("LIVE notices:", budget.notices)
        // Each answer line on its own: the first is the prompt's source label and matches nothing.
        for range in PageContext.sentenceRanges(Self.answer) {
            let line = String(Self.answer[range])
            print("LIVE line:", line.debugDescription, "label:", ChatCitation.isLabel(line, source: budget.sources[0]), "passage:", PageContext.passage(for: line, in: budget.sources[0]).debugDescription)
        }

        // The finished answer's citations (ChatCitation.assign), then the linker's filter.
        let messageID = UUID()
        let citations = ChatCitation.assign(answer: Self.answer, sources: budget.sources, messageID: messageID)
        for citation in citations { print("LIVE citation \(citation.index) -> source \(citation.sourceNumber), passage:", citation.passage.debugDescription, "anchors:", citation.anchors ?? []) }
        XCTAssertFalse(citations.isEmpty)
        XCTAssertTrue(citations.allSatisfy { $0.passage != nil }, "every citation carries a passage")
        let eligible = CitationLinker.eligible(citations, sources: budget.sources, tabID: tabID, url: tabURL)
        print("LIVE eligible:", eligible.map(\.text))
        for passage in eligible { print("LIVE swift mirror matches captured text:", passage.matches(in: captured)) }

        // The page marks them (CitationLinker.link -> WKWebEngine.highlight -> cite.js).
        let linker = CitationLinker()
        let linked = await linker.link(messageID: messageID, citations: citations, sources: budget.sources, tabID: tabID, url: tabURL, page: .engine(engine))
        let marks = await engine.evaluateJavaScript("Array.from(document.querySelectorAll('mark[data-graphene-cite]')).map(m => m.textContent).join('|')") as? String
        print("LIVE linked:", linked.sorted(), "marks:", marks ?? "nil")
        XCTAssertFalse(linked.isEmpty, "the page reports the passages found")
        // G8: one passage per claim. The tensile strength is the infobox row alone; the
        // isolation claim is the 2004 sentence. The source label shares the first citation.
        XCTAssertEqual(citations.count, 2)
        let row = try XCTUnwrap(citations.first?.passage)
        XCTAssertTrue(row.contains("130 GPa") && row.contains("Tensile strength"), row)
        XCTAssertLessThanOrEqual(PageContext.words(row).count, PageContext.rowWordLimit, "the row, not the infobox")
        let sentence = try XCTUnwrap(citations.last?.passage)
        XCTAssertTrue(sentence.contains("2004") && sentence.contains("Geim"), sentence)
        XCTAssertEqual(ChatCitation.sourcesLine(citations).count, 1, "one sources-line entry for the page")
        XCTAssertEqual(linked, Set(citations.map(\.citationID)), "both passages are marked")
        // The floating panel over this 1000×800 viewport: 420pt wide, inset 16 from the right, top and bottom.
        let covered = CGRect(x: 1000 - 16 - ShellLayout.chatWidth, y: 16, width: ShellLayout.chatWidth, height: 768)
        for citation in citations {
            let rect = await engine.highlightRect(id: citation.citationID)
            XCTAssertNotNil(rect, "the mark has a box")
            let plan = rect.map { CitationLinker.reveal(mark: $0, viewport: CGSize(width: 1000, height: 800), covered: covered) }
            print("LIVE rect \(citation.index):", rect.debugDescription, "reveal:", plan.debugDescription)
        }
        await engine.clearHighlights()
    }
}
