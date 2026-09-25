import Foundation

extension AppState {
    /// Import through the same path from Settings and the isolated debug driver.
    func applyImport(_ batch: ImportBatch, progress: (Double) -> Void = { _ in }) async -> String {
        guard !isPrivate else { return "Import is unavailable in private windows." }
        let originalSpace = activeSpaceID, originalTab = activeTabID
        var destinations: [String: UUID] = [:]
        var added = 0, history = 0, skipped = 0
        for imported in batch.spaces {
            let existing = spaces.first { $0.name == imported.name }?.id
            let id = existing ?? createSpace(name: imported.name)
            destinations[imported.name] = id
            if existing == nil, let theme = imported.theme, let index = spaces.firstIndex(where: { $0.id == id }) { spaces[index].theme = theme }
        }
        for (index, bookmark) in batch.bookmarks.enumerated() {
            let id = destinations[bookmark.space] ?? spaces.first { $0.name == bookmark.space }?.id ?? createSpace(name: bookmark.space)
            destinations[bookmark.space] = id
            if tabs.contains(where: { $0.spaceID == id && $0.url == bookmark.url && $0.isPinned }) { skipped += 1; continue }
            activeSpaceID = id
            let tab = newTab(activate: false)
            tab.url = bookmark.url; tab.title = bookmark.title; tab.pinnedURL = bookmark.url
            tab.isPinned = true; tab.isFavorite = bookmark.favorite; tab.discard(); added += 1
            progress(Double(index + 1) / Double(max(1, batch.bookmarks.count + batch.history.count)))
            if index % 20 == 0 { await Task.yield() }
        }
        if !batch.history.isEmpty {
            let id = destinations["Imported"] ?? spaces.first { $0.name == "Imported" }?.id ?? createSpace(name: "Imported")
            for (index, page) in batch.history.enumerated() {
                if graph.node(for: page.url) == nil {
                    graph.recordVisit(url: page.url, title: page.title, spaceID: id, parentNodeID: nil, query: nil, date: page.date.addingTimeInterval(Double(index) * 0.001)); history += 1
                } else { skipped += 1 }
                progress(Double(batch.bookmarks.count + index + 1) / Double(max(1, batch.bookmarks.count + batch.history.count)))
                if index % 50 == 0 { await Task.yield() }
            }
            graph.save()
        }
        activeSpaceID = originalSpace; activeTabID = originalTab; persist()
        var summary = "Imported \(added) bookmarks and \(history) history pages. Skipped \(skipped) duplicates. Passwords were not imported.\n" + batch.warnings.joined(separator: "\n")
        if let error = sessionError ?? graph.errorText { summary += "\nPersistence error: \(error)" }
        return summary
    }
}
