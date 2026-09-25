import SwiftUI
import AppKit

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

    /// Linear blend toward `other` by `t` (0…1) in sRGB — our stand-in for CSS color-mix.
    func mixed(with other: Color, by t: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        let t = CGFloat(max(0, min(1, t)))
        return Color(.sRGB,
                     red: Double(a.redComponent + (b.redComponent - a.redComponent) * t),
                     green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * t),
                     blue: Double(a.blueComponent + (b.blueComponent - a.blueComponent) * t),
                     opacity: 1)
    }
}

// MARK: - design knobs (user-controlled, Arc-style)

enum ThemeMode: String, Codable, CaseIterable { case light, dark, automatic }

enum ShellLayout {
    static let pageRadius: CGFloat = 10
    static let rowRadius: CGFloat = 8
    static let popoverRadius: CGFloat = 12
    static let commandRadius: CGFloat = 16
    static let toolbarHeight: CGFloat = 36
    static let rowHeight: CGFloat = 37
    static let rowPitch: CGFloat = 41
    static let favoriteHeight: CGFloat = 56
    static let favoriteGap: CGFloat = 8
    static func favoriteColumns(width: CGFloat) -> Int { width >= 280 ? 4 : 3 }
    static let footerHeight: CGFloat = 36
    static let trafficBandHeight: CGFloat = 48
    static let topTabHeight: CGFloat = 40
    static let sidebarDefault: CGFloat = 224
    // The WP1 brief explicitly extends the matrix's 320pt maximum to 360pt.
    static let sidebarRange: ClosedRange<CGFloat> = 200...360
    static let collapseThreshold: CGFloat = 176
    static let minimumPageWidth: CGFloat = 480
    static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(sidebarRange.upperBound, max(sidebarRange.lowerBound, width))
    }
}

/// A grounded space color: two gradient stops + a readable accent. Not neon.
enum SpaceColor: String, Codable, CaseIterable, Identifiable {
    case clay, moss, tide, iris, slate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clay: return "Clay"; case .moss: return "Moss"; case .tide: return "Tide"
        case .iris: return "Iris"; case .slate: return "Slate"
        }
    }
    var c1: Color {
        switch self {
        case .clay: return Color(hex: "C08361"); case .moss: return Color(hex: "7E9564")
        case .tide: return Color(hex: "5C87A2"); case .iris: return Color(hex: "8B80C6")
        case .slate: return Color(hex: "9A9486")
        }
    }
    var c2: Color {
        switch self {
        case .clay: return Color(hex: "93402F"); case .moss: return Color(hex: "41603C")
        case .tide: return Color(hex: "2E4A63"); case .iris: return Color(hex: "4E4880")
        case .slate: return Color(hex: "565149")
        }
    }
    var accent: Color {
        switch self {
        case .clay: return Color(hex: "9C4536"); case .moss: return Color(hex: "4F7145")
        case .tide: return Color(hex: "3E6C8C"); case .iris: return Color(hex: "645AA0")
        case .slate: return Color(hex: "6C665D")
        }
    }
    var gradient: LinearGradient {
        LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// One of the browser's first-class surfaces (the app tiles in the sidebar).
enum Surface: String, CaseIterable { case web, threads, mail, vault, board }


/// The resolved color system for the current (mode, space). Recomputed cheaply
/// from AppState's published knobs, so any view that reads it updates on change.
/// Boldness is spent in one place — `accent`; everything else is quiet neutrals,
/// faintly tinted by the space color the way Arc floods its chrome.
struct Palette {
    let mode: ThemeMode
    let space: SpaceColor
    var theme: SpaceTheme? = nil
    var neutralChrome = false
    var isDark: Bool {
        mode == .dark || (mode == .automatic && NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
    private var tintColor: Color {
        guard let theme else { return space.accent }
        return Color(hue: min(1, max(0, theme.hue)), saturation: min(1, max(0, theme.saturation)), brightness: 0.65)
    }
    private var intensity: Double { neutralChrome ? 0 : min(0.65, max(0, theme?.intensity ?? 0.25) * 1.8) }
    static func luminance(_ color: Color) -> Double {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func linear(_ v: CGFloat) -> Double { v <= 0.04045 ? Double(v / 12.92) : pow(Double((v + 0.055) / 1.055), 2.4) }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }
    var inkContrast: Double {
        let a = Self.luminance(ink), b = Self.luminance(sidebarBg)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private var chromeBase: Color { isDark ? Color(hex: "29292F") : Color(hex: "ECECEE") }
    private var chromeTint: Color {
        guard isDark else { return tintColor }
        let color = NSColor(tintColor).usingColorSpace(.sRGB) ?? .systemBlue
        return Color(hue: color.hueComponent, saturation: min(0.8, color.saturationComponent * 1.15), brightness: 0.29)
    }
    private var groundBase: Color { isDark ? Color(hex: "181A20") : Color(hex: "F8F9FC") }

    var ink: Color  { Self.luminance(sidebarBg) < 0.179 ? .white : .black }
    var ink2: Color { ink.mixed(with: sidebarBg, by: 0.22) }
    var ink3: Color { ink.mixed(with: sidebarBg, by: 0.35) }
    var hairline: Color { ink.opacity(isDark ? 0.08 : 0.10) }
    var pageBorder: Color { ink.opacity(isDark ? 0 : 0.10) }
    var elev: Color { isDark ? Color(hex: "212227") : Color(hex: "FFFFFF") }
    var selection: Color { Color.white.opacity(isDark ? 0.13 : 0.46) }
    var scrim: Color { Color.black.opacity(isDark ? 0.30 : 0.13) }

    var accent: Color { tintColor }
    var accentText: Color { tintColor.mixed(with: ink, by: 0.4) }
    var accentSoft: Color { tintColor.opacity(isDark ? 0.22 : 0.13) }

    private var chromeMix: Double { isDark ? min(1, intensity * 1.7) : intensity }
    var chromeBg: Color  { chromeBase.mixed(with: chromeTint, by: chromeMix * 0.8) }
    var sidebarBg: Color { chromeBase.mixed(with: chromeTint, by: chromeMix) }
    var sidebarGradient: LinearGradient {
        let preset = NSColor(space.c1).usingColorSpace(.deviceRGB) ?? .systemBlue
        let second = Color(hue: ((theme?.hue ?? preset.hueComponent) + 0.08).truncatingRemainder(dividingBy: 1), saturation: theme?.saturation ?? preset.saturationComponent, brightness: isDark ? 0.29 : 0.65)
        return LinearGradient(colors: [sidebarBg, chromeBase.mixed(with: second, by: chromeMix * 0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var shadow: Color { Color.black.opacity(isDark ? 0.18 : 0.08) }
    var ground: Color { groundBase }

    var hover: Color  { (isDark ? Color.white : Color.black).opacity(isDark ? 0.06 : 0.05) }
    var active: Color { (isDark ? Color.white : Color.black).opacity(isDark ? 0.11 : 0.09) }

    // reading tokens — a clean, cool near-white sheet (a web page doesn't invert)
    var rdBg: Color   { Color(hex: "FCFCFD") }
    var rdInk: Color  { Color(hex: "252933") }
    var rdInk2: Color { Color(hex: "626875") }
    var rdInk3: Color { Color(hex: "727987") }
    var rdHair: Color { Color(hex: "E8ECF2") }
    var wash: Color   { space.accent.opacity(0.16) }

    var c1: Color { space.c1 }
    var c2: Color { space.c2 }
}
