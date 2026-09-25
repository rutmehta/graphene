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
        XCTAssertEqual(citations.map(\.citationID), [ChatCitation.citationID(messageID: message, ordinal: 1), ChatCitation.citationID(messageID: message, ordinal: 2)])
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
        // One citation per claim, each passage its own source sentence verbatim; one source, so both read 1.
        XCTAssertEqual(citations.count, 2)
        let citation = try XCTUnwrap(citations.first)
        XCTAssertEqual(citations.map(\.index), [1, 1])
        XCTAssertEqual(citations.map(\.sourceNumber), [1, 1])
        XCTAssertEqual(citation.sourceID, page.id)
        XCTAssertEqual(citation.citationID, ChatCitation.citationID(messageID: message, ordinal: 1))
        XCTAssertEqual(citation.passage, "Graphene is the strongest material ever tested, with an intrinsic tensile strength of 130 GPa and a Young's modulus of 1 TPa.")
        XCTAssertEqual(citations[1].passage, "In 1947, Philip Wallace first theorized the electronic band structure of graphite.")
        for c in citations { XCTAssertTrue(page.text.contains(try XCTUnwrap(c.passage))) }
        XCTAssertEqual(citation.anchors, ["Graphene has a tensile strength of 130 GPa."])
        XCTAssertEqual(citations[1].anchors, ["It was first theorized in 1947 by Philip Wallace."])
        XCTAssertEqual(ChatCitation.sourcesLine(citations).map { $0.map(\.index) }, [[1, 1]], "one sources-line entry for the one source")
        // The inline chip is drawn after each matched sentence.
        let shown = ChatMarkdown.anchored(answer, citations: citations)
        XCTAssertEqual(ChatMarkdown.segments(shown), [.text("Graphene has a tensile strength of 130 GPa. "), .anchored(1), .text(" It was first theorized in 1947 by Philip Wallace. "), .anchored(2)])
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
        XCTAssertEqual(citations.count, 2, "the uncited sentence finds another passage of the same source: its own citation")
        let citation = try XCTUnwrap(citations.first)
        XCTAssertEqual(citation.passage, "Graphene conducts heat and electricity very efficiently along its plane.")
        XCTAssertNil(citation.anchors)
        XCTAssertEqual(citation.markers, [0])
        XCTAssertEqual(citations[1].anchors, ["Graphene has a tensile strength of 130 GPa."])
        XCTAssertEqual(ChatCitation.sourcesLine(citations).count, 1)
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

    /// The on-device answer from the D6 re-verification: its first `[1]` sits on a restated source
    /// label that matches no sentence. The citation's passage comes from the lines that state claims.
    func testAMarkerOnASourceLabelStillGetsAPassage() throws {
        let page = source("Graphene - Wikipedia", wiki + " In 2004, the material was isolated and characterized by Andre Geim and Konstantin Novoselov at the University of Manchester.")
        let answer = "Source [1]: Graphene - Wikipedia\nTensile strength: 130 GPa [1]\nFirst isolated: Andre Geim and Konstantin Novoselov in 2004. [1]"
        XCTAssertTrue(ChatCitation.isLabel("Source [1]: Graphene - Wikipedia\n", source: page))
        XCTAssertFalse(ChatCitation.isLabel("Tensile strength: 130 GPa [1]", source: page))
        XCTAssertNil(PageContext.passage(for: "Source [1]: Graphene - Wikipedia", in: page), "the label alone matches nothing")
        let citations = ChatCitation.assign(answer: answer, sources: [page], messageID: UUID())
        // Each claim its own passage; the label's marker joins the source's first citation.
        XCTAssertEqual(citations.count, 2)
        let passage = try XCTUnwrap(citations.first?.passage)
        XCTAssertEqual(passage, "Graphene is the strongest material ever tested, with an intrinsic tensile strength of 130 GPa and a Young's modulus of 1 TPa.")
        XCTAssertTrue(page.text.contains(passage))
        XCTAssertEqual(citations[1].passage, "In 2004, the material was isolated and characterized by Andre Geim and Konstantin Novoselov at the University of Manchester.")
        XCTAssertEqual(citations.map(\.markers), [[0, 1], [2]])
        XCTAssertEqual(ChatCitation.sourcesLine(citations).map { $0.map(\.index) }, [[1, 1]])
        // Each marker becomes its own citation's chip.
        let shown = ChatMarkdown.anchored(answer, citations: citations)
        XCTAssertEqual(shown, "Source ⁅1⁆: Graphene - Wikipedia\nTensile strength: 130 GPa ⁅1⁆\nFirst isolated: Andre Geim and Konstantin Novoselov in 2004. ⁅2⁆")

        // Only the label carries a marker: the uncited claim that matches the source supplies the passage.
        let labelOnly = ChatCitation.assign(answer: "Source [1]: Graphene - Wikipedia\nGraphene was first isolated by Andre Geim and Konstantin Novoselov in 2004.",
                                            sources: [page], messageID: UUID())
        XCTAssertEqual(labelOnly.count, 1)
        XCTAssertEqual(labelOnly.first?.passage, "In 2004, the material was isolated and characterized by Andre Geim and Konstantin Novoselov at the University of Manchester.")
        XCTAssertEqual(labelOnly.first?.anchors, ["Graphene was first isolated by Andre Geim and Konstantin Novoselov in 2004."])
    }

    func testChipHelpSaysWhetherTheSourceIsThisPage() {
        XCTAssertEqual(CitationChipLink.unlinkedPage.help(title: "Graphene - Wikipedia"), "Passage not found on this page")
        XCTAssertEqual(CitationChipLink.tab(UUID()).help(title: "Swift Forums"), "Not on this page. Switch to Swift Forums")
        XCTAssertEqual(CitationChipLink.source.help(title: "Graphite"), "Not on this page. Open Graphite")
        XCTAssertEqual(CitationChipLink.source.help(title: "My note", note: true), "My note")
        XCTAssertEqual(CitationChipLink.page.help(title: "Graphene"), "Show in page")
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
        XCTAssertEqual(citations.count, 4, "two claims of the page with two passages are two citations")
        let eligible = CitationLinker.eligible(citations, sources: sources, tabID: tab, url: URL(string: page.url))
        XCTAssertEqual(eligible.map(\.id), [citations[0].citationID, citations[1].citationID], "only passages whose source is the page are offered to it")
        XCTAssertEqual(eligible.map(\.index), [1, 1], "both marks carry the source's number")
        XCTAssertNotEqual(eligible[0].id, eligible[1].id, "each passage keeps its own mark")

        let linker = CitationLinker(), recorder = PageRecorder(found: [])
        let linked = await linker.link(messageID: message, citations: citations, sources: sources, tabID: tab, url: URL(string: page.url), page: recorder.page)
        XCTAssertTrue(linked.isEmpty, "a passage the page did not find is not linked")
        XCTAssertEqual(recorder.highlighted.first?.map(\.text), ["Alpha is first.", "Beta is second."])

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
        XCTAssertEqual(link(citations[1], page), .unlinkedPage)
        XCTAssertEqual(link(citations[2], elsewhere), .tab(otherTab))
        XCTAssertEqual(link(citations[3], history), .source)
        XCTAssertEqual(CitationLinker.chipLink(citations[0], source: page, linkedIDs: [], linkedTabID: nil, activeTab: (tab, nil), openTabIDs: open), .unlinkedPage)
        XCTAssertEqual(CitationLinker.chipLink(citations[0], source: page, linkedIDs: linker.linkedIDs, linkedTabID: tab, activeTab: (otherTab, nil), openTabIDs: open), .tab(tab), "a linked tab that is no longer active switches back first")

        // Chip hover raises the mark and scrolls to it; click scrolls; a mark hover raises the chip.
        // Unmeasured (no window), both use the page's own centring scroll.
        linker.hoverChip(citations[0].citationID)
        linker.hoverChip("not-linked")
        for _ in 0..<10 { await Task.yield() }
        await linker.focus(citations[0].citationID)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(found.active.compactMap { $0 }, [citations[0].citationID, citations[0].citationID])
        XCTAssertEqual(found.scrolled, [citations[0].citationID, citations[0].citationID])
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

    // MARK: G8 passage granularity

    func testSegmentsSplitAtSentencesLinesAndTableCells() {
        let text = "Graphene is a single layer of carbon atoms.[1] It is strong.\nYoung's modulus (E)\t≈1 TPa and more\nShort\tTensile strength (σt) 130 GPa"
        let segments = PageContext.segments(text)
        // The sentence break inside "atoms.[1] It" leaves marker fragments; they are trimmed.
        XCTAssertEqual(segments.map(\.text), ["Graphene is a single layer of carbon atoms.", "It is strong.", "Young's modulus (E)", "≈1 TPa and more", "Tensile strength (σt) 130 GPa"])
        XCTAssertEqual(segments.map(\.terminal), [true, true, false, false, false])
        XCTAssertEqual(segments.map(\.prose), [true, false, false, false, false], "prose is a whole sentence of 8–40 words")
        for segment in segments { XCTAssertTrue(text.contains(segment.text)) }
    }

    /// The live infobox: captured text runs its rows together with no sentence end, so the
    /// passage is the densest short run of it, the row alone, not the 60-word block.
    func testATableRowStandsAloneAndProseWinsATie() throws {
        let infobox = "Graphene Graphene is an atomic-scale honeycomb structure made of carbon atoms Material type Allotrope of carbon Chemical properties Chemical formula C "
            + "Mechanical properties Young's modulus (E) ≈1 TPa Tensile strength (σt) 130 GPa Thermal properties Thermal conductivity (k) 5300 W⋅m−1⋅K−1 "
            + "Graphene Graphene is a variety of the element carbon which occurs naturally in small amounts."
        let page = source("Graphene - Wikipedia", infobox + " In 2004, the material was isolated and characterized by Andre Geim and Konstantin Novoselov at the University of Manchester.")
        XCTAssertEqual(PageContext.passage(for: "Tensile strength: 130 GPa [1]", in: page), "Tensile strength (σt) 130 GPa")
        XCTAssertEqual(PageContext.passage(for: "Graphene's tensile strength is 130 GPa [1]", in: page), "Tensile strength (σt) 130 GPa", "a far-off repeat of a word does not stretch the row")
        XCTAssertEqual(PageContext.passage(for: "First isolated: Andre Geim and Konstantin Novoselov in 2004. [1]", in: page),
                       "In 2004, the material was isolated and characterized by Andre Geim and Konstantin Novoselov at the University of Manchester.")

        // The same words in a row and in a sentence of 8–40 words: the sentence.
        let both = source("Page", "Tensile strength (σt) 130 GPa\nIts tensile strength of 130 GPa is the highest ever measured for any material.")
        XCTAssertEqual(PageContext.passage(for: "Tensile strength: 130 GPa", in: both), "Its tensile strength of 130 GPa is the highest ever measured for any material.")
        // More of the claim's words in the row: the row.
        let row = source("Page", "Tensile strength (σt) 130 GPa\nGraphene has remarkable strength and stiffness among all known materials today.")
        XCTAssertEqual(PageContext.passage(for: "Tensile strength: 130 GPa", in: row), "Tensile strength (σt) 130 GPa")

        // A sentence longer than 40 words is cut to at most 40 around the claim, still exact.
        let filler = (1...50).map { "filler\($0)" }.joined(separator: " ")
        let long = source("Page", "Early on \(filler) the measured tensile strength reached 130 GPa in careful tests \(filler).")
        let cut = try XCTUnwrap(PageContext.passage(for: "The tensile strength reached 130 GPa.", in: long))
        XCTAssertLessThanOrEqual(PageContext.words(cut).count, PageContext.passageWordLimit)
        XCTAssertTrue(cut.contains("tensile strength reached 130 GPa"))
        XCTAssertTrue(long.text.contains(cut))
    }

    func testEachClaimGetsItsOwnPassageAndTheSourceOneEntry() throws {
        let page = source("Graphene - Wikipedia", wiki)
        let other = source("Swift", "Swift is a general-purpose programming language developed by Apple. Swift compiles to native code with LLVM.")
        let answer = "Graphene conducts heat very efficiently [1]. Its tensile strength is 130 GPa [1]. Swift compiles with LLVM [2]. It conducts electricity along its plane [1]."
        let citations = ChatCitation.assign(answer: answer, sources: [page, other], messageID: UUID())
        XCTAssertEqual(citations.map(\.index), [1, 1, 2])
        XCTAssertEqual(citations.map(\.sourceNumber), [1, 1, 2])
        XCTAssertEqual(citations.map(\.markers), [[0, 3], [1], [2]], "claims that find the same passage share its citation")
        XCTAssertEqual(ChatCitation.sourcesLine(citations).map { $0.map(\.index) }, [[1, 1], [2]])
        XCTAssertEqual(ChatMarkdown.segments(ChatMarkdown.anchored(answer, citations: citations)).filter { if case .anchored = $0 { return true }; return false },
                       [.anchored(1), .anchored(2), .anchored(3), .anchored(1)])
        // Citations stored before per-claim passages carry no markers: `[n]` stays and resolves by source.
        let legacy = citations.map { var old = $0; old.markers = nil; return old }
        XCTAssertEqual(ChatMarkdown.anchored(answer, citations: legacy), answer)
    }

    // MARK: per-source numbering

    func testEveryChipOfOneSourceShowsItsNumber() throws {
        // The owner's case: five claims of one page, each with its own passage.
        let page = source("Set up Bluetooth on your Mac", "Open System Settings on your Mac. Click Bluetooth in the sidebar. Turn Bluetooth on. "
            + "Put the device in pairing mode. Click Connect next to the device name.")
        let answer = "Open System Settings [1]. Click Bluetooth in the sidebar [1]. Turn Bluetooth on [1]. Put the device in pairing mode [1]. Click Connect next to the device [1]."
        let message = UUID()
        let citations = ChatCitation.assign(answer: answer, sources: [page], messageID: message)
        XCTAssertGreaterThan(citations.count, 1, "the per-claim passages are kept")
        XCTAssertEqual(Set(citations.map(\.index)), [1], "every chip of the one source reads 1")
        XCTAssertEqual(Set(citations.map(\.citationID)).count, citations.count, "each passage keeps its own id and mark")
        XCTAssertEqual(ChatCitation.sourcesLine(citations).map { $0.map(\.index) }, [Array(repeating: 1, count: citations.count)], "one entry, one number")
        // Each chip in the text names its own citation, so hover goes to its own passage.
        let chips = ChatMarkdown.segments(ChatMarkdown.anchored(answer, citations: citations)).compactMap { segment -> Int? in
            if case .anchored(let position) = segment { return position }; return nil
        }
        XCTAssertEqual(chips.count, 5)
        XCTAssertEqual(Set(chips).count, citations.count)
        XCTAssertTrue(chips.allSatisfy { citations.indices.contains($0 - 1) })
        // Two sources: numbered in order of first mention, whatever the model's own numbers.
        let other = source("Swift", "Swift compiles to native code with LLVM.")
        let mixed = ChatCitation.assign(answer: "Swift compiles with LLVM [2]. Open System Settings [1]. Turn Bluetooth on [1].", sources: [page, other], messageID: message)
        XCTAssertEqual(mixed.map(\.index), [1, 2, 2])
        // Answers stored with per-passage numbers are renumbered by source when shown.
        var stored = mixed; stored[2].index = 3
        let old = ChatMessage(role: .assistant, content: "Swift compiles with LLVM [2]. Open System Settings [1]. Turn Bluetooth on [1].", sources: [page, other])
        var session = ChatSession(spaceID: UUID(), profileID: UUID(), messages: [old])
        session.citations = [old.id.uuidString: stored]
        XCTAssertEqual(session.citations(for: old).map(\.index), [1, 2, 2])
    }

    // MARK: quoted excerpts

    func testOnlyExplicitExcerptsAreQuotes() {
        let passage = "In 2004, the material was isolated and characterized by Andre Geim and Konstantin Novoselov at the University of Manchester."
        // A whole sentence found word for word in the passage, chips and punctuation aside.
        XCTAssertTrue(ChatMarkdown.excerpt("In 2004, the material was isolated and characterized by Andre Geim and Konstantin Novoselov. ⁅1⁆", passages: [passage]))
        // Sharing a run of eight words is no longer enough: the sentence adds its own words.
        XCTAssertFalse(ChatMarkdown.excerpt("In 2004 the material was isolated and characterized by Andre Geim, a physicist who later won the Nobel Prize.", passages: [passage]))
        XCTAssertFalse(ChatMarkdown.excerpt("The material was isolated in 2004 by Geim and Novoselov.", passages: [passage]), "a paraphrase is prose")
        XCTAssertFalse(ChatMarkdown.excerpt("was isolated and characterized by Andre Geim", passages: [passage]), "seven words are too short to be an excerpt")
        // Text wholly in quotation marks that the passage holds is an excerpt at any length.
        XCTAssertTrue(ChatMarkdown.excerpt("“isolated and characterized by Andre Geim”. [1]", passages: [passage]))
        XCTAssertFalse(ChatMarkdown.excerpt("“isolated by nobody”", passages: [passage]))
        XCTAssertEqual(ChatMarkdown.echoWords, 8)
        XCTAssertEqual(ChatMarkdown.quoteShare, 0.4)
    }

    func testAQuoteNeedsProseAroundItAndNeverTakesTheWholeAnswer() {
        let passage = "In 2004, the material was isolated and characterized by Andre Geim and Konstantin Novoselov at the University of Manchester."
        let quote = "In 2004, the material was isolated and characterized by Andre Geim and Konstantin Novoselov at the University of Manchester. ⁅1⁆"
        // Alone, the excerpt would be the entire answer: prose.
        XCTAssertEqual(ChatMarkdown.quotePlan(quote, passages: [passage], sources: []), ChatMarkdown.QuotePlan())
        // With enough prose around it (the quote is under 40% of the words), it is a quote.
        let answer = "Graphene was first made in a lab with ordinary sticky tape, which surprised many researchers at the time. " + quote
            + " Since then, researchers have studied its strength, conductivity and many possible uses in electronics and in batteries."
        let plan = ChatMarkdown.quotePlan(answer, passages: [passage], sources: [])
        XCTAssertEqual(plan.sentences, [ChatMarkdown.sentenceKey(quote)])
        XCTAssertEqual(ChatMarkdown.pieces(answer, quoted: plan.sentences).map(\.quote), [false, true, false])
        XCTAssertEqual(ChatMarkdown.pieces(answer, quoted: plan.sentences)[1].text.trimmingCharacters(in: .whitespaces), quote, "the chip stays with its quote")
        // Every sentence verbatim from the page: none may take more than 40%, so most stay prose.
        let first = "Graphene is an allotrope of carbon consisting of a single layer of atoms arranged in a honeycomb lattice."
        let second = "Graphene is the strongest material ever tested, with an intrinsic tensile strength of 130 GPa."
        let third = "Graphene conducts heat and electricity very efficiently along its plane of atoms."
        let all = [first, second, third].joined(separator: " ")
        let copied = ChatMarkdown.quotePlan(all, passages: [first, second, third], sources: [])
        let quotedWords = ChatMarkdown.pieces(all, quoted: copied.sentences).filter(\.quote).map { ChatMarkdown.comparable($0.text).count }.reduce(0, +)
        XCTAssertLessThanOrEqual(Double(quotedWords), 0.4 * Double(ChatMarkdown.comparable(all).count))
        XCTAssertTrue(ChatMarkdown.pieces(all, quoted: copied.sentences).contains { !$0.quote })
        // A block quote that is the whole answer is shown as prose too.
        XCTAssertTrue(ChatMarkdown.quotePlan("> In 2004, the material was isolated.", passages: [], sources: []).blocks.isEmpty)
        XCTAssertEqual(ChatMarkdown.unquoted("> In 2004, the material\n> was isolated."), "In 2004, the material\nwas isolated.")
        XCTAssertEqual(ChatMarkdown.pieces("Plain prose here. More prose.", quoted: []), [ChatMarkdown.Piece(text: "Plain prose here. More prose.", quote: false)])
    }

    func testATrailingChipStaysOnItsSentencesLine() {
        // A chip alone on the last line, after a blank line or not, joins the line before it.
        XCTAssertEqual(ChatMarkdown.attachingOrphanChips("It conducts heat well.\n\n⁅5⁆"), "It conducts heat well. ⁅5⁆")
        XCTAssertEqual(ChatMarkdown.attachingOrphanChips("It conducts heat well.\n[1] [2]"), "It conducts heat well. [1] [2]")
        XCTAssertEqual(ChatMarkdown.attachingOrphanChips("```\n[1]\n```"), "```\n[1]\n```", "code is left alone")
        XCTAssertEqual(ChatMarkdown.attachingOrphanChips("First.\n\nSecond."), "First.\n\nSecond.")
        // In the flow, a chip (and a space after it) is one wrap unit with the word before it.
        let groups = ChatMarkdown.flowGroups("Strong material. ⁅1⁆ Light ⁅2⁆")
        func text(_ group: [ChatMarkdown.FlowToken]) -> String {
            group.map { token -> String in
                switch token {
                case .word(let word): return String(word.characters)
                case .chip(let segment): if case .anchored(let n) = segment { return "<\(n)>" }; return "<?>"
                }
            }.joined()
        }
        XCTAssertEqual(groups.map(text), ["Strong ", "material. <1> ", "Light <2>"])
    }

    // MARK: G8 the panel over the page

    func testAMarkBehindThePanelSaysSoAndScrollsKeepItClear() async {
        // A 1000×800 page at x 300 in the window; the 420pt panel floats over its right side, inset 16.
        let pageFrame = CGRect(x: 300, y: 50, width: 1000, height: 800)
        let panel = CGRect(x: 1300 - 16 - 420, y: 66, width: 420, height: 768)
        let covered = CitationLinker.covered(panel: panel, page: pageFrame)
        XCTAssertEqual(covered, CGRect(x: 564, y: 16, width: 420, height: 768))
        XCTAssertNil(CitationLinker.covered(panel: CGRect(x: 0, y: 0, width: 200, height: 200), page: pageFrame), "a docked panel covers nothing")
        XCTAssertEqual(CitationLinker.uncovered(viewport: pageFrame.size, covered: covered), CGRect(x: 0, y: 0, width: 564, height: 800))

        let clear = CitationLinker.reveal(mark: CGRect(x: 40, y: 1200, width: 300, height: 20), viewport: pageFrame.size, covered: covered)
        XCTAssertEqual(clear.dy, 1210 - 400)
        XCTAssertFalse(clear.behind)
        let behind = CitationLinker.reveal(mark: CGRect(x: 700, y: 100, width: 200, height: 20), viewport: pageFrame.size, covered: covered)
        XCTAssertTrue(behind.behind)
        XCTAssertEqual(behind.dy, 110 - 400, "a mark behind the panel keeps the plain centring")
        XCTAssertFalse(CitationLinker.reveal(mark: CGRect(x: 450, y: 100, width: 200, height: 20), viewport: pageFrame.size, covered: covered).behind, "mostly clear of the panel")
        XCTAssertFalse(CitationLinker.reveal(mark: CGRect(x: 700, y: 100, width: 200, height: 20), viewport: pageFrame.size, covered: nil).behind)

        XCTAssertEqual(CitationChipLink.page.help(title: "Graphene", behind: true), "Behind the Ask panel; scroll to see")
        XCTAssertEqual(CitationChipLink.page.help(title: "Graphene", behind: false), "Show in page")
        XCTAssertEqual(CitationChipLink.unlinkedPage.help(title: "Graphene", behind: true), "Passage not found on this page")

        // Linked and measured: the behind state is recorded, and a click scrolls by the plan, not by centring.
        let tab = UUID(), message = UUID()
        let page = source("Page", "Alpha is the first letter. Beta is the second letter.", id: tab)
        let citations = ChatCitation.assign(answer: "Alpha is the first letter [1]. Beta is the second letter [1].", sources: [page], messageID: message)
        let recorder = PageRecorder(found: citations.map(\.citationID))
        recorder.frame = pageFrame
        recorder.rects = [citations[0].citationID: CGRect(x: 40, y: 1200, width: 300, height: 20), citations[1].citationID: CGRect(x: 700, y: 100, width: 200, height: 20)]
        let linker = CitationLinker()
        linker.panelFrame = panel
        await linker.link(messageID: message, citations: citations, sources: [page], tabID: tab, url: nil, page: recorder.page)
        XCTAssertEqual(linker.behindIDs, [citations[1].citationID])
        await linker.focus(citations[0].citationID)
        XCTAssertEqual(recorder.scrolledBy, [810])
        XCTAssertTrue(recorder.scrolled.isEmpty)
        linker.clear()
        XCTAssertTrue(linker.behindIDs.isEmpty)
    }

    func testTheEmptyStateIsOneLine() {
        XCTAssertEqual(ChatGrounding.emptyState, "Attach a page with @ or ask about this one.")
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
    /// Mark rects in the viewport and the page view's frame; unset, the page is unmeasured.
    var rects: [String: CGRect] = [:]
    var frame: CGRect?
    var scrolledBy: [CGFloat] = []
    let found: [String]
    init(found: [String]) { self.found = found }
    var page: CitationPage {
        CitationPage(highlight: { self.highlighted.append($0); return self.found }, setActive: { self.active.append($0) },
                     scroll: { self.scrolled.append($0) }, clear: { self.clears += 1 },
                     rect: { self.rects[$0] }, frame: { self.frame }, scrollBy: { self.scrolledBy.append($0) })
    }
}

private final class CitationProvider: LanguageModelProvider {
    let output: AsyncThrowingStream<String, Error>
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    init() { let pair = AsyncThrowingStream<String, Error>.makeStream(); output = pair.stream; continuation = pair.continuation }
    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> { output }
}
