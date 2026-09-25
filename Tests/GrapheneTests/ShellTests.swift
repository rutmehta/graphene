import XCTest
@testable import Graphene

final class ShellTests: XCTestCase {
    func testFaviconOriginsAndDeclaredIconPolicy() {
        let page = URL(string: "https://example.com:8443/docs")!
        XCTAssertEqual(FaviconPolicy.declaredURL("/brand.png", page: page)?.absoluteString, "https://example.com:8443/brand.png")
        XCTAssertEqual(FaviconPolicy.fallbackURL(page: page)?.absoluteString, "https://example.com:8443/favicon.ico")
        // A page may declare its icon on its own CDN; downgrades, credentials and non-web schemes are refused.
        XCTAssertEqual(FaviconPolicy.declaredURL("https://cdn.example/icon.png", page: page)?.absoluteString, "https://cdn.example/icon.png")
        XCTAssertNil(FaviconPolicy.declaredURL("http://cdn.example/icon.png", page: page))
        XCTAssertNil(FaviconPolicy.declaredURL("https://user:pw@cdn.example/icon.png", page: page))
        XCTAssertNil(FaviconPolicy.declaredURL("javascript:alert(1)", page: page))
        XCTAssertNil(FaviconPolicy.fallbackURL(page: URL(string: "file:///tmp/a")!))
        XCTAssertFalse(FaviconPolicy.sameOrigin(page, URL(string: "https://example.com/")!))
        XCTAssertFalse(FaviconPolicy.sameOrigin(page, URL(string: "http://example.com:8443/")!))
    }
    @MainActor
    func testCrossSpaceDropReorderAndFolderDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let first = try XCTUnwrap(app.activeTab)
        let second = app.newTab()
        let third = app.newTab()
        app.activate(first.id); app.reorderActiveTab(1)
        XCTAssertEqual(app.visibleTabs.map(\.id), [second.id, first.id, third.id])
        let folder = app.createFolder(section: .today)
        app.placeTab(first.id, section: .today, folderID: folder)
        app.deleteFolder(folder)
        XCTAssertNil(first.folderID)
        let destination = app.spaces.last!.id
        app.placeTab(first.id, section: .favorites, spaceID: destination)
        XCTAssertFalse(app.visibleTabs.contains { $0.id == first.id })
        app.selectSpace(destination)
        XCTAssertEqual(first.section, .favorites)
        app.resizeSidebar(300, windowID: "one")
        app.resizeSidebar(240, windowID: "two")
        app.persist()
        let restored = AppState(directory: directory)
        XCTAssertEqual(restored.sidebarWidths["one"], 300)
        XCTAssertEqual(restored.sidebarWidths["two"], 240)
        for hue in stride(from: 0.0, through: 1.0, by: 0.1) {
            for mode in [ThemeMode.light, .dark] {
                let palette = Palette(mode: mode, space: .tide, theme: SpaceTheme(hue: hue, saturation: 1))
                XCTAssertGreaterThan(palette.inkContrast, 4.5)
            }
        }
    }
    @MainActor
    func testThemeAndLayoutPersistenceAndLegacyDecode() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let theme = SpaceTheme(hue: 0.12, saturation: 0.8)
        app.updateSpaceTheme(theme, icon: "leaf")
        app.resizeSidebar(340)
        app.mode = .automatic
        app.persist()
        let restored = AppState(directory: directory)
        XCTAssertEqual(restored.activeSpace.theme, theme)
        XCTAssertEqual(restored.activeSpace.icon, "leaf")
        XCTAssertEqual(restored.sidebarWidth, 340)
        XCTAssertEqual(restored.mode, .automatic)
        XCTAssertEqual(ShellLayout.clampedSidebarWidth(100), 180)
        XCTAssertEqual(ShellLayout.clampedSidebarWidth(500), 360)
        let legacy = Data("{\"tabs\":[{\"pinned\":true,\"url\":\"https://example.com\"}],\"activeIndex\":0}".utf8)
        let decoded = try JSONDecoder().decode(AppState.SessionData.self, from: legacy)
        XCTAssertNil(decoded.tabs.first?.favorite)
        XCTAssertNil(decoded.folders)
        for mode in [ThemeMode.light, .dark] {
            let palette = Palette(mode: mode, space: .tide, theme: theme)
            XCTAssertGreaterThan(palette.inkContrast, 4.5)
        }
    }
    @MainActor
    func testClassificationFoldersAndSessionRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let tab = try XCTUnwrap(app.activeTab)
        tab.url = URL(string: "https://example.com/base")
        app.pin(tab)
        XCTAssertEqual(tab.section, .pinned)
        XCTAssertEqual(tab.pinnedURL, tab.url)
        let folder = app.createFolder(name: "Reading", section: .pinned)
        app.placeTab(tab.id, section: .pinned, folderID: folder)
        XCTAssertEqual(tab.folderID, folder)
        tab.url = URL(string: "https://example.com/elsewhere")
        app.renameTab(tab, name: "My reading")
        app.persist()
        let restored = AppState(directory: directory)
        let restoredTab = try XCTUnwrap(restored.activeTab)
        XCTAssertEqual(restoredTab.pinnedURL?.path, "/base")
        XCTAssertEqual(restoredTab.displayTitle, "My reading")
        XCTAssertEqual(restoredTab.folderID, folder)
        XCTAssertEqual(restored.folders.first?.name, "Reading")
        app.placeTab(tab.id, section: .favorites)
        XCTAssertEqual(tab.section, .favorites)
        XCTAssertNil(tab.folderID)
        app.placeTab(tab.id, section: .today)
        XCTAssertFalse(tab.isPinned)
        XCTAssertNil(tab.pinnedURL)
        app.archiveToday()
        XCTAssertEqual(app.archivedTabs.count, 1)
        app.reopenClosedTab()
        XCTAssertEqual(app.activeTab?.displayTitle, "My reading")
    }
    @MainActor
    func testSpaceLifecycleMovesTabsToPreviousSpace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let previous = app.spaces.last!.id
        let space = app.createSpace(name: "Writing")
        let tab = try XCTUnwrap(app.activeTab)
        XCTAssertEqual(tab.spaceID, space)
        app.renameSpace(space, name: "Drafts")
        XCTAssertEqual(app.activeSpace.name, "Drafts")
        app.deleteSpace(space)
        XCTAssertEqual(tab.spaceID, previous)
        XCTAssertFalse(app.spaces.contains { $0.id == space })
        while app.spaces.count > 1 { app.deleteSpace(app.spaces.last!.id) }
        app.deleteSpace(app.spaces[0].id)
        XCTAssertEqual(app.spaces.count, 1)
    }
}
