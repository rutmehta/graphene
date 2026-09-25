import Foundation

struct PersonalMemory: Codable, Identifiable {
    var id = UUID()
    var profileID: UUID
    var text: String
    var created = Date()
}
@MainActor
final class MemoryStore: ObservableObject {
    @Published var items: [PersonalMemory] = []
    @Published var error: String?
    private let file: URL
    private var readable = true
    init(root: URL) {
        file = root.appendingPathComponent("memory.json")
        do { if FileManager.default.fileExists(atPath: file.path) { items = try JSONDecoder().decode([PersonalMemory].self, from: Data(contentsOf: file)) } }
        catch { readable = false; self.error = "Personal context couldn’t be read. Original file preserved." }
    }
    nonisolated static func parse(_ text: String) -> [String] {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") { value = value.components(separatedBy: "\n").dropFirst().filter { $0 != "```" }.joined(separator: "\n") }
        guard let data = value.data(using: .utf8), let facts = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        var seen = Set<String>()
        return Array(facts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.count <= 300 && seen.insert($0.lowercased()).inserted }.prefix(3))
    }
    func add(_ facts: [String], profile: UUID) {
        for fact in facts where !items.contains(where: { $0.profileID == profile && $0.text.lowercased() == fact.lowercased() }) { items.append(PersonalMemory(profileID: profile, text: fact)) }
        items = Array(items.suffix(300)); save()
    }
    func save() {
        guard readable else { return }
        do { try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(items).write(to: file, options: .atomic); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
