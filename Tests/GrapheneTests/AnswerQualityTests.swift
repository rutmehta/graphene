import XCTest
@testable import Graphene

final class AnswerQualityTests: XCTestCase {
    @MainActor func testWritingPreambles() {
        for input in ["Here is the rewritten text:\n\nWe will meet tomorrow.", "Sure! Here's a revised version:\n\"We will meet tomorrow.\"", "Rewritten text:\n```text\nWe will meet tomorrow.\n```", "Here’s the improved text:\n“We will meet tomorrow.”"] {
            XCTAssertEqual(DraftGenerator.clean(input), "We will meet tomorrow.")
        }
        XCTAssertEqual(DraftGenerator.clean("Here is the plan for tomorrow.\nBring notes."), "Here is the plan for tomorrow.\nBring notes.")
    }
    func testSourcesArePlainLabeledExcerpts() {
        let source = KnowledgeSource(id: UUID(), title: "Example Domain", url: "https://example.org", text: "This domain is for use in documentation examples.", kind: "Page")
        let prompt = PageContext.prompt([source])
        XCTAssertTrue(prompt.contains("Source [1]: Example Domain\n"))
        XCTAssertTrue(prompt.contains("\nThis domain is for use in documentation examples."))
        XCTAssertFalse(prompt.contains("UNTRUSTED_SOURCES_JSON"))
    }

    /// The final turn puts the question after the sources; the on-device model never sees an
    /// earlier answer (it replayed one verbatim), only earlier questions marked as answered.
    func testFollowUpRequestsNeverCarryAnEarlierAnswer() {
        let page = KnowledgeSource(id: UUID(), title: "Graphene - Wikipedia", url: "https://en.wikipedia.org/wiki/Graphene", text: "Graphene has a tensile strength of 130 GPa.", kind: "Tab")
        let earlierAnswer = "Graphene has a tensile strength of 130 GPa. [1]"
        let history = [ChatMessage(role: .user, content: "What is graphene's tensile strength?"), ChatMessage(role: .assistant, content: earlierAnswer, sources: [page]),
                       ChatMessage(role: .user, content: "What is the capital of Peru?")]
        let onDevice = PageContext.conversation(history, system: PageContext.instructions, sources: [page], skills: ChatSkill.defaults, onDevice: true)
        XCTAssertEqual(onDevice.map(\.role), [.system, .user], "one self-contained turn")
        let turn = onDevice[1].content
        XCTAssertFalse(turn.contains(earlierAnswer))
        XCTAssertTrue(turn.hasSuffix("\n\nQuestion: What is the capital of Peru?"), "the question comes last")
        XCTAssertTrue(turn.hasPrefix("Source [1]: Graphene - Wikipedia\n"))
        XCTAssertTrue(turn.contains(PageContext.earlierHeading + "\n- What is graphene's tensile strength?"))
        let remote = PageContext.conversation(history, system: PageContext.instructions, sources: [page], skills: ChatSkill.defaults, onDevice: false)
        XCTAssertEqual(remote.map(\.role), [.system, .user, .assistant, .user])
        XCTAssertTrue(remote[3].content.hasSuffix("Question: What is the capital of Peru?"))
        // A first question has no earlier-questions block; skills still expand.
        let first = PageContext.conversation([ChatMessage(role: .user, content: "/tldr")], system: "s", sources: [page], skills: ChatSkill.defaults, onDevice: true)
        XCTAssertFalse(first[1].content.contains(PageContext.earlierHeading))
        XCTAssertTrue(first[1].content.hasSuffix("Question: Give a three-bullet TL;DR with citations."))
        // The instructions ask for the question asked, and one sentence when the sources lack it.
        for phrase in ["latest question", "Never repeat an earlier answer", "do not contain the answer, say so in one sentence", PageContext.notInSources] {
            XCTAssertTrue(PageContext.instructions.contains(phrase), phrase)
        }
        // The guardrail retry shortens the sources, never the question.
        let long = PageContext.request("Who isolated it?", sources: [KnowledgeSource(id: UUID(), title: "Long", url: "https://example.org", text: String(repeating: "graphene ", count: 600), kind: "Tab")], skills: [])
        let short = PageContext.shortened(long, limit: 2400)
        XCTAssertEqual(short.count, 2400)
        XCTAssertTrue(short.hasSuffix("\n\nQuestion: Who isolated it?"))
        XCTAssertEqual(PageContext.shortened("brief", limit: 2400), "brief")
    }

    /// Initials and common abbreviations do not end a sentence ("Philip R. Wallace").
    func testSentencesDoNotBreakAfterInitialsOrAbbreviations() {
        let answer = "It was first theorized in 1947 by Philip R. Wallace and isolated in 2004. Dr. Geim used tape, e.g. Scotch tape, vs. other methods. It is strong."
        let sentences = PageContext.sentenceRanges(answer).map { String(answer[$0]).trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(sentences, ["It was first theorized in 1947 by Philip R. Wallace and isolated in 2004.",
                                   "Dr. Geim used tape, e.g. Scotch tape, vs. other methods.", "It is strong."])
        XCTAssertEqual(PageContext.sentenceRanges(answer).first?.lowerBound, answer.startIndex)
        XCTAssertEqual(PageContext.sentenceRanges(answer).last?.upperBound, answer.endIndex)
        XCTAssertEqual(PageContext.sentences("Mrs. Smith (St. Louis) met Mr. Jones. Then they left."), ["Mrs. Smith (St. Louis) met Mr. Jones.", "Then they left."])
        XCTAssertTrue(PageContext.nonTerminal("by Philip R."))
        XCTAssertTrue(PageContext.nonTerminal("see (e.g."))
        XCTAssertFalse(PageContext.nonTerminal("in 1987."))
        XCTAssertFalse(PageContext.nonTerminal("it is a."), "a lowercase letter is a word, not an initial")
        // Fallback citations anchor the whole sentence, not the part before "R.".
        let page = KnowledgeSource(id: UUID(), title: "Graphene", url: "https://en.wikipedia.org/wiki/Graphene",
                                   text: "The existence of graphene was first theorized in 1947 by Philip R. Wallace during his research on graphite's electronic properties.", kind: "Tab")
        let citations = ChatCitation.assign(answer: "Graphene was first theorized in 1947 by Philip R. Wallace during research on graphite.", sources: [page], messageID: UUID())
        XCTAssertEqual(citations.first?.anchors, ["Graphene was first theorized in 1947 by Philip R. Wallace during research on graphite."])
        // Footnote-marker pieces left at sentence edges are trimmed from passages.
        XCTAssertEqual(PageContext.trimMarkerFragments("7][8] The existence of graphene. [9"), "The existence of graphene.")
        XCTAssertEqual(PageContext.trimMarkerFragments("Graphene [1] is carbon.[2]"), "Graphene [1] is carbon.[2]")
    }

    // Explicit opt-in: ordinary tests never invoke Apple Intelligence. Writes the report to
    // GRAPHENE_AI_ANSWERS (to its "-followup" sibling when GRAPHENE_AI_QUESTIONS also runs the
    // single-turn harness). The page text is the fetched Wikipedia excerpt in docs/parity/shots/wp8.
    func testLiveFollowUpAnswersTheNewQuestion() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard var output = environment["GRAPHENE_AI_ANSWERS"] else { throw XCTSkip("Opt-in real-model harness") }
        if environment["GRAPHENE_AI_QUESTIONS"] != nil { output = (output as NSString).deletingPathExtension + "-followup.md" }
        struct Row: Decodable { let url: String; let title: String; let text: String }
        let inputs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/parity/shots/wp8/inputs.json")
        let row = try XCTUnwrap(JSONDecoder().decode([Row].self, from: Data(contentsOf: inputs)).first { $0.url.contains("wikipedia.org/wiki/Graphene") })
        let page = KnowledgeSource(id: UUID(), title: "Graphene - Wikipedia", url: row.url, text: row.text, kind: "Tab")
        let sources = PageContext.budget([page], limit: 6000).sources
        var history: [ChatMessage] = []
        var answers: [String] = []
        var report = "# Real on-device follow-up\n\nSame PageContext.conversation and OnDeviceProvider as Chat; the page is the fetched Wikipedia Graphene excerpt.\n\n"
        for question in ["What is graphene's tensile strength and who first isolated it?", "What is the capital of Peru?"] {
            history.append(ChatMessage(role: .user, content: question))
            let messages = PageContext.conversation(history, system: PageContext.instructions, sources: sources, skills: ChatSkill.defaults, onDevice: true)
            var answer = ""
            do { for try await delta in OnDeviceProvider().stream(messages: messages) { answer += delta } }
            catch { answer += "\nERROR: " + error.localizedDescription }
            history.append(ChatMessage(role: .assistant, content: answer, sources: sources))
            answers.append(answer)
            let citations = ChatCitation.assign(answer: answer, sources: sources, messageID: UUID())
            report += "## \(question)\n\n\(answer)\n\nCitations: \(citations.count)\(citations.isEmpty ? " (panel shows: \(ChatGrounding.noSources))" : "")\n\n"
            for citation in citations { report += "- [\(citation.index)] passage: \(citation.passage ?? "none")\n" }
            report += "\n"
            try report.write(toFile: output, atomically: true, encoding: .utf8)
            XCTAssertFalse(answer.contains("ERROR:"), answer)
        }
        let second = answers[1].lowercased()
        XCTAssertNotEqual(answers[1].trimmingCharacters(in: .whitespacesAndNewlines), answers[0].trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertFalse(second.contains("130"), "the follow-up must not replay the graphene answer")
        let saysMissing = ["don't cover", "do not cover", "does not contain", "don't contain", "do not contain", "doesn't contain", "not mention", "no information"].contains { second.contains($0) }
        XCTAssertTrue(saysMissing || second.contains("lima"), "either the not-in-sources sentence or a real answer")
    }

    // Explicit opt-in: ordinary tests never download pages or invoke Apple Intelligence.
    func testLiveAnswers() async throws {
        guard let input = ProcessInfo.processInfo.environment["GRAPHENE_AI_QUESTIONS"],
              let output = ProcessInfo.processInfo.environment["GRAPHENE_AI_ANSWERS"] else { throw XCTSkip("Opt-in real-model harness") }
        struct Question: Decodable { let url: String; let title: String; let text: String; let question: String }
        let questions = try JSONDecoder().decode([Question].self, from: Data(contentsOf: URL(fileURLWithPath: input)))
        var report = "# Real on-device answers\n\nSame PageContext builder and OnDeviceProvider as Chat. Source excerpts are fetched public page text, not model-generated fixtures.\n\n"
        for question in questions {
            let source = KnowledgeSource(id: UUID(), title: question.title, url: question.url, text: question.text, kind: "Page")
            let messages = [ChatMessage(role: .system, content: PageContext.instructions), ChatMessage(role: .user, content: PageContext.request(question.question, sources: PageContext.budget([source], limit: 6000).sources, skills: ChatSkill.defaults))]
            var answer = "", chunks = 0
            do {
                for try await delta in OnDeviceProvider().stream(messages: messages) { answer += delta; chunks += 1 }
            } catch { answer += "\nERROR: " + error.localizedDescription }
            report += "## \(question.title)\n\nSource: \(question.url)\n\nQuestion: \(question.question)\n\nStream updates: \(chunks)\n\n\(answer)\n\n"
            try report.write(toFile: output, atomically: true, encoding: .utf8)
            XCTAssertFalse(answer.isEmpty)
            XCTAssertGreaterThan(chunks, 0, "The harness must actually receive model output")
            XCTAssertFalse(answer.contains("ERROR:"), "Do not treat provider errors as answers")
            for refusal in ["cannot fulfill", "cannot summarize", "can't summarize", "cannot provide a summary", "unable to fulfill"] {
                XCTAssertFalse(answer.lowercased().contains(refusal), "Benign-page refusal is not a successful answer")
            }
        }
    }
}
