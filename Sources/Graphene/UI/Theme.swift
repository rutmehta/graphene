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

/// Graphene's restraint: one warm graphite accent, used sparingly. Neutrals come
/// from the system so the app follows the OS light/dark appearance natively.
enum Theme {
    static let accent = Color(hex: "B4794F")   // warm graphite / ink — deliberately not blue
}
