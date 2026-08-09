import Foundation

/// An Arc-style Space: a named, themed context that scopes its own tabs and its
/// own region of the knowledge graph.
final class Space: ObservableObject, Identifiable, Codable {
    let id: UUID
    @Published var name: String
    @Published var accentHex: String
    @Published var glyph: String

    init(id: UUID = UUID(), name: String, accentHex: String, glyph: String = "circle.fill") {
        self.id = id
        self.name = name
        self.accentHex = accentHex
        self.glyph = glyph
    }

    enum CodingKeys: String, CodingKey { case id, name, accentHex, glyph }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        accentHex = try c.decode(String.self, forKey: .accentHex)
        glyph = try c.decodeIfPresent(String.self, forKey: .glyph) ?? "circle.fill"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(accentHex, forKey: .accentHex)
        try c.encode(glyph, forKey: .glyph)
    }
}
