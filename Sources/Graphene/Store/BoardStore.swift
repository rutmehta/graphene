import Foundation
import Combine

struct BoardItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var spaceID: UUID
    var title: String
    var text: String = ""
    var url: String? = nil
    var x: Double = 24
    var y: Double = 24
    var width: Double = 240
    var height: Double = 180
}

@MainActor final class BoardStore: ObservableObject {
    @Published private(set) var entries: [BoardItem] = []
    @Published private(set) var errorText: String?
    private let file: URL?
    private var canSave = true
    init(file: URL?) {
        self.file = file
        if let file, FileManager.default.fileExists(atPath: file.path) {
            do { entries = try JSONDecoder().decode([BoardItem].self, from: Data(contentsOf: file)) }
            catch { canSave = false; errorText = "Boards couldn’t be read. The original file is untouched." }
        }
    }
    func items(in spaceID: UUID) -> [BoardItem] { entries.filter { $0.spaceID == spaceID } }
    func upsert(_ item: BoardItem) {
        guard canSave else { return }
        var item = item
        item.x = min(4000, max(0, item.x)); item.y = min(4000, max(0, item.y))
        item.width = min(800, max(180, item.width)); item.height = min(800, max(120, item.height))
        let previous = entries
        if let index = entries.firstIndex(where: { $0.id == item.id }) { entries[index] = item }
        else { entries.append(item) }
        if !save() { entries = previous }
    }
    func delete(_ id: UUID) {
        guard canSave else { return }
        let previous = entries; entries.removeAll { $0.id == id }
        if !save() { entries = previous }
    }
    func markdown(spaceID: UUID) -> String {
        "# Board\n\n" + items(in: spaceID).map { item in
            let title = item.title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            let heading = item.url.map { "[\(title)](<\($0)>)" } ?? title
            return "- \(heading)\n  " + item.text.replacingOccurrences(of: "\n", with: "\n  ")
        }.joined(separator: "\n\n") + "\n"
    }
    private func save() -> Bool {
        guard let file else { return true }
        do { try JSONEncoder().encode(entries).write(to: file, options: .atomic); errorText = nil; return true }
        catch { errorText = error.localizedDescription; return false }
    }
}
