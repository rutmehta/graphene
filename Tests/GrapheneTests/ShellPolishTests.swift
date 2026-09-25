import XCTest
import AppKit
@testable import Graphene

final class ShellPolishTests: XCTestCase {
    func testFavoritesRespondToSidebarWidth() {
        XCTAssertEqual(ShellLayout.favoriteColumns(width: 224), 3)
        XCTAssertEqual(ShellLayout.favoriteColumns(width: 279), 3)
        XCTAssertEqual(ShellLayout.favoriteColumns(width: 280), 4)
        XCTAssertEqual(ShellLayout.favoriteHeight, 56)
        XCTAssertEqual(ShellLayout.favoriteGap, 8)
    }
    func testChatWidthClampsAndSkillsShareQuestionBuilder() {
        var settings = Settings()
        settings.askWidth = 100
        XCTAssertEqual(settings.askWidth, 360)
        settings.askWidth = 900
        XCTAssertEqual(settings.askWidth, 560)
        for skill in ChatSkill.defaults {
            XCTAssertEqual(PageContext.request(skill.trigger, sources: [], skills: ChatSkill.defaults), PageContext.request(skill.instructions, sources: [], skills: []))
        }
    }
    func testChatDefaultMatchesWideReferenceWithoutOverridingSavedWidth() throws {
        XCTAssertEqual(Settings().askWidth, 420)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Data("{\"panelWidth\":500}".utf8)).askWidth, 500)
    }

    @MainActor
    func testTidyCommandArchivesOnlyStaleTodayTabsInCurrentSpace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_000_000)
        let app = AppState(directory: directory, clock: { now })
        let stale = try XCTUnwrap(app.activeTab)
        stale.url = URL(string: "https://example.com/stale")
        let pin = app.newTab(); app.placeTab(pin.id, section: .pinned)
        let other = app.newTab(); app.placeTab(other.id, section: .today, spaceID: app.spaces[1].id)
        let playing = app.newTab(); playing.isPlayingAudio = true
        let selected = app.newTab()
        now.addTimeInterval(12 * 3600)
        let fresh = app.newTab(activate: false)
        try XCTUnwrap(app.commandActions.first { $0.id == "tidy-tabs" }).run()
        XCTAssertFalse(app.tabs.contains { $0.id == stale.id })
        for tab in [pin, other, playing, selected, fresh] { XCTAssertTrue(app.tabs.contains { $0.id == tab.id }) }
        app.persist()
        let archive = try JSONDecoder().decode([AppState.SessionTab].self, from: Data(contentsOf: directory.appendingPathComponent("archive.json")))
        XCTAssertTrue(archive.contains { $0.id == stale.id })
        app.archiveHours = 0
        now.addTimeInterval(24 * 3600)
        let count = app.tabs.count
        app.tidyToday()
        XCTAssertEqual(app.tabs.count, count)
    }

    @MainActor
    func testDownloadIndicatorExpiresButActiveTransfersRemainVisible() {
        let store = DownloadStore(file: nil)
        XCTAssertFalse(store.hasRecentActivity(at: Date()))
        let id = store.begin(URL(fileURLWithPath: "/tmp/graphene-download-test"))
        let started = store.entries[0].date
        XCTAssertTrue(store.hasRecentActivity(at: started.addingTimeInterval(48 * 3600)))
        store.finish(id, error: nil)
        XCTAssertTrue(store.hasRecentActivity(at: started.addingTimeInterval(60)))
        XCTAssertFalse(store.hasRecentActivity(at: started.addingTimeInterval(24 * 3600)))
        store.clear()
        XCTAssertFalse(store.hasRecentActivity(at: started))
    }

    @MainActor
    func testSidebarDensityAndTintFollowWP10Brief() throws {
        XCTAssertEqual(ShellLayout.rowHeight, 37)
        XCTAssertEqual(ShellLayout.rowPitch, 41)
        XCTAssertEqual(ShellLayout.pageRadius, 10)
        let color = try XCTUnwrap(NSColor(Palette(mode: .dark, space: .iris).sidebarBg).usingColorSpace(.sRGB))
        XCTAssertLessThan(color.brightnessComponent, 0.32)
        XCTAssertGreaterThan(color.saturationComponent, 0.25)
    }
}
