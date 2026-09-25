import XCTest
import AppKit
import SwiftUI
@testable import Graphene

final class VisualPaletteTests: XCTestCase {
    private func rgb(_ color: Color, file: StaticString = #filePath, line: UInt = #line) throws -> [Int] {
        let c = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB), file: file, line: line)
        return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
    }
    private func assertNear(_ color: Color, hex: String, tolerance: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try rgb(color, file: file, line: line), expected = try rgb(Color(hex: hex), file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertLessThanOrEqual(abs(a - e), tolerance, "\(actual) vs #\(hex) \(expected)", file: file, line: line)
        }
    }

    @MainActor
    func testDefaultDarkChromeMatchesArcReference() throws {
        let palette = Palette(mode: .dark, space: .iris, theme: SpaceTheme(hue: 243.0 / 360, saturation: 0.6))
        XCTAssertEqual(palette.chromeSaturation, 0.8, accuracy: 0.0001)
        try assertNear(palette.chromeTop, hex: "0E0D26", tolerance: 6)
        try assertNear(palette.chromeBottom, hex: "200A26", tolerance: 6)
        try assertNear(palette.sidebarBg, hex: "0E0D26", tolerance: 6)
    }

    @MainActor
    func testPresetsDriveTheChromeAtSixtyPercentSaturation() throws {
        XCTAssertEqual(SpaceColor.slate.theme.saturation, 0, "Slate is the neutral preset: grey chrome, no hue")
        for space in SpaceColor.allCases where space != .slate {
            let swatch = try XCTUnwrap(NSColor(space.c1).usingColorSpace(.sRGB))
            XCTAssertEqual(space.theme.hue, Double(swatch.hueComponent), accuracy: 0.0001, "Presets keep the swatch hue")
            guard space != .graphite else { continue }
            XCTAssertGreaterThanOrEqual(space.theme.saturation, 0.6, space.rawValue)
            XCTAssertGreaterThanOrEqual(Palette(mode: .dark, space: space).chromeSaturation, 0.8, space.rawValue)
        }
        // Iris no longer collapses to a flat purple: the two dark stops differ clearly in hue and chroma.
        let iris = Palette(mode: .dark, space: .iris)
        let top = try XCTUnwrap(NSColor(iris.chromeTop).usingColorSpace(.sRGB))
        XCTAssertGreaterThan(top.saturationComponent, 0.45)
        // A custom theme keeps its own saturation.
        XCTAssertEqual(Palette(mode: .dark, space: .iris, theme: SpaceTheme(hue: 0.68, saturation: 0.2)).chromeSaturation, 0.6, accuracy: 0.0001)
    }

    // MARK: graphite (graphene-identity.md §3.2)

    private func hsbHex(_ hue: Double, _ saturation: Double, _ brightness: Double) throws -> String {
        let c = try XCTUnwrap(NSColor(Color(hue: hue / 360, saturation: saturation, brightness: brightness)).usingColorSpace(.sRGB))
        return [c.redComponent, c.greenComponent, c.blueComponent].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }

    @MainActor
    func testGraphitePresetIsHue232AtSaturation012() throws {
        XCTAssertEqual(SpaceColor.graphite.label, "Graphite")
        XCTAssertEqual(SpaceColor.graphite.presetSaturation, 0.12)
        XCTAssertEqual(SpaceColor.graphite.theme.hue * 360, 232, accuracy: 0.5)
        XCTAssertEqual(Palette(mode: .dark, space: .graphite).chromeSaturation, 0.56, accuracy: 0.0001)
        XCTAssertEqual(SpaceColor.slate.presetSaturation, 0)
        XCTAssertEqual(SpaceColor.allCases, [.graphite, .iris, .tide, .moss, .clay, .slate], "Picker order")
    }

    @MainActor
    func testGraphiteChromeTopMatchesSpecInBothSchemes() throws {
        let dark = Palette(mode: .dark, space: .graphite), light = Palette(mode: .light, space: .graphite)
        try assertNear(dark.chromeTop, hex: try hsbHex(232, 0.46, 0.15), tolerance: 6)
        // Chrome presence (landing-and-tidy.md §3): light top is HSB(h, 0.30·s′, 0.93), s′ = 0.56.
        try assertNear(light.chromeTop, hex: try hsbHex(232, 0.168, 0.93), tolerance: 6)
        try assertNear(light.chromeBottom, hex: try hsbHex(257, 0.34 * 0.56, 0.90), tolerance: 6)
        XCTAssertGreaterThanOrEqual(dark.inkContrast, 4.5)
        XCTAssertGreaterThanOrEqual(light.inkContrast, 4.5)
    }

    @MainActor
    func testLightChromeCarriesTheSpaceAndEveryPresetStaysReadable() throws {
        for space in SpaceColor.allCases {
            for mode in [ThemeMode.light, .dark] {
                let palette = Palette(mode: mode, space: space)
                XCTAssertGreaterThanOrEqual(palette.inkContrast, 4.5, "\(space) \(mode) top")
                let ink = Palette.luminance(palette.ink), bottom = Palette.luminance(palette.chromeBottom)
                XCTAssertGreaterThanOrEqual((max(ink, bottom) + 0.05) / (min(ink, bottom) + 0.05), 4.5, "\(space) \(mode) bottom")
            }
            let light = Palette(mode: .light, space: space), s = light.chromeSaturation
            let theme = space.theme
            try assertNear(light.chromeTop, hex: try hsbHex(theme.hue * 360, 0.30 * s, 0.93), tolerance: 1)
            try assertNear(light.chromeBottom, hex: try hsbHex(theme.hue * 360 + 25, 0.34 * s, 0.90), tolerance: 1)
        }
        // Light `fill` is white 55% so tiles read on the deeper chrome; dark stays white 9%.
        let alpha = { (color: Color) in Double(NSColor(color).usingColorSpace(.sRGB)?.alphaComponent ?? -1) }
        XCTAssertEqual(alpha(Palette(mode: .light, space: .graphite).fill), 0.55, accuracy: 0.001)
        XCTAssertEqual(alpha(Palette(mode: .dark, space: .graphite).fill), 0.09, accuracy: 0.001)
    }

    func testOldSpaceColorValuesStillDecode() throws {
        for raw in ["clay", "moss", "tide", "iris", "slate"] {
            let decoded = try JSONDecoder().decode([SpaceColor].self, from: Data("[\"\(raw)\"]".utf8))
            XCTAssertEqual(decoded.first?.rawValue, raw)
        }
    }

    @MainActor
    func testNewSpacesAndFreshOnboardingDefaultToGraphite() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        XCTAssertEqual(OnboardingView.swatches, [.graphite, .iris, .tide])
        // Onboarding marks the swatch matching the active space's preset as selected.
        XCTAssertEqual(app.activeSpace.color, .graphite, "A fresh profile's first space is graphite")
        XCTAssertNil(app.activeSpace.theme)
        let id = app.createSpace(name: "Fresh")
        XCTAssertEqual(app.spaces.first { $0.id == id }?.color, .graphite)
    }

    @MainActor
    func testNeutralSpacesDropAllHue() throws {
        for palette in [Palette(mode: .dark, space: .clay, theme: SpaceTheme(hue: 0.3, saturation: 0)),
                        Palette(mode: .light, space: .clay, neutralChrome: true)] {
            XCTAssertEqual(palette.chromeSaturation, 0)
            for color in [palette.chromeTop, palette.chromeBottom] {
                let channels = try rgb(color)
                XCTAssertEqual(channels.max(), channels.min())
            }
        }
    }

    @MainActor
    func testInkStaysReadableOnChromeAcrossHues() {
        for mode in [ThemeMode.dark, .light] {
            for degrees in [0.0, 120, 243, 300] {
                for saturation in [0.0, 0.6, 1] {
                    let palette = Palette(mode: mode, space: .tide, theme: SpaceTheme(hue: degrees / 360, saturation: saturation))
                    XCTAssertGreaterThanOrEqual(palette.inkContrast, 4.5, "\(mode) h=\(degrees) s=\(saturation)")
                    let ink = Palette.luminance(palette.ink), bottom = Palette.luminance(palette.chromeBottom)
                    XCTAssertGreaterThanOrEqual((max(ink, bottom) + 0.05) / (min(ink, bottom) + 0.05), 4.5, "\(mode) h=\(degrees) bottom")
                }
            }
        }
    }

    @MainActor
    func testDarkSidebarIsDeeplyTintedRatherThanMidGray() {
        for space in SpaceColor.allCases {
            let palette = Palette(mode: .dark, space: space)
            XCTAssertLessThan(Palette.luminance(palette.sidebarBg), 0.05, space.rawValue)
            XCTAssertGreaterThan(palette.inkContrast, 4.5)
        }
    }

    @MainActor
    func testTopTabsLocationUsesTheSameCommandSession() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        app.layout = .topTabs
        app.focusAddress()
        XCTAssertTrue(app.commandBarPresented)
        XCTAssertFalse(app.commandBarCreatesTab)
        app.commandBarDraft = "draft question"
        app.dismissCommandBar()
        XCTAssertFalse(app.commandBarPresented)
        app.openCommandBar(newTab: true)
        app.commandBarDraft = "unfinished search"
        app.dismissCommandBar()
        app.openCommandBar(newTab: true)
        XCTAssertEqual(app.commandBarDraft, "unfinished search")
    }

    @MainActor
    func testTopTabsChromeIsNeutralAcrossSpaceColors() {
        for mode in [ThemeMode.light, .dark] {
            let reference = Palette(mode: mode, space: .tide, neutralChrome: true)
            for space in SpaceColor.allCases {
                let palette = Palette(mode: mode, space: space, neutralChrome: true)
                XCTAssertEqual(NSColor(palette.chromeBg), NSColor(reference.chromeBg))
                XCTAssertGreaterThan(palette.inkContrast, 4.5)
            }
        }
    }

    @MainActor
    func testSidebarThemesRemainDistinctAndReadable() {
        for mode in [ThemeMode.light, .dark] {
            let neutral = Palette(mode: mode, space: .tide, neutralChrome: true)
            for space in SpaceColor.allCases {
                let palette = Palette(mode: mode, space: space)
                if space != .slate { XCTAssertNotEqual(NSColor(palette.sidebarBg), NSColor(neutral.sidebarBg)) }
                XCTAssertGreaterThan(palette.inkContrast, 4.5)
            }
        }
    }

    @MainActor
    func testLayoutSwitchDoesNotRewriteSpaceTheme() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let theme = SpaceTheme(hue: 0.15, saturation: 0.5)
        app.updateSpaceTheme(theme)
        app.layout = .topTabs
        XCTAssertTrue(app.pal.neutralChrome)
        app.persist()
        let restored = AppState(directory: directory)
        XCTAssertEqual(restored.layout, .topTabs)
        XCTAssertEqual(restored.activeSpace.theme, theme)
        restored.layout = .sidebar
        XCTAssertFalse(restored.pal.neutralChrome)
        XCTAssertEqual(restored.activeSpace.theme, theme)
    }
}
