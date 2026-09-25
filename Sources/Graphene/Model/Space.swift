import Foundation

struct SpaceInfo: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var color: SpaceColor
    var icon: String? = nil
    var theme: SpaceTheme? = nil
    var profileID: UUID? = nil
}

/// The space's colour: hue and saturation drive the whole chrome palette.
/// Keys written by earlier versions (intensity, gradient, grain) are ignored on decode.
struct SpaceTheme: Equatable, Codable {
    var hue: Double = 0.57
    var saturation: Double = 0.45
}

enum TabSection: String, Codable, CaseIterable { case favorites, pinned, today }

struct TabFolder: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var spaceID: UUID
    var section: TabSection
    var collapsed = false
}
