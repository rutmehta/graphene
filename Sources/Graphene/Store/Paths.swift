import Foundation

/// On-disk locations. Everything Graphene knows about you lives in one folder
/// you own — no database, no cloud.
enum Paths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Graphene", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The human-readable knowledge vault (markdown annotations, daily digests).
    static var vault: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("GrapheneVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var graphFile: URL { root.appendingPathComponent("graph.json") }
    static var settingsFile: URL { root.appendingPathComponent("settings.json") }
    static var sessionFile: URL { root.appendingPathComponent("session.json") }
}
