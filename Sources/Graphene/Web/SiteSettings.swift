import Foundation
import Combine

enum SitePermission: String, Codable, CaseIterable { case ask, allow, block }
struct SitePreference: Codable, Equatable {
    var zoom: Double = 1
    var blocking: Bool?
    var camera: SitePermission = .ask
    var microphone: SitePermission = .ask
    var motion: SitePermission = .ask
}

/// Host keys are canonicalized. Corrupt files are preserved until repaired.
final class SiteSettings: ObservableObject {
    @Published private(set) var entries: [String: SitePreference] = [:]
    @Published private(set) var error: String?
    private let file: URL
    private let persistent: Bool
    init(file: URL, persistent: Bool = true) {
        self.file = file; self.persistent = persistent
        guard persistent, FileManager.default.fileExists(atPath: file.path) else { return }
        do { entries = try JSONDecoder().decode([String: SitePreference].self, from: Data(contentsOf: file)) }
        catch { self.error = "Site settings couldn’t be read. The original file is untouched." }
    }
    func site(_ host: String) -> SitePreference { entries[host.lowercased()] ?? SitePreference() }
    func set(_ value: SitePreference, host: String) throws {
        guard error == nil else { throw CocoaError(.fileReadCorruptFile) }
        var next = entries; var value = value
        value.zoom = Self.zoom(value.zoom, factor: 1)
        next[host.lowercased()] = value
        if persistent { try JSONEncoder().encode(next).write(to: file, options: .atomic) }
        entries = next
    }
    static func zoom(_ current: Double, factor: Double) -> Double {
        if factor == 0 { return 1 }
        let value = current * factor
        return value.isFinite ? min(3, max(0.25, value)) : 1
    }
}
