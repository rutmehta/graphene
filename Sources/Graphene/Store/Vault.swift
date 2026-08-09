import Foundation
import Combine

struct Annotation: Codable, Identifiable {
    let id: UUID
    var text: String
    var note: String
    var url: String
    var title: String
    var context: String
    var created: Date
}

/// The knowledge vault: annotations and daily digests as plain markdown on your
/// disk, each carrying the source it came from. Notes never lose their origin.
@MainActor
final class Vault: ObservableObject {
    @Published private(set) var annotations: [Annotation] = []

    init() { load() }

    func add(text: String, note: String, url: URL?, title: String, context: String) {
        let ann = Annotation(
            id: UUID(), text: text, note: note,
            url: url?.absoluteString ?? "", title: title,
            context: context, created: Date()
        )
        annotations.insert(ann, at: 0)
        persistJSON()
        appendMarkdown(ann)
    }

    func delete(_ ann: Annotation) {
        annotations.removeAll { $0.id == ann.id }
        persistJSON()
    }

    func annotations(forURL url: String) -> [Annotation] {
        annotations.filter { $0.url == url }
    }

    func forget(host: String) {
        annotations.removeAll {
            guard let h = URL(string: $0.url)?.host?.lowercased() else { return false }
            let t = host.lowercased()
            return h == t || h.hasSuffix("." + t)
        }
        persistJSON()
    }

    // MARK: markdown provenance file (one per day)

    private func appendMarkdown(_ ann: Annotation) {
        let day = Self.dayFormatter.string(from: ann.created)
        let file = Paths.vault.appendingPathComponent("annotations").appendingPathComponent("\(day).md")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file.path) {
            try? "---\ntype: annotations\ndate: \(day)\n---\n\n# Annotations — \(day)\n".write(to: file, atomically: true, encoding: .utf8)
        }
        let time = Self.timeFormatter.string(from: ann.created)
        let quoted = ann.text.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")
        var block = "\n## \(time) — \(ann.title)\n\n\(quoted)\n"
        if !ann.note.isEmpty { block += "\n**Note:** \(ann.note)\n" }
        block += "\n— [source](\(ann.url))\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(block.utf8))
            try? handle.close()
        }
    }

    func writeDailyDigest(_ markdown: String, date: Date = Date()) {
        let day = Self.dayFormatter.string(from: date)
        let dir = Paths.vault.appendingPathComponent("daily")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(day).md")
        let body = "---\ntype: daily\ndate: \(day)\n---\n\n# \(day) — Daily Update\n\n\(markdown)\n"
        try? body.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: persistence

    private func persistJSON() {
        let file = Paths.root.appendingPathComponent("annotations.json")
        if let data = try? JSONEncoder().encode(annotations) { try? data.write(to: file) }
    }

    private func load() {
        let file = Paths.root.appendingPathComponent("annotations.json")
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([Annotation].self, from: data) else { return }
        annotations = list
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
}
