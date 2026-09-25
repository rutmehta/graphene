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
