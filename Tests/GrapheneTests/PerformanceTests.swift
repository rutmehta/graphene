import XCTest
import AppKit
import Combine
@testable import Graphene

/// The interaction hot paths from docs/parity/perf-audit.md: what is polled, what stays loaded,
/// when thumbnails are taken, how often icons are fetched and how often views are told to redraw.
@MainActor
final class PerformanceTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDown() async throws {
        removeRoots()
        try await super.tearDown()
    }
    private func removeRoots() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
    }
    private func directory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        roots.append(root)
        return root
    }

    // MARK: media polling

    func testPollSetIsDisplayedAndAudibleTabsWithAPeriodicFullSweep() {
        let shown = UUID(), audible = UUID(), idle = [UUID(), UUID(), UUID()]
        let loaded = [shown, audible] + idle
        for tick in 1..<TabLifecycle.fullSweepPolls {
            XCTAssertEqual(TabLifecycle.pollSet(loaded: loaded, displayed: [shown], audible: [audible], tick: tick), [shown, audible],
                           "Tick \(tick) wakes only the page on screen and the audible one")
        }
        XCTAssertEqual(TabLifecycle.pollSet(loaded: loaded, displayed: [shown], audible: [audible], tick: TabLifecycle.fullSweepPolls), loaded)
        XCTAssertEqual(TabLifecycle.pollSet(loaded: idle, displayed: [shown], audible: [], tick: 1), [], "A displayed tab that is not loaded is not polled")
        XCTAssertGreaterThanOrEqual(TabLifecycle.pollInterval, 2)
    }

    func testPollNeverLoadsADiscardedTab() async throws {
        let app = AppState(directory: directory())
        let sleeping = app.newTab(activate: false)
        sleeping.url = URL(string: "https://example.com")
        sleeping.discard()
        for _ in 0..<TabLifecycle.fullSweepPolls { await app.pollMediaAndDiscard() }
        XCTAssertNil(sleeping.loadedEngine)
        XCTAssertTrue(sleeping.isDiscarded)
    }

    // MARK: LRU cap and memory pressure

    func testLRUVictimsKeepTheMostRecentAndSpareBusyTabs() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func resident(_ age: Double, displayed: Bool = false, playing: Bool = false, dirty: Bool = false, loading: Bool = false) -> TabLifecycle.Resident {
            TabLifecycle.Resident(id: UUID(), lastActive: now.addingTimeInterval(-age), displayed: displayed, playing: playing, dirty: dirty, loading: loading)
        }
        let shown = resident(10_000, displayed: true)
        let recent = (0..<3).map { resident(Double($0)) }
        let old = resident(500), oldest = resident(900), playing = resident(800, playing: true), dirty = resident(700, dirty: true), loading = resident(600, loading: true)
        let all = [shown, oldest, playing] + recent + [old, dirty, loading]
        XCTAssertEqual(Set(TabLifecycle.lruVictims(all, limit: 3)), [old.id, oldest.id],
                       "Beyond the three most recent background tabs, idle ones go; playing, dirty and loading tabs stay; the displayed tab never counts")
        XCTAssertEqual(TabLifecycle.lruVictims(all, limit: 20), [])
        XCTAssertEqual(TabLifecycle.lruVictims(recent + [old], limit: 3), [old.id])
        XCTAssertEqual(TabLifecycle.pressureLimit(critical: false, limit: 12), 6)
        XCTAssertEqual(TabLifecycle.pressureLimit(critical: true, limit: 12), 0)
        XCTAssertEqual(Settings().backgroundTabLimit, TabLifecycle.defaultBackgroundLimit)
        XCTAssertEqual(TabLifecycle.defaultBackgroundLimit, 12)
    }

    func testBackgroundCapDiscardsLeastRecentlyActiveTabs() async throws {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let app = AppState(directory: directory(), clock: { now })
        app.settings.backgroundTabLimit = 2
        var background: [Tab] = []
        for _ in 0..<4 {
            now.addTimeInterval(60)
            background.append(app.newTab(activate: false))
        }
        for (index, tab) in background.enumerated() { tab.lastActiveAt = now.addingTimeInterval(Double(index)) }
        let active = try XCTUnwrap(app.activeTab)
        XCTAssertEqual(Set(app.lruVictims(limit: 2).map(\.id)), [background[0].id, background[1].id])
        await app.discard(app.lruVictims(limit: 2), verified: [])
        XCTAssertNil(background[0].loadedEngine); XCTAssertNil(background[1].loadedEngine)
        XCTAssertNotNil(background[2].loadedEngine); XCTAssertNotNil(background[3].loadedEngine)
        XCTAssertNotNil(active.loadedEngine, "The selected tab is never discarded")

        await app.relieveMemoryPressure(critical: true)
        XCTAssertTrue(background.allSatisfy { $0.loadedEngine == nil }, "A critical memory event discards every idle background page")
        XCTAssertNotNil(active.loadedEngine)
    }

    func testDiscardedTabsStayDiscardedAcrossSpaceSwitchesAndRestore() throws {
        let root = directory()
        let first = AppState(directory: root)
        for (index, space) in first.spaces.enumerated() {
            for page in 0..<3 {
                let tab = first.newTab(activate: false)
                first.placeTab(tab.id, section: .today, spaceID: space.id)
                tab.url = URL(string: "https://example.com/\(index)/\(page)")
            }
        }
        first.persist()
        let restored = AppState(directory: root)
        XCTAssertTrue(restored.tabs.allSatisfy { $0.loadedEngine == nil }, "Restored session tabs start without a web view")
        restored.selectSpace(restored.spaces[1].id)
        restored.selectSpace(restored.spaces[0].id)
        XCTAssertTrue(restored.tabs.filter { $0.url != nil }.allSatisfy { $0.loadedEngine == nil },
                      "Switching spaces selects a tab but loads nothing until a page is shown")

        let closing = try XCTUnwrap(restored.tabs.first { $0.url != nil })
        restored.closeTab(closing.id, announce: false)
        restored.reopenClosedTab()
        let reopened = try XCTUnwrap(restored.activeTab)
        XCTAssertEqual(reopened.url, closing.url)
        XCTAssertNil(reopened.loadedEngine, "A reopened tab loads when its page is shown")
        XCTAssertTrue(reopened.isDiscarded)
    }

    // MARK: thumbnails

    func testThumbnailOncePerNavigationOfTheSelectedFinishedPage() {
        let url = URL(string: "https://example.com/a")!, next = URL(string: "https://example.com/b")!
        XCTAssertTrue(TabLifecycle.needsThumbnail(active: true, loaded: true, loading: false, isPrivate: false, url: url, captured: nil))
        XCTAssertFalse(TabLifecycle.needsThumbnail(active: true, loaded: true, loading: false, isPrivate: false, url: url, captured: url), "Already captured at this URL")
        XCTAssertTrue(TabLifecycle.needsThumbnail(active: true, loaded: true, loading: false, isPrivate: false, url: next, captured: url), "A new navigation")
        XCTAssertFalse(TabLifecycle.needsThumbnail(active: false, loaded: true, loading: false, isPrivate: false, url: url, captured: nil), "Background tab")
        XCTAssertFalse(TabLifecycle.needsThumbnail(active: true, loaded: false, loading: false, isPrivate: false, url: url, captured: nil), "Discarded tab")
        XCTAssertFalse(TabLifecycle.needsThumbnail(active: true, loaded: true, loading: true, isPrivate: false, url: url, captured: nil), "Still loading")
        XCTAssertFalse(TabLifecycle.needsThumbnail(active: true, loaded: true, loading: false, isPrivate: true, url: url, captured: nil))
        XCTAssertLessThanOrEqual(TabLifecycle.thumbnailWidth, 320)
        XCTAssertGreaterThan(TabLifecycle.thumbnailDelay, .zero)

        let cache = ThumbnailCache(capacity: 1)
        let a = UUID(), b = UUID(), image = NSImage(size: NSSize(width: 1, height: 1))
        cache.put(image, for: a, url: url)
        XCTAssertEqual(cache.capturedURL(a), url)
        cache.put(image, for: b, url: next)
        XCTAssertNil(cache.capturedURL(a), "Evicting an image forgets its URL, so the page is captured again")
    }

    func testSwitchingTabsTakesNoSnapshotSynchronously() {
        let app = AppState(directory: directory())
        let first = app.activeTab!, second = app.newTab()
        first.url = URL(string: "https://example.com/first"); second.url = URL(string: "https://example.com/second")
        for _ in 0..<5 { app.activate(first.id); app.activate(second.id) }
        XCTAssertNil(ThumbnailCache.shared.capturedURL(first.id))
        XCTAssertNil(ThumbnailCache.shared.capturedURL(second.id))
        XCTAssertNotNil(app.thumbnailTask, "A single delayed capture is scheduled for the selected tab")
    }

    // MARK: favicons

    func testFaviconFetchesOncePerOriginAndReusesTheDiskCache() async throws {
        let icons = directory()
        let tiff = try XCTUnwrap(NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in NSColor.black.setFill(); rect.fill(); return true }.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        final class Requests: @unchecked Sendable { var urls: [URL] = [] }
        let requested = Requests()
        let loader: (URL) async -> Data? = { url in
            await MainActor.run { requested.urls.append(url) }
            try? await Task.sleep(for: .milliseconds(50))
            return png
        }
        let store = FaviconStore(directory: icons, loader: loader)
        let page = URL(string: "https://example.com/some/page")!
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask { await store.fetch(URL(string: "https://example.com/row/\(index)")!) }
            }
        }
        XCTAssertEqual(store.downloads, 1, "Twenty rows of one origin fetch its icon once")
        XCTAssertNotNil(store.image(page: page, host: nil), "The shared fetch's icon is kept")

        let declared = [URL(string: "https://cdn.example.com/icon.png")!]
        let second = FaviconStore(directory: icons, loader: loader)
        await second.fetch(page, declared: declared)
        XCTAssertEqual(second.downloads, 1, "The declared icon differs from the cached one's source")
        let third = FaviconStore(directory: icons, loader: loader)
        await third.fetch(page, declared: declared)
        await third.fetch(page)
        XCTAssertEqual(third.downloads, 0, "A fresh disk entry from the same declared icon is reused")
        XCTAssertNotNil(third.image(page: page, host: nil))
        XCTAssertEqual(requested.urls.count, 2)
    }

    // MARK: publishing

    func testLoadProgressIsThrottledAndEdgesAlwaysPublish() async {
        var time: TimeInterval = 100
        let progress = LoadProgress(now: { time })
        var published = 0
        let observation = progress.objectWillChange.sink { published += 1 }
        progress.update(0.1, loading: true)
        XCTAssertEqual(progress.value, 0.1); XCTAssertTrue(progress.isLoading)
        let start = published
        for step in 1...50 { progress.update(0.1 + Double(step) / 100, loading: true) }
        XCTAssertEqual(published, start, "Fifty ticks within one frame interval publish nothing yet")
        time += 0.1
        progress.update(0.7, loading: true)
        XCTAssertEqual(progress.value, 0.7)
        progress.update(1, loading: false)
        XCTAssertEqual(progress.value, 1); XCTAssertFalse(progress.isLoading, "Completion publishes at once")
        progress.update(0.05, loading: true)
        XCTAssertEqual(progress.value, 0.05, "A new load publishes at once")

        progress.update(0.3, loading: true)
        XCTAssertEqual(progress.value, 0.05)
        time += 1
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(progress.value, 0.3, "The last throttled value is published when its interval ends")
        withExtendedLifetime(observation) {}
    }

    func testUnchangedEngineStateDoesNotRepublishTheTab() {
        let tab = Tab(engine: nil)
        let engine = WKWebEngine()
        var changes = 0
        let observation = tab.objectWillChange.sink { changes += 1 }
        tab.engineDidChangeState(engine)
        let first = changes
        for _ in 0..<20 { tab.engineDidChangeState(engine) }
        XCTAssertEqual(changes, first, "Repeated KVO callbacks with the same state publish nothing")
        withExtendedLifetime(observation) {}
    }

    func testRoutineStateChangesDoNotPublishTheShell() throws {
        let app = AppState(directory: directory())
        var changes = 0
        let observation = app.objectWillChange.sink { changes += 1 }
        app.persist(); app.persist()
        XCTAssertEqual(changes, 0, "A successful save publishes nothing")
        _ = app.newTab(activate: false)
        changes = 0
        app.cycleRecentTab(1); app.cycleRecentTab(1); app.cycleRecentTab(-1)
        XCTAssertEqual(changes, 0, "⌃Tab cycling redraws only the switcher")
        XCTAssertFalse(app.switcherIDs.isEmpty)
        app.switcherIDs = []

        let tab = try XCTUnwrap(app.activeTab)
        changes = 0
        tab.engineDidChangeState(WKWebEngine())
        tab.loading.update(0.5, loading: true)
        XCTAssertEqual(changes, 0, "Page progress and loading never go through AppState")

        app.toasts.enqueue(title: "Saved", seconds: 1)
        changes = 0
        app.toasts.expire(app.toasts.items[0].id)
        XCTAssertTrue(app.toasts.items.isEmpty)
        withExtendedLifetime(observation) {}
    }

    func testCommandTableAndThreadCheck() throws {
        let app = AppState(directory: directory())
        let table = CommandMenuTable(app.allCommandActions)
        XCTAssertEqual(table["reload"]?.title, "Reload")
        XCTAssertNil(table["no-such-command"])
        XCTAssertEqual(app.graph.hasThreads(spaceID: app.activeSpaceID), !app.graph.threads(spaceID: app.activeSpaceID).isEmpty)
        XCTAssertEqual(table["export"]?.enabled, false)
        app.graph.recordVisit(url: URL(string: "https://example.com")!, title: "Example", spaceID: app.activeSpaceID, parentNodeID: nil, query: nil)
        XCTAssertTrue(app.graph.hasThreads(spaceID: app.activeSpaceID))
        XCTAssertEqual(app.graph.hasThreads(spaceID: app.activeSpaceID), !app.graph.threads(spaceID: app.activeSpaceID).isEmpty)
        XCTAssertFalse(app.graph.hasThreads(spaceID: app.spaces[1].id))
        XCTAssertEqual(CommandMenuTable(app.allCommandActions)["export"]?.enabled, true)
    }

    func testProvenanceLayoutIsCachedAndNamesParents() {
        let app = AppState(directory: directory())
        let parent = app.activeTab!
        parent.url = URL(string: "https://example.com")
        app.openTab(url: URL(string: "https://example.com/child")!, parent: parent, activate: false)
        let layout = app.todayProvenance()
        XCTAssertEqual(layout, app.todayProvenance())
        XCTAssertEqual(layout.parentIDs, [parent.id])
        XCTAssertEqual(layout.parentIDs.contains(parent.id), !app.branchChildren(of: parent.id).isEmpty)
        app.setBranch(parent.id, collapsed: true)
        XCTAssertEqual(app.todayProvenance().rows.count, 1, "A collapse changes the cache key")
    }
}
