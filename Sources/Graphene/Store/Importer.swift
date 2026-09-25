import Foundation
import AppKit
import SQLite3

struct ImportedBookmark {
    var title: String
    var url: URL
    var space = "Imported"
    var favorite = false
}
struct ImportedSpace { var name: String; var theme: SpaceTheme? }
struct ImportedHistory { var url: URL; var title: String; var date: Date }
struct ImportBatch {
    var bookmarks: [ImportedBookmark] = []
    var spaces: [ImportedSpace] = []
    var history: [ImportedHistory] = []
    var warnings: [String] = []
}
enum Importer {
    enum Browser: String, CaseIterable { case safari = "Safari", chrome = "Chrome", arc = "Arc" }
    static func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
    static func chrome(_ data: Data) throws -> ImportBatch {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let roots = root["roots"] as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        var result = ImportBatch()
        func visit(_ object: Any) {
            guard let item = object as? [String: Any] else { return }
            if item["type"] as? String == "url", let url = webURL(item["url"] as? String) {
                result.bookmarks.append(ImportedBookmark(title: item["name"] as? String ?? url.host!, url: url))
            }
            for child in item["children"] as? [Any] ?? [] { visit(child) }
        }
        for key in roots.keys.sorted() { visit(roots[key]!) }
        return result
    }
    static func safari(_ data: Data) throws -> ImportBatch {
        let root = try PropertyListSerialization.propertyList(from: data, format: nil)
        var result = ImportBatch()
        func visit(_ object: Any) {
            guard let item = object as? [String: Any] else { return }
            if let url = webURL(item["URLString"] as? String) {
                let title = (item["URIDictionary"] as? [String: Any])?["title"] as? String ?? url.host!
                result.bookmarks.append(ImportedBookmark(title: title, url: url))
            }
            for child in item["Children"] as? [Any] ?? [] { visit(child) }
        }
        visit(root); return result
    }
    static func arc(_ data: Data) throws -> ImportBatch {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sidebar = root["sidebar"] as? [String: Any], let containers = sidebar["containers"] as? [Any] else { throw CocoaError(.fileReadCorruptFile) }
        var result = ImportBatch(); var seen = Set<String>()
        for case let container as [String: Any] in containers {
            let spaces = (container["spaces"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
            let items = (container["items"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
            var byID: [String: [String: Any]] = [:]
            for item in items { if let id = item["id"] as? String { byID[id] = item } }
            var pins: [String: String] = [:]
            let tops = Set((container["topAppsContainerIDs"] as? [Any] ?? []).compactMap { $0 as? String })
            for space in spaces {
                let name = space["title"] as? String ?? "Imported"
                let custom = space["customInfo"] as? [String: Any]
                let window = custom?["windowTheme"] as? [String: Any]
                let palette = window?["primaryColorPalette"] as? [String: Any]
                var theme: SpaceTheme?
                if let rgb = palette?["midTone"] as? [String: Any], let r = rgb["red"] as? Double, let g = rgb["green"] as? Double, let b = rgb["blue"] as? Double {
                    let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1).usingColorSpace(.deviceRGB)!
                    theme = SpaceTheme(hue: color.hueComponent, saturation: color.saturationComponent)
                }
                if !result.spaces.contains(where: { $0.name == name }) { result.spaces.append(ImportedSpace(name: name, theme: theme)) }
                let ids = space["newContainerIDs"] as? [Any] ?? []
                for i in ids.indices where i + 1 < ids.count {
                    if let kind = ids[i] as? [String: Any], kind["pinned"] != nil, let id = ids[i + 1] as? String { pins[id] = name }
                }
                let old = space["containerIDs"] as? [String] ?? []
                for i in old.indices where old[i] == "pinned" && i + 1 < old.count { pins[old[i + 1]] = name }
            }
            for item in items {
                guard let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any], let url = webURL(tab["savedURL"] as? String) else { continue }
                var parent = item["parentID"] as? String; var visited = Set<String>(); var space: String?; var favorite = false
                while let id = parent, visited.insert(id).inserted {
                    if let name = pins[id] { space = name; break }
                    if tops.contains(id) { space = "Imported"; favorite = true; break }
                    parent = byID[id]?["parentID"] as? String
                }
                guard let space else { continue }
                let key = space + "|" + url.absoluteString
                guard seen.insert(key).inserted else { continue }
                result.bookmarks.append(ImportedBookmark(title: item["title"] as? String ?? tab["savedTitle"] as? String ?? url.host!, url: url, space: space, favorite: favorite))
            }
        }
        return result
    }
    static func read(_ browser: Browser, file: URL? = nil) throws -> ImportBatch {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base: URL
        switch browser {
        case .arc: base = home.appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
        case .chrome: base = home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Bookmarks")
        case .safari: base = home.appendingPathComponent("Library/Safari/Bookmarks.plist")
        }
        let data = try Data(contentsOf: file ?? base)
        var result: ImportBatch
        switch browser { case .arc: result = try arc(data); case .chrome: result = try chrome(data); case .safari: result = try safari(data) }
        if browser != .arc && file == nil {
            let history = base.deletingLastPathComponent().appendingPathComponent(browser == .safari ? "History.db" : "History")
            do { result.history = try readHistory(history, safari: browser == .safari) }
            catch { result.warnings.append("Bookmarks read, but history was not imported: \(error.localizedDescription)") }
        }
        return result
    }
    static func readHistory(_ file: URL, safari: Bool) throws -> [ImportedHistory] {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("graphene-history-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: copy) }
        // SQLite backup includes committed WAL pages and leaves the source read-only.
        var source: OpaquePointer?; var destination: OpaquePointer?
        guard sqlite3_open_v2(file.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(source); throw CocoaError(.fileReadNoPermission) }
        defer { sqlite3_close(source) }
        guard sqlite3_open(copy.path, &destination) == SQLITE_OK else { sqlite3_close(destination); throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(destination) }
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else { throw CocoaError(.fileReadUnknown) }
        let status = sqlite3_backup_step(backup, -1); sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE else { throw CocoaError(.fileReadUnknown) }
        let query = safari
            ? "SELECT history_items.url, COALESCE(history_visits.title,''), MAX(history_visits.visit_time) FROM history_items JOIN history_visits ON history_items.id=history_visits.history_item GROUP BY history_items.id ORDER BY MAX(history_visits.visit_time)"
            : "SELECT url, title, last_visit_time FROM urls ORDER BY last_visit_time"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(destination, query, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
        defer { sqlite3_finalize(statement) }
        func text(_ col: Int32) -> String { sqlite3_column_text(statement, col).map { String(cString: $0) } ?? "" }
        var rows: [ImportedHistory] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let url = webURL(text(0)) else { continue }
            let time = sqlite3_column_double(statement, 2)
            let date = safari ? Date(timeIntervalSinceReferenceDate: time) : Date(timeIntervalSince1970: time / 1_000_000 - 11_644_473_600)
            rows.append(ImportedHistory(url: url, title: text(1), date: date))
        }
        return rows
    }
}
