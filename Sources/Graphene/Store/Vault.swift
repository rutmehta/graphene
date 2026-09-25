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
    var spaceID: UUID?
    var provenance: String?
    var accountScope: String?
}

extension Annotation {
    /// The prefix of a saved note's in-page mark id; the id is the note's drag reference.
    static let markPrefix = "note:"
    /// The `data-graphene-cite` id of this note's mark: `note:<uuid>`.
    var markID: String { NoteDrag.reference(id) }
    /// The note a mark id names, or nil for any other mark (a citation, the source highlight).
    static func noteID(markID: String) -> UUID? {
        guard markID.hasPrefix(markPrefix) else { return nil }
        return UUID(uuidString: String(markID.dropFirst(markPrefix.count)))
    }
    /// What cite.js marks for this note: its quote under `markID`, or nil when the note has
    /// no quote (a page saved without a selection).
    var passage: CitedPassage? {
        CitedPassage.normalized(text).isEmpty ? nil : CitedPassage(id: markID, text: text)
    }
}

/// The knowledge vault: annotations and daily digests as plain markdown on your
/// disk, each carrying the source it came from. Notes never lose their origin.
@MainActor
final class Vault: ObservableObject {
    @Published private(set) var annotations: [Annotation] = []

    private var canSave = true
    private let file: URL
    private let directory: URL
    @Published private(set) var errorText: String?

    init(file: URL = Paths.root.appendingPathComponent("annotations.json"), directory: URL = Paths.vault, inMemory: Bool = false) {
        self.file = file; self.directory = directory; canSave = !inMemory
        if !inMemory { load() }
    }

    /// Saves a note and returns it, or nil when it could not be saved.
    @discardableResult
    func add(text: String, note: String, url: URL?, title: String, context: String, spaceID: UUID? = nil, provenance: String? = nil, accountScope: String? = nil) -> Annotation? {
        guard canSave else { return nil }
        let ann = Annotation(
            id: UUID(), text: text, note: note,
            url: url?.absoluteString ?? "", title: title,
            context: context, created: Date(), spaceID: spaceID,
            provenance: provenance ?? (url == nil ? "manual" : "web page"), accountScope: accountScope
        )
        let previous = annotations
        annotations.insert(ann, at: 0)
        guard persistJSON() else { annotations = previous; return nil }
        writeNote(ann)
        return ann
    }

    func delete(_ ann: Annotation) {
        guard canSave else { return }
        let previous = annotations
        annotations.removeAll { $0.id == ann.id }
        guard persistJSON() else { annotations = previous; return }
        try? FileManager.default.removeItem(at: noteFile(ann.id))
    }

    func update(_ ann: Annotation, note: String) {
        guard canSave, let index = annotations.firstIndex(where: { $0.id == ann.id }) else { return }
        let previous = annotations
        annotations[index].note = note
        guard persistJSON() else { annotations = previous; return }
        writeNote(annotations[index])
    }

    private func noteFile(_ id: UUID) -> URL {
        directory.appendingPathComponent("notes", isDirectory: true).appendingPathComponent("\(id.uuidString).md")
    }

    private func writeNote(_ annotation: Annotation) {
        let destination = noteFile(annotation.id)
        let body = Self.markdown(for: annotation)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: destination, atomically: true, encoding: .utf8)
        } catch { errorText = error.localizedDescription }
    }

    /// A note as Markdown: title, the quote as a block quote, the note, the source link and
    /// the save date. The note's file on disk and a shelf chip dragged out carry the same text.
    static func markdown(for annotation: Annotation) -> String {
        let quote = annotation.text.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")
        return "# \(annotation.title)\n\n\(quote)\n\n\(annotation.note)\n\n[Source](\(annotation.url))\n\nSaved \(annotation.created.formatted(date: .long, time: .shortened))\n"
    }

    /// Notes saved in `space`, newest first, at most `limit` when given.
    func notes(inSpace space: UUID, limit: Int? = nil) -> [Annotation] {
        let notes = annotations.filter { $0.spaceID == space }.sorted { $0.created > $1.created }
        guard let limit else { return notes }
        return Array(notes.prefix(max(0, limit)))
    }

    func annotations(forURL url: String) -> [Annotation] {
        annotations.filter { KnowledgeGraph.canonicalURL($0.url) == KnowledgeGraph.canonicalURL(url) }
    }

    /// The notes saved from the page at `url` that carry a quote, newest first: the page's saved marks.
    func markedNotes(forURL url: URL) -> [Annotation] {
        annotations(forURL: url.absoluteString).filter { $0.passage != nil }.sorted { $0.created > $1.created }
    }

    func forget(host: String) {
        let target = host.lowercased()
        let removed = annotations.filter {
            guard let host = URL(string: $0.url)?.host?.lowercased() else { return false }
            return host == target || host.hasSuffix("." + target)
        }
        for annotation in removed { delete(annotation) }
    }

    func writeDailyDigest(_ markdown: String, date: Date = Date()) {
        guard canSave else { return }
        let day = Self.dayFormatter.string(from: date)
        let dir = directory.appendingPathComponent("daily")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(day).md")
        let body = "---\ntype: daily\ndate: \(day)\n---\n\n# \(day) — Daily Update\n\n\(markdown)\n"
        try? body.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: persistence

    @discardableResult
    private func persistJSON() -> Bool {
        do {
            let data = try JSONEncoder().encode(annotations)
            try data.write(to: file, options: .atomic)
            errorText = nil
            return true
        } catch { errorText = error.localizedDescription; return false }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { annotations = try JSONDecoder().decode([Annotation].self, from: Data(contentsOf: file)) }
        catch { canSave = false; errorText = "The note index couldn’t be read. It has been left untouched." }
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
}
