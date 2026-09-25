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
                XCTAssertNotEqual(NSColor(palette.sidebarBg), NSColor(neutral.sidebarBg))
                XCTAssertGreaterThan(palette.inkContrast, 4.5)
            }
        }
    }

    @MainActor
    func testLayoutSwitchDoesNotRewriteSpaceTheme() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let theme = SpaceTheme(hue: 0.15, saturation: 0.5, intensity: 0.3)
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
