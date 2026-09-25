import XCTest
@testable import Graphene

/// D6 G4: Ask citations that point at the page.
@MainActor
final class CitationTests: XCTestCase {
    private func source(_ title: String, _ text: String, id: UUID = UUID(), kind: String = "Tab", url: String = "https://example.com/page") -> KnowledgeSource {
        KnowledgeSource(id: id, title: title, url: url, text: text, kind: kind)
    }

    // MARK: index assignment

    func testIndicesAreAssignedPerAnswerInOrderOfFirstMention() {
        let sources = [source("A", "Alpha text."), source("B", "Beta text.")]
        let message = UUID()
        let citations = ChatCitation.assign(answer: "Beta says so [2]. Alpha agrees [1]. Beta again [2]. Nothing [9].", sources: sources, messageID: message, passages: false)
        XCTAssertEqual(citations.map(\.index), [1, 2])
        XCTAssertEqual(citations.map(\.sourceNumber), [2, 1])
        XCTAssertEqual(citations.map(\.sourceID), [sources[1].id, sources[0].id])
        XCTAssertEqual(citations.map(\.citationID), [ChatCitation.citationID(messageID: message, index: 1), ChatCitation.citationID(messageID: message, index: 2)])
        // Stable: the same answer yields the same ids; another answer restarts at 1.
        XCTAssertEqual(ChatCitation.assign(answer: "Beta says so [2]. Alpha agrees [1].", sources: sources, messageID: message, passages: false).map(\.citationID), citations.map(\.citationID))
        let other = ChatCitation.assign(answer: "Alpha [1].", sources: sources, messageID: UUID(), passages: false)
        XCTAssertEqual(other.map(\.index), [1])
        XCTAssertNotEqual(other.first?.citationID, citations.first?.citationID)
        XCTAssertTrue(ChatCitation.assign(answer: "General knowledge only.", sources: sources, messageID: message).isEmpty)
    }

    func testCitationsPersistWithHistoryAndOldFilesStillDecode() throws {
        var chat = ChatSession(spaceID: UUID(), profileID: UUID())
        let answer = ChatMessage(role: .assistant, content: "Strong [1].", sources: [source("Page", "It is strong and light.")])
        chat.messages = [answer]
        chat.citations = [answer.id.uuidString: [ChatCitation(citationID: "cite-x-1", index: 1, sourceNumber: 1, sourceID: answer.sources![0].id, passage: "It is strong and light.")]]
        let decoded = try JSONDecoder().decode(ChatSession.self, from: JSONEncoder().encode(chat))
        XCTAssertEqual(decoded.citations(for: answer).first?.passage, "It is strong and light.")
        // A file written before G4 has no citations key: decode it and derive indices without passages.
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(chat)) as? [String: Any])
        legacy["citations"] = nil
        let old = try JSONDecoder().decode(ChatSession.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.citations)
        XCTAssertEqual(old.citations(for: answer).map(\.index), [1])
        XCTAssertNil(old.citations(for: answer).first?.passage)
    }

    // MARK: passages

    func testPassageIsAnExactExcerptNeverTheModelsParaphrase() {
        let page = source("Graphene", "Graphene is an allotrope of carbon. Its tensile strength is 130 GPa, the highest ever measured. It conducts heat well.")
        let passage = PageContext.passage(for: "Graphene has a tensile strength of about 130 GPa [1].", in: page)
        XCTAssertEqual(passage, "Its tensile strength is 130 GPa, the highest ever measured.")
        XCTAssertTrue(page.text.contains(passage!))
        // An echoed quote that appears verbatim wins; one that does not is never used.
        XCTAssertEqual(PageContext.passage(for: "The article says “the highest ever measured” [1].", in: page), "the highest ever measured")
        XCTAssertNotEqual(PageContext.passage(for: "It says “the strongest thing in the universe” [1].", in: page), "the strongest thing in the universe")
        XCTAssertNil(PageContext.passage(for: "Bananas are yellow [1].", in: page))
        // A marker set after the full stop cites the sentence before it.
        let citations = ChatCitation.assign(answer: "It conducts heat well. [1]", sources: [page], messageID: UUID())
        XCTAssertEqual(citations.first?.passage, "It conducts heat well.")
        let long = String(repeating: "word ", count: 200) + "tensile strength"
        XCTAssertLessThanOrEqual(PageContext.clip(long).count, PageContext.passageLimit)
        XCTAssertTrue(long.hasPrefix(PageContext.clip(long)))
    }

    // MARK: fallback for an answer without markers

    private let wiki = "Graphene is an allotrope of carbon consisting of a single layer of atoms arranged in a honeycomb lattice. "
        + "Graphene is the strongest material ever tested, with an intrinsic tensile strength of 130 GPa and a Young's modulus of 1 TPa. "
        + "In 1947, Philip Wallace first theorized the electronic band structure of graphite. "
        + "Graphene conducts heat and electricity very efficiently along its plane."

    func testUncitedSentencesAreMatchedToExactSourceSentences() throws {
        let page = source("Graphene - Wikipedia", wiki)
        let message = UUID()
        let answer = "Graphene has a tensile strength of 130 GPa. It was first theorized in 1947 by Philip Wallace."
        let citations = ChatCitation.assign(answer: answer, sources: [page], messageID: message)
        // One citation per source per answer, numbered from 1, its passage the first matched sentence verbatim.
        XCTAssertEqual(citations.count, 1)
        let citation = try XCTUnwrap(citations.first)
        XCTAssertEqual(citation.index, 1)
        XCTAssertEqual(citation.sourceNumber, 1)
        XCTAssertEqual(citation.sourceID, page.id)
        XCTAssertEqual(citation.citationID, ChatCitation.citationID(messageID: message, index: 1))
        XCTAssertEqual(citation.passage, "Graphene is the strongest material ever tested, with an intrinsic tensile strength of 130 GPa and a Young's modulus of 1 TPa.")
        XCTAssertTrue(page.text.contains(try XCTUnwrap(citation.passage)))
        XCTAssertEqual(citation.anchors, ["Graphene has a tensile strength of 130 GPa.", "It was first theorized in 1947 by Philip Wallace."])
        // The inline chip is drawn after each matched sentence.
        let shown = ChatMarkdown.anchored(answer, citations: citations)
        XCTAssertEqual(ChatMarkdown.segments(shown), [.text("Graphene has a tensile strength of 130 GPa. "), .anchored(1), .text(" It was first theorized in 1947 by Philip Wallace. "), .anchored(1)])
        XCTAssertTrue(ChatMarkdown.hasMarkers(shown))
        // Streaming and older chats derive no fallback: only a finished answer is matched.
        XCTAssertTrue(ChatCitation.assign(answer: answer, sources: [page], messageID: message, passages: false).isEmpty)

        // Two sources, numbered in order of first use.
        let other = source("Swift", "Swift is a general-purpose programming language developed by Apple. Swift compiles to native code with LLVM.")
        let mixed = ChatCitation.assign(answer: "Swift compiles to native code using LLVM. Graphene has a tensile strength of 130 GPa.", sources: [page, other], messageID: message)
        XCTAssertEqual(mixed.map(\.sourceNumber), [2, 1])
        XCTAssertEqual(mixed.map(\.index), [1, 2])
        XCTAssertEqual(mixed.first?.passage, "Swift compiles to native code with LLVM.")
    }

    func testAParaphraseBelowTheThresholdIsNotCited() {
        let page = source("Graphene - Wikipedia", wiki)
        // Shares only "graphene" and "carbon" (2 of 6 content words): below 60% and below 3.
        XCTAssertTrue(ChatCitation.assign(answer: "Graphene is a remarkable carbon wonder material for batteries.", sources: [page], messageID: UUID()).isEmpty)
        // Three shared words, but only 3 of 7: below 60%.
        XCTAssertNil(ChatCitation.fallbackMatch("Graphene tensile strength matters for aircraft wings today.", sources: [page]))
        // Too few content words to match at all.
        XCTAssertNil(ChatCitation.fallbackMatch("Graphene is strong.", sources: [page]))
        XCTAssertEqual(ChatCitation.fallbackCoverage, 0.6)
        XCTAssertEqual(ChatCitation.fallbackMinimumShared, 3)
        XCTAssertTrue(ChatCitation.assign(answer: "Peru is a country in South America.", sources: [page], messageID: UUID()).isEmpty)
    }

    func testExplicitMarkersWinOverTheFallback() throws {
        let page = source("Graphene - Wikipedia", wiki)
        // The marked sentence keeps the model's citation and its passage; it is never re-matched.
        let answer = "Graphene conducts heat and electricity very efficiently [1]. Graphene has a tensile strength of 130 GPa."
        let citations = ChatCitation.assign(answer: answer, sources: [page], messageID: UUID())
        XCTAssertEqual(citations.count, 1, "the uncited sentence joins the source's existing citation")
        let citation = try XCTUnwrap(citations.first)
        XCTAssertEqual(citation.passage, "Graphene conducts heat and electricity very efficiently along its plane.")
        XCTAssertEqual(citation.anchors, ["Graphene has a tensile strength of 130 GPa."])
        // A bare marker after the full stop cites the sentence before it, so that sentence is not a fallback.
        let trailing = ChatCitation.assign(answer: "Graphene has a tensile strength of 130 GPa. [1]", sources: [page], messageID: UUID())
        XCTAssertEqual(trailing.count, 1)
        XCTAssertNil(trailing.first?.anchors)
        // An explicit citation to another source keeps its number first.
        let other = source("Notes", "Carbon allotropes include diamond and graphite.")
        let both = ChatCitation.assign(answer: "Carbon has several allotropes [2]. Graphene has a tensile strength of 130 GPa.", sources: [page, other], messageID: UUID())
        XCTAssertEqual(both.map(\.sourceNumber), [2, 1])
        XCTAssertNil(both[0].anchors)
        XCTAssertEqual(both[1].anchors, ["Graphene has a tensile strength of 130 GPa."])
    }

    func testBudgetNoticesArePlain() {
        let page = KnowledgeSource(id: UUID(), title: "Graphene - Wikipedia", url: "https://en.wikipedia.org/wiki/Graphene", text: String(repeating: "Graphene is strong. ", count: 900), kind: "Tab")
        XCTAssertEqual(PageContext.budget([page], limit: 6000).notices, ["Page text trimmed to \(6000.formatted()) characters"])
        let empty = KnowledgeSource(id: UUID(), title: "Blank", url: "https://example.com", text: " ", kind: "Tab")
        XCTAssertEqual(PageContext.budget([page, empty], limit: 6000).notices, ["Couldn't read Blank", "Graphene - Wikipedia trimmed to \(6000.formatted()) characters"])
    }

    func testPassagesComeFromTheRequestBuildersSourceBudget() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root), store = ChatStore(root: root), controller = ChatController(), provider = CitationProvider()
        let url = URL(string: "https://example.com/graphene")!
        let node = app.graph.recordVisit(url: url, title: "Graphene", spaceID: app.activeSpaceID, parentNodeID: nil, query: nil)
        // The on-device budget keeps the first 6000 characters: the second strength sentence is cut.
        let kept = "Its tensile strength is 130 GPa in lab tests."
        let text = kept + " " + String(repeating: "Filler about carbon lattices. ", count: 300) + "Its tensile strength is 999 GPa in the trimmed tail."
        controller.send("How strong is it?", sources: [source("Graphene", text, id: node, kind: "Visited page", url: url.absoluteString)], app: app, store: store, providerOverride: provider)
        await Task.yield()
        provider.continuation.yield("The tensile strength is 130 GPa [1].")
        provider.continuation.finish()
        for _ in 0..<40 { await Task.yield() }
        let chat = try XCTUnwrap(controller.chat)
        let answer = try XCTUnwrap(chat.messages.last)
        XCTAssertEqual(controller.arrived, answer.id)
        let citation = try XCTUnwrap(chat.citations?[answer.id.uuidString]?.first)
        XCTAssertEqual(citation.passage, kept)
        XCTAssertEqual(citation.sourceID, node)
        XCTAssertTrue(try XCTUnwrap(answer.sources?.first?.text).contains(kept))
        XCTAssertFalse(try XCTUnwrap(answer.sources?.first?.text).contains("999 GPa"), "the passage pool is the budgeted text the model saw")
        XCTAssertEqual(ChatStore(root: root).chats.first?.citations?[answer.id.uuidString]?.first?.passage, kept, "citations persist with chat history")
    }

    // MARK: grounding

    func testGroundingLineDotAndPlaceholderForEachState() {
        let active = UUID()
        let page = source("Page", "x", id: active)
        let other = source("Other", "y")
        let note = source("Note", "z", kind: "Note"), saved = source("Saved", "w", kind: "Saved note")
        let visited = source("History", "v", kind: "Visited page")
        let cases: [([KnowledgeSource], ChatGrounding, String, String, Bool)] = [
            ([], .nothing, "Nothing yet", "Ask a question…", false),
            ([page], .page, "This page", "Ask about this page…", true),
            ([page, other, source("Third", "t")], .tabs(3), "3 tabs", "Ask across 3 tabs…", true),
            ([other], .tabs(1), "1 tab", "Ask about this tab…", true),
            ([note, saved], .notes, "This space's notes", "Ask your notes…", true),
            ([page, visited], .sources(2), "2 sources", "Ask across 2 sources…", true),
        ]
        for (sources, state, line, placeholder, dot) in cases {
            let grounding = ChatGrounding(sources: sources, activeTabID: active)
            XCTAssertEqual(grounding, state)
            XCTAssertEqual(grounding.line, line)
            XCTAssertEqual(grounding.placeholder, placeholder)
            XCTAssertEqual(grounding.grounded, dot, "accent dot only when local sources are attached")
        }
        XCTAssertEqual(ChatGrounding.emptyState, "Attach a page with @ or ask about this one.")
        XCTAssertEqual(ChatGrounding.noSources, "No sources; this is the model's general knowledge.")
    }

    // MARK: page link

    func testOnlyFoundPassagesOfThePageGetLinkedChips() async {
        let tab = UUID(), otherTab = UUID(), message = UUID()
        let page = source("Page", "Alpha is first. Beta is second.", id: tab)
        let elsewhere = source("Other tab", "Gamma is third.", id: otherTab, url: "https://other.example")
        let history = source("History", "Delta is fourth.", kind: "Visited page", url: "https://history.example")
        let sources = [page, elsewhere, history]
        let citations = ChatCitation.assign(answer: "Alpha is first [1]. Beta is second [1]... Gamma is third [2]. Delta is fourth [3].", sources: sources, messageID: message)
        XCTAssertEqual(citations.count, 3)
        let eligible = CitationLinker.eligible(citations, sources: sources, tabID: tab, url: URL(string: page.url))
        XCTAssertEqual(eligible.map(\.id), [citations[0].citationID], "only passages whose source is the page are offered to it")
        XCTAssertEqual(eligible.first?.index, 1)

        let linker = CitationLinker(), recorder = PageRecorder(found: [])
        let linked = await linker.link(messageID: message, citations: citations, sources: sources, tabID: tab, url: URL(string: page.url), page: recorder.page)
        XCTAssertTrue(linked.isEmpty, "a passage the page did not find is not linked")
        XCTAssertEqual(recorder.highlighted.first?.map(\.text), [citations[0].passage!])

        let found = PageRecorder(found: [citations[0].citationID, "stray"])
        await linker.link(messageID: message, citations: citations, sources: sources, tabID: tab, url: URL(string: page.url), page: found.page)
        XCTAssertEqual(linker.linkedIDs, [citations[0].citationID])
        XCTAssertEqual(recorder.clears, 1, "linking a new answer clears the previous marks first")
        XCTAssertEqual(CitationLinker.linked(eligible, found: ["stray"]), [])

        let open: Set<UUID> = [tab, otherTab]
        func link(_ c: ChatCitation, _ s: KnowledgeSource) -> CitationChipLink {
            CitationLinker.chipLink(c, source: s, linkedIDs: linker.linkedIDs, linkedTabID: linker.tabID, activeTab: (tab, URL(string: page.url)), openTabIDs: open)
        }
        XCTAssertEqual(link(citations[0], page), .page)
        XCTAssertEqual(link(citations[1], elsewhere), .tab(otherTab))
        XCTAssertEqual(link(citations[2], history), .source)
        XCTAssertEqual(CitationLinker.chipLink(citations[0], source: page, linkedIDs: [], linkedTabID: nil, activeTab: (tab, nil), openTabIDs: open), .unlinkedPage)
        XCTAssertEqual(CitationLinker.chipLink(citations[0], source: page, linkedIDs: linker.linkedIDs, linkedTabID: tab, activeTab: (otherTab, nil), openTabIDs: open), .tab(tab), "a linked tab that is no longer active switches back first")

        // Chip hover raises the mark; click scrolls; a mark hover raises the chip.
        linker.hoverChip(citations[0].citationID)
        linker.hoverChip("not-linked")
        await linker.focus(citations[0].citationID)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(found.active.compactMap { $0 }, [citations[0].citationID, citations[0].citationID])
        XCTAssertEqual(found.scrolled, [citations[0].citationID])
        linker.markHovered(nil, tabID: tab)
        XCTAssertNil(linker.activeID)
        linker.markHovered(citations[0].citationID, tabID: otherTab)
        XCTAssertNil(linker.activeID, "marks in another tab are ignored")
        linker.markHovered(citations[0].citationID, tabID: tab)
        XCTAssertEqual(linker.activeID, citations[0].citationID)
    }

    func testHighlightsClearOnCloseRegenerateAndNavigate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        let tab = Tab(engine: WKWebEngine(privateMode: false))
        let page = source("Page", "Alpha is the first letter.", id: tab.id)
        let citations = ChatCitation.assign(answer: "Alpha is the first letter [1].", sources: [page], messageID: UUID())
        func linked() async -> PageRecorder {
            let recorder = PageRecorder(found: citations.map(\.citationID))
            await app.citations.link(messageID: UUID(), citations: citations, sources: [page], tabID: tab.id, url: nil, page: recorder.page)
            XCTAssertFalse(app.citations.linkedIDs.isEmpty)
            return recorder
        }
        func settle() async { for _ in 0..<10 { await Task.yield() } }

        // Panel closes.
        app.knowledgeSearchPresented = true
        var recorder = await linked()
        app.knowledgeSearchPresented = false
        await settle()
        XCTAssertEqual(recorder.clears, 1)
        XCTAssertTrue(app.citations.linkedIDs.isEmpty)
        XCTAssertNil(app.citations.tabID)

        // Regenerate.
        recorder = await linked()
        let store = ChatStore(root: root), controller = ChatController(), provider = CitationProvider()
        controller.send("", sources: [], app: app, store: store, regenerate: true, providerOverride: provider)
        await settle()
        XCTAssertEqual(recorder.clears, 1)
        XCTAssertTrue(app.citations.linkedIDs.isEmpty)
        controller.stop()

        // The linked tab navigates; another tab navigating leaves the link alone.
        recorder = await linked()
        let other = Tab(engine: WKWebEngine(privateMode: false))
        app.tab(other, didNavigateTo: URL(string: "https://other.example")!, title: nil)
        await settle()
        XCTAssertEqual(recorder.clears, 0)
        app.tab(tab, didNavigateTo: URL(string: "https://example.com/next")!, title: nil)
        await settle()
        XCTAssertEqual(recorder.clears, 1)
        XCTAssertTrue(app.citations.linkedIDs.isEmpty)
    }

    // MARK: answer rendering

    func testMarkersSplitIntoChipsAndQuotesUseTheSerifBlock() {
        XCTAssertEqual(ChatMarkdown.segments("Strong [1] and light [2](https://x.example)."), [.text("Strong "), .marker(1), .text(" and light "), .marker(2), .text(".")])
        XCTAssertEqual(ChatMarkdown.words("**Very** strong  indeed").map { String($0.characters) }, ["Very ", "strong  ", "indeed"])
        let page = source("Page", "The  Tensile strength is 130 GPa.")
        XCTAssertEqual(ChatMarkdown.quote("> Quoted line\n> second", sources: []), "Quoted line\nsecond")
        XCTAssertEqual(ChatMarkdown.quote("“the tensile strength is 130 GPa.”", sources: [page]), "the tensile strength is 130 GPa.")
        XCTAssertNil(ChatMarkdown.quote("“Invented words.”", sources: [page]), "only text the page holds is set as a quote")
        XCTAssertNil(ChatMarkdown.quote("Plain prose.", sources: [page]))
    }
}

@MainActor
private final class PageRecorder {
    var highlighted: [[CitedPassage]] = []
    var active: [String?] = []
    var scrolled: [String] = []
    var clears = 0
    let found: [String]
    init(found: [String]) { self.found = found }
    var page: CitationPage {
        CitationPage(highlight: { self.highlighted.append($0); return self.found }, setActive: { self.active.append($0) },
                     scroll: { self.scrolled.append($0) }, clear: { self.clears += 1 })
    }
}

private final class CitationProvider: LanguageModelProvider {
    let output: AsyncThrowingStream<String, Error>
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    init() { let pair = AsyncThrowingStream<String, Error>.makeStream(); output = pair.stream; continuation = pair.continuation }
    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> { output }
}
