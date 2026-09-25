import Foundation

struct ThreadBranch: Identifiable, Equatable {
    let id: UUID
    let depth: Int
    static func rows(ids: [UUID], parents: [UUID: UUID]) -> [ThreadBranch] {
        let allowed = Set(ids)
        var seen = Set<UUID>(), rows: [ThreadBranch] = []
        func walk(_ id: UUID, depth: Int) {
            guard seen.insert(id).inserted else { return }
            rows.append(ThreadBranch(id: id, depth: depth))
            for child in ids where child != id && parents[child] == id { walk(child, depth: depth + 1) }
        }
        for id in ids where parents[id] == nil || parents[id] == id || !allowed.contains(parents[id]!) { walk(id, depth: 0) }
        // Corrupt or legacy cycles must not hide sources or recurse indefinitely.
        for id in ids where !seen.contains(id) { walk(id, depth: 0) }
        return rows
    }
}
