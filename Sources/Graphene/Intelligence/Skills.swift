import Foundation

struct ChatSkill: Codable, Identifiable, Equatable {
    enum Context: String, Codable, CaseIterable { case currentTab = "Current tab", allTabs = "Space tabs", thread = "This thread", vault = "Vault notes", history = "Space history" }
    var id = UUID()
    var name: String
    var trigger: String
    var instructions: String
    var contexts: [Context] = [.currentTab]
    static let defaults = [
        ChatSkill(name: "Summarize", trigger: "/summarize", instructions: "Summarize the key points with citations."),
        ChatSkill(name: "Explain", trigger: "/explain", instructions: "Explain the ideas clearly, with examples grounded in the sources."),
        ChatSkill(name: "Compare", trigger: "/compare", instructions: "Compare the sources. Highlight agreements, differences and missing evidence.", contexts: [.allTabs]),
        ChatSkill(name: "TL;DR", trigger: "/tldr", instructions: "Give a three-bullet TL;DR with citations.")
    ]
    static func parse(_ input: String, skills: [ChatSkill]) -> (skill: ChatSkill, rest: String)? {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let first = parts.first, let skill = skills.first(where: { $0.trigger.lowercased() == first.lowercased() }) else { return nil }
        return (skill, parts.count > 1 ? String(parts[1]) : "")
    }
    var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && trigger.range(of: #"^/[a-z][a-z0-9-]*$"#, options: .regularExpression) != nil && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
@MainActor
final class SkillStore: ObservableObject {
    @Published var skills = ChatSkill.defaults
    @Published var error: String?
    private let file: URL
    private var readable = true
    init(root: URL) {
        file = root.appendingPathComponent("skills.json")
        do { if FileManager.default.fileExists(atPath: file.path) { skills = try JSONDecoder().decode([ChatSkill].self, from: Data(contentsOf: file)) } }
        catch { readable = false; self.error = "Skills couldn’t be read. Original file preserved." }
    }
    func save() {
        guard readable else { return }
        guard skills.allSatisfy(\.valid), Set(skills.map(\.trigger)).count == skills.count else { error = "Use unique /lowercase-triggers, names and nonempty instructions."; return }
        do { try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(skills).write(to: file, options: .atomic); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
