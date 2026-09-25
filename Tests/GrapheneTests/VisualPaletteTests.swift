import XCTest
import AppKit
@testable import Graphene

final class VisualPaletteTests: XCTestCase {
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
