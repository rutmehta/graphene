import XCTest
@testable import Graphene

final class LifecycleTests: XCTestCase {
    @MainActor
    func testRestoredBackgroundTabsStayUnloadedAndMigrationBacksUp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = Data("{\"tabs\":[{\"pinned\":false,\"url\":\"https://example.com\"},{\"pinned\":true,\"url\":\"https://swift.org\"}],\"activeIndex\":0}".utf8)
        let file = directory.appendingPathComponent("session.json")
        try legacy.write(to: file)
        let app = AppState(directory: directory)
        XCTAssertNil(app.tabs[1].loadedEngine)
        XCTAssertTrue(app.graph.visits.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("v1.backup")), legacy)
        app.persist(); app.flushSaves()
        XCTAssertEqual(try JSONDecoder().decode(AppState.SessionData.self, from: Data(contentsOf: file)).version, 2)
    }

    @MainActor
    func testSettingsSharedAndMovingTabSeparatesSplit() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let first = app.activeTab!, second = app.newTab()
        app.activate(first.id); app.openSplit(second.id)
        let other = AppState(sharing: app)
        other.archiveHours = 168
        XCTAssertEqual(app.archiveHours, 168)
        app.placeTab(second.id, section: .today, spaceID: app.spaces.last!.id)
        XCTAssertTrue(app.splits.isEmpty)
    }

    @MainActor
    func testSidebarRangeAndToggleSelection() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let a = app.activeTab!, b = app.newTab(), c = app.newTab()
        app.selectSidebarTab(a.id, extend: false, toggle: false)
        app.selectSidebarTab(c.id, extend: true, toggle: false)
        XCTAssertEqual(app.selectedTabIDs, Set([a.id, b.id, c.id]))
        app.selectSidebarTab(b.id, extend: false, toggle: true)
        XCTAssertEqual(app.selectedTabIDs, Set([a.id, c.id]))
    }

    @MainActor
    func testDownloadHistoryRoundTripAndInterruptedState() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = DownloadStore(file: file)
        let id = store.begin(URL(fileURLWithPath: "/tmp/example.txt"))
        store.update(id, progress: 0.5)
        let interrupted = DownloadStore(file: file)
        XCTAssertEqual(interrupted.entries.first?.status, .interrupted)
        store.finish(id, error: nil)
        XCTAssertEqual(DownloadStore(file: file).entries.first?.status, .finished)
        store.clear()
        XCTAssertTrue(DownloadStore(file: file).entries.isEmpty)
    }

    func testDialogLoopGuardIsOriginScopedAndExpires() {
        var guardrail = DialogGuard()
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(guardrail.record("https://example.com", at: now))
        XCTAssertFalse(guardrail.record("https://example.com", at: now))
        XCTAssertFalse(guardrail.record("https://example.com", at: now))
        XCTAssertTrue(guardrail.record("https://example.com", at: now))
        XCTAssertFalse(guardrail.record("https://other.example", at: now))
        XCTAssertFalse(guardrail.record("https://example.com", at: now.addingTimeInterval(11)))
    }

    @MainActor
    func testCaptureExclusionPauseAndForget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let tab = app.activeTab!
        let url = URL(string: "https://sub.example.com/page")!
        tab.url = url
        app.excludedHosts = ["example.com"]
        app.tab(tab, didNavigateTo: url, title: "Excluded")
        XCTAssertTrue(app.graph.nodes.isEmpty)
        app.excludedHosts = []
        app.pausedSpaces = [app.activeSpaceID]
        app.tab(tab, didNavigateTo: url, title: "Paused")
        XCTAssertTrue(app.graph.nodes.isEmpty)
        app.pausedSpaces = []
        app.tab(tab, didNavigateTo: url, title: "Captured")
        XCTAssertEqual(app.siteCaptureCount("example.com"), 1)
        app.forgetSite("example.com")
        XCTAssertTrue(app.graph.nodes.isEmpty)
        XCTAssertNil(tab.currentNodeID)
        app.persist()
        XCTAssertEqual(AppState(directory: directory).excludedHosts, ["example.com"])
    }

    @MainActor
    func testPrivateStateWritesNothing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory, privateMode: true)
        let tab = app.activeTab!
        tab.url = URL(string: "https://example.com/private")
        app.tab(tab, didNavigateTo: tab.url!, title: "Private")
        app.tab(tab, didCapture: CapturedAnnotation(text: "secret", note: "", url: tab.url, title: "Private", context: ""))
        app.vault.add(text: "secret", note: "", url: tab.url, title: "Private", context: "")
        app.closeTab(tab.id); app.persist(); app.graph.save()
        XCTAssertTrue(app.graph.nodes.isEmpty)
        XCTAssertTrue(app.vault.annotations.isEmpty)
        XCTAssertTrue(app.archivedTabs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    func testWindowSelectionIndependentWithSharedTabs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = AppState(directory: directory)
        let second = AppState(sharing: first)
        let a = first.activeTab!
        let b = second.newTab()
        XCTAssertEqual(first.activeTabID, a.id)
        XCTAssertEqual(second.activeTabID, b.id)
        XCTAssertTrue(first.tabs.contains { $0.id == b.id })
        second.selectSpace(second.spaces.last!.id)
        XCTAssertNotEqual(first.activeSpaceID, second.activeSpaceID)
        first.closeTab(b.id)
        XCTAssertFalse(second.tabs.contains { $0.id == b.id })
    }

    func testDiscardProtectionAndThreshold() {
        let now = Date(timeIntervalSince1970: 10000)
        XCTAssertTrue(TabLifecycle.canDiscard(lastActive: now.addingTimeInterval(-1801), now: now, minutes: 30, protected: false, playing: false, downloading: false, dirty: false))
        for flags in [(true, false, false, false), (false, true, false, false), (false, false, true, false), (false, false, false, true)] {
            XCTAssertFalse(TabLifecycle.canDiscard(lastActive: now.addingTimeInterval(-1801), now: now, minutes: 30, protected: flags.0, playing: flags.1, downloading: flags.2, dirty: flags.3))
        }
        XCTAssertFalse(TabLifecycle.canDiscard(lastActive: now, now: now, minutes: 30, protected: false, playing: false, downloading: false, dirty: false))
    }

    func testExternalURLRoutingRejectsNonWebSchemes() {
        XCTAssertEqual(ExternalLinkPolicy.destination(URL(string: "https://example.com")!, littleEnabled: true), .little)
        XCTAssertEqual(ExternalLinkPolicy.destination(URL(string: "http://example.com")!, littleEnabled: false), .tab)
        XCTAssertNil(ExternalLinkPolicy.destination(URL(string: "file:///etc/passwd")!, littleEnabled: true))
        XCTAssertNil(ExternalLinkPolicy.destination(URL(string: "javascript:alert(1)")!, littleEnabled: true))
    }

    @MainActor
    func testSplitPersistenceAndClosePane() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let first = app.activeTab!
        let second = app.newTab()
        app.activate(first.id)
        app.openSplit(second.id)
        XCTAssertEqual(app.activeSplit?.tabIDs, [first.id, second.id])
        app.persist()
        let restored = AppState(directory: directory)
        XCTAssertEqual(restored.activeSplit?.tabIDs, [first.id, second.id])
        XCTAssertEqual(restored.splits, app.splits)
        restored.closeTab(second.id)
        XCTAssertNil(restored.activeSplit)
        XCTAssertEqual(restored.activeTabID, first.id)
    }

    @MainActor
    func testMRUOrderAndSelectionOnRelease() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let first = app.activeTab!
        let second = app.newTab()
        let third = app.newTab()
        app.activate(first.id)
        XCTAssertEqual(app.recentTabs.map(\.id), [first.id, third.id, second.id])
        app.cycleRecentTab(1)
        XCTAssertEqual(app.activeTabID, first.id)
        XCTAssertEqual(app.switcherIDs[app.switcherIndex], third.id)
        app.finishTabSwitch()
        XCTAssertEqual(app.activeTabID, third.id)
        XCTAssertEqual(app.recentTabs.map(\.id), [third.id, first.id, second.id])
    }

    @MainActor
    func testArchiveClockAndDurableRestore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_000_000)
        let app = AppState(directory: directory, clock: { now })
        let tab = try XCTUnwrap(app.activeTab)
        tab.url = URL(string: "https://example.com/base")
        app.pin(tab)
        tab.url = URL(string: "https://example.com/other")
        app.closeTab(tab.id)
        app.persist()
        let restored = AppState(directory: directory, clock: { now })
        restored.reopenClosedTab()
        XCTAssertEqual(restored.activeTab?.pinnedURL?.path, "/base")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("archive.json").path))
        app.reopenClosedTab()
        app.placeTab(app.activeTab!.id, section: .today)
        let idle = app.activeTab!
        _ = app.newTab()
        now.addTimeInterval(12 * 3600 - 1)
        app.archiveInactiveTabs()
        XCTAssertTrue(app.tabs.contains { $0.id == idle.id })
        now.addTimeInterval(1)
        app.archiveInactiveTabs()
        XCTAssertFalse(app.tabs.contains { $0.id == idle.id })
        XCTAssertEqual(app.archivedTabs.count, 1)
    }
}
