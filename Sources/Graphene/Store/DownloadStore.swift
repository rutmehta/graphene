import Foundation
import Combine

struct DownloadEntry: Codable, Identifiable {
    enum Status: String, Codable { case active, finished, failed, interrupted }
    var id = UUID()
    var destination: URL
    var date = Date()
    var progress = 0.0
    var status = Status.active
    var error: String?
    var sourceURL: URL?
    var profileID: UUID?
}

@MainActor
final class DownloadStore: ObservableObject {
    @Published private(set) var entries: [DownloadEntry] = []
    @Published private(set) var completionCount = 0
    @Published private(set) var errorText: String?
    private let file: URL?
    private var canSave = true
    var preferredDirectory: (() -> URL?)?
    var onFinished: ((DownloadEntry) -> Void)?
    init(file: URL?) {
        self.file = file
        if let file, FileManager.default.fileExists(atPath: file.path) {
            do {
                entries = try JSONDecoder().decode([DownloadEntry].self, from: Data(contentsOf: file))
                for i in entries.indices where entries[i].status == .active { entries[i].status = .interrupted }
            } catch { canSave = false; errorText = "Download history couldn’t be read. Its file is untouched." }
        }
    }
    func begin(_ url: URL, sourceURL: URL? = nil, profileID: UUID? = nil) -> UUID {
        let entry = DownloadEntry(destination: url, sourceURL: sourceURL, profileID: profileID)
        entries.insert(entry, at: 0); save(); return entry.id
    }
    func update(_ id: UUID, progress: Double) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].progress = max(0, min(1, progress))
    }
    func finish(_ id: UUID, error: String?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = error == nil ? .finished : .failed
        entries[index].error = error
        if error == nil { entries[index].progress = 1; completionCount += 1 }
        save()
        if error == nil { onFinished?(entries[index]) }
    }
    func rename(_ id: UUID, to name: String) throws {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.status == .finished }),
              AITidy.filename(name, original: entries[index].destination.lastPathComponent) == name else { throw ProviderFailure(message: "Invalid download name.") }
        let old = entries[index].destination, new = old.deletingLastPathComponent().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: new.path) else { throw ProviderFailure(message: "A file with this name already exists.") }
        try FileManager.default.moveItem(at: old, to: new)
        guard FileManager.default.fileExists(atPath: new.path), !FileManager.default.fileExists(atPath: old.path) else { throw ProviderFailure(message: "Rename verification failed.") }
        entries[index].destination = new; save()
    }
    func clear() { entries.removeAll { $0.status != .active }; save() }
    func hasRecentActivity(at now: Date) -> Bool {
        entries.contains { $0.status == .active || now.timeIntervalSince($0.date) < 24 * 3600 }
    }
    private func save() {
        guard let file, canSave else { return }
        do { try JSONEncoder().encode(entries).write(to: file, options: .atomic); errorText = nil }
        catch { errorText = "Couldn’t save download history: \(error.localizedDescription)" }
    }
}
