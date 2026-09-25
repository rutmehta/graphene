import XCTest
import SwiftUI
@testable import Graphene

/// D2: the Arc sidebar (arc-look.md §3.3).
final class SidebarTests: XCTestCase {
    func testSidebarGeometryMatchesSpec() {
        let content = ShellLayout.sidebarContentWidth(ShellLayout.sidebarDefault)
        XCTAssertEqual(content, 208)
        XCTAssertEqual(ShellLayout.favoriteTileWidth(contentWidth: content), 62.67, accuracy: 0.01)
        let wide = ShellLayout.sidebarContentWidth(ShellLayout.sidebarRange.upperBound)
        XCTAssertEqual(ShellLayout.favoriteColumns(width: wide), 4)
        XCTAssertEqual(ShellLayout.favoriteTileWidth(contentWidth: wide), (344 - 3 * 10) / 4, accuracy: 0.01)
        // Row anatomy: 8 inset, 20 icon slot, 8 gap, so titles start 36pt into the row.
        XCTAssertEqual(ShellLayout.rowInsetLeading + ShellLayout.iconSlot + ShellLayout.iconGap, 36)
        XCTAssertEqual(ShellLayout.rowHeight, 36)
        XCTAssertEqual(ShellLayout.rowPitch, 40)
        XCTAssertEqual(ShellLayout.folderIndent, 20)
        XCTAssertEqual(ShellLayout.closeTarget, 24)
        XCTAssertEqual(ShellLayout.spaceLabelHeight, 24)
        XCTAssertEqual(ShellLayout.sectionGap, 12)
        XCTAssertEqual(ShellLayout.statusDot, 6)
        XCTAssertEqual(ShellLayout.spaceDotPitch, 14)
        XCTAssertEqual(ShellLayout.footerHeight, 36)
        XCTAssertEqual(ShellLayout.sidebarAddressHeight, 28)
        XCTAssertEqual(ShellLayout.resizeStrip, 8)
        XCTAssertEqual(ShellLayout.spaceSlide, 24)
    }

    func testFooterHoldsArchiveLibraryDotsAndPlusOnly() {
        let idle = SidebarFooterLayout(downloadsActive: false)
        XCTAssertEqual(idle.leading, [.archive, .library])
        XCTAssertEqual(idle.trailing, [.newTab])
        XCTAssertEqual(idle.sideWidth, 2 * ShellLayout.controlSize)
        let downloading = SidebarFooterLayout(downloadsActive: true)
        XCTAssertEqual(downloading.leading, [.archive, .library])
        XCTAssertEqual(downloading.trailing, [.downloads, .newTab])
        XCTAssertEqual(downloading.sideWidth, 2 * ShellLayout.controlSize)
        // The dots stay centred: both side groups share one width, and the strip fits at the narrowest sidebar.
        let narrowest = ShellLayout.sidebarContentWidth(ShellLayout.sidebarRange.lowerBound)
        XCTAssertGreaterThanOrEqual(narrowest - 2 * downloading.sideWidth, 3 * ShellLayout.spaceDotPitch)
    }

    func testAddressPlacementDefaultsToPageAndLegacySettingsLoad() throws {
        let empty = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.addressPlacement, .onPage)
        let legacy = try JSONDecoder().decode(Settings.self, from: Data(#"{"compactSidebar":true,"gutter":false}"#.utf8))
        XCTAssertEqual(legacy.addressPlacement, .onPage)
        XCTAssertFalse(legacy.pageGutter)
        var settings = Settings()
        settings.addressPlacement = .sidebar
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.addressPlacement, .sidebar)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self).contains("compactSidebar"))
    }

    @MainActor func testAddressPlacementPersists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        XCTAssertEqual(app.settings.addressPlacement, .onPage)
        app.settings.addressPlacement = .sidebar
        app.persist()
        XCTAssertEqual(AppState(directory: root).settings.addressPlacement, .sidebar)
    }

    func testSavedSpaceThemesWithRetiredKeysStillLoad() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Research","color":"iris","theme":{"hue":0.68,"saturation":0.6,"intensity":0.3,"gradient":false,"grain":true}}"#
        let space = try JSONDecoder().decode(SpaceInfo.self, from: Data(json.utf8))
        XCTAssertEqual(space.theme, SpaceTheme(hue: 0.68, saturation: 0.6))
        // Saturation drives the chrome: a neutral theme has no hue in the chrome, a tinted one does.
        XCTAssertEqual(Palette(mode: .dark, space: .iris, theme: SpaceTheme(hue: 0.68, saturation: 0)).chromeSaturation, 0)
        XCTAssertEqual(Palette(mode: .dark, space: .iris, theme: space.theme).chromeSaturation, 0.8, accuracy: 0.0001)
    }
}
