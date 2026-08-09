import SwiftUI

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >> 8) & 0xff) / 255
        let b = Double(v & 0xff) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Graphene's look: native materials + system labels so it adapts to light/dark,
/// with one warm graphite accent used sparingly. Hierarchy comes from type and
/// space, not color.
enum Theme {
    static let accent = Color(hex: "C08457")        // warm graphite / ember
    static let accentSoft = Color(hex: "C08457").opacity(0.16)

    /// Hairline used for separators and field borders.
    static func hairline(_ scheme: ColorScheme) -> Color {
        .primary.opacity(scheme == .dark ? 0.09 : 0.10)
    }
    static func fill(_ scheme: ColorScheme, _ level: Double = 1) -> Color {
        .primary.opacity((scheme == .dark ? 0.05 : 0.045) * level)
    }
}
