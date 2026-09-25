import Foundation
import AppKit
import WebKit

enum TabLifecycle {
    static func canDiscard(lastActive: Date, now: Date, minutes: Double, protected: Bool, playing: Bool, downloading: Bool, dirty: Bool) -> Bool {
        minutes > 0 && now.timeIntervalSince(lastActive) > minutes * 60 && !protected && !playing && !downloading && !dirty
    }

    /// Loaded background pages kept by default before the least recently active are discarded.
    static let defaultBackgroundLimit = 12
    /// Seconds between media polls.
    static let pollInterval: TimeInterval = 2
    /// Every this many polls, every loaded tab is checked, so a background page that starts
    /// playing on its own still gets its speaker glyph (every 30 s rather than every 2 s).
    static let fullSweepPolls = 15

    /// The tabs whose pages are asked whether they play media on poll number `tick`: those on
    /// screen and those last known to be audible. Every `fullSweepPolls` polls, all of `loaded`.
    /// Asking a page wakes its WebContent process, so polling every loaded tab every 2 s kept
    /// every background process busy.
    static func pollSet(loaded: [UUID], displayed: Set<UUID>, audible: Set<UUID>, tick: Int) -> [UUID] {
        if tick % fullSweepPolls == 0 { return loaded }
        return loaded.filter { displayed.contains($0) || audible.contains($0) }
    }

    /// A loaded tab as the LRU cap sees it.
    struct Resident: Equatable {
        var id: UUID
        var lastActive: Date
        /// On screen in some window.
        var displayed = false
        var playing = false
        var downloading = false
        var dirty = false
        var loading = false
        var evictable: Bool { !displayed && !playing && !downloading && !dirty && !loading }
    }

    /// Loaded background tabs to discard so at most `limit` stay loaded, least recently active
    /// first. Tabs on screen never count; tabs that are playing, downloading, loading or hold
    /// unsaved form input are kept even beyond the limit.
    static func lruVictims(_ residents: [Resident], limit: Int) -> [UUID] {
        let background = residents.filter { !$0.displayed }
        guard background.count > max(0, limit) else { return [] }
        return background.sorted { $0.lastActive > $1.lastActive }
            .dropFirst(max(0, limit)).filter(\.evictable).map(\.id)
    }

    /// How many background pages survive a memory-pressure event: half the cap on a warning,
    /// none on a critical event.
    static func pressureLimit(critical: Bool, limit: Int) -> Int { critical ? 0 : max(0, limit) / 2 }

    /// Whether a thumbnail should be taken of a tab's page now: once per navigation (a URL not
    /// already captured), only of the selected, finished, loaded page, never of private pages.
    static func needsThumbnail(active: Bool, loaded: Bool, loading: Bool, isPrivate: Bool, url: URL?, captured: URL?) -> Bool {
        active && loaded && !loading && !isPrivate && url != nil && url != captured
    }
    /// A thumbnail waits this long after a switch or a load, so it never competes with the
    /// switch itself.
    static let thumbnailDelay: Duration = .milliseconds(800)
    /// Snapshot width in points (the ⌃Tab tile is 96pt, the hover preview 236pt).
    static let thumbnailWidth: CGFloat = 240

    static let mediaProbe = "Array.from(document.querySelectorAll('audio,video')).some(e => !e.paused && !e.ended && !e.muted && e.volume > 0)"
}

extension AppState {
    /// Schedules a thumbnail of `tab`'s page after `TabLifecycle.thumbnailDelay`, when it is
    /// still selected and the page has not been captured at its current URL.
    func scheduleThumbnail(_ tab: Tab) {
        guard !isPrivate, !tab.isPrivate else { return }
        thumbnailTask?.cancel()
        thumbnailTask = Task { [weak self, weak tab] in
            try? await Task.sleep(for: TabLifecycle.thumbnailDelay)
            guard !Task.isCancelled, let self, let tab else { return }
            self.captureThumbnail(tab)
        }
    }

    func captureThumbnail(_ tab: Tab) {
        guard let engine = tab.loadedEngine as? WKWebEngine,
              TabLifecycle.needsThumbnail(active: displayedTabIDs.contains(tab.id), loaded: true, loading: engine.isLoading,
                                          isPrivate: isPrivate || tab.isPrivate, url: tab.url, captured: ThumbnailCache.shared.capturedURL(tab.id)),
              engine.webView.bounds.width > 0, engine.webView.window != nil, let url = tab.url else { return }
        let config = WKSnapshotConfiguration(); config.snapshotWidth = NSNumber(value: Double(TabLifecycle.thumbnailWidth))
        ThumbnailCache.shared.markCaptured(url, for: tab.id)
        engine.webView.takeSnapshot(with: config) { [weak tab] image, _ in
            MainActor.assumeIsolated {
                guard let tab, !tab.isPrivate else { return }
                guard let image else { ThumbnailCache.shared.forgetCapture(tab.id); return }
                ThumbnailCache.shared.put(image, for: tab.id, url: url)
            }
        }
    }

    func pollMediaAndDiscard() async {
        mediaPolls &+= 1
        let displayed = displayedTabIDs
        let loaded = tabs.filter { $0.loadedEngine is WKWebEngine }
        let audible = Set(loaded.filter(\.isPlayingAudio).map(\.id))
        let polled = Set(TabLifecycle.pollSet(loaded: loaded.map(\.id), displayed: displayed, audible: audible, tick: mediaPolls))
        let protected = Set(library.states.flatMap { $0.recentTabs.prefix(10).map(\.id) }).union(displayed)
        for tab in loaded where polled.contains(tab.id) {
            guard let engine = tab.loadedEngine as? WKWebEngine else { continue }
            let playing = await engine.evaluateJavaScript(TabLifecycle.mediaProbe) as? Bool ?? false
            if tab.isPlayingAudio != playing { tab.isPlayingAudio = playing }
            if playing && mediaTabID != tab.id { mediaTabID = tab.id }
        }
        var victims: [Tab] = []
        for tab in loaded {
            guard let engine = tab.loadedEngine as? WKWebEngine else { continue }
            if TabLifecycle.canDiscard(lastActive: tab.lastActiveAt, now: clock(), minutes: discardMinutes, protected: protected.contains(tab.id) || tab.id == activeTabID || engine.isLoading, playing: tab.isPlayingAudio, downloading: engine.activeDownloads > 0, dirty: engine.formDirty) {
                victims.append(tab)
            }
        }
        let chosen = Set(victims.map(\.id))
        victims += lruVictims(limit: settings.backgroundTabLimit).filter { !chosen.contains($0.id) }
        await discard(victims, verified: polled)
    }

    /// The loaded background tabs beyond `limit`, least recently active first (`TabLifecycle.lruVictims`).
    func lruVictims(limit: Int) -> [Tab] {
        let displayed = displayedTabIDs
        let residents = tabs.compactMap { tab -> TabLifecycle.Resident? in
            guard let engine = tab.loadedEngine as? WKWebEngine else { return nil }
            return TabLifecycle.Resident(id: tab.id, lastActive: tab.lastActiveAt, displayed: displayed.contains(tab.id) || tab.id == activeTabID,
                                         playing: tab.isPlayingAudio, downloading: engine.activeDownloads > 0, dirty: engine.formDirty, loading: engine.isLoading)
        }
        let ids = TabLifecycle.lruVictims(residents, limit: limit)
        return ids.compactMap { id in tabs.first { $0.id == id } }
    }

    /// Discards `victims`. A page not asked this poll (`verified`) is asked once whether it
    /// plays media first, so a page that started playing in the background keeps playing.
    func discard(_ victims: [Tab], verified: Set<UUID>) async {
        for tab in victims {
            guard let engine = tab.loadedEngine as? WKWebEngine, !displayedTabIDs.contains(tab.id) else { continue }
            if !verified.contains(tab.id) {
                let playing = await engine.evaluateJavaScript(TabLifecycle.mediaProbe) as? Bool ?? false
                if tab.isPlayingAudio != playing { tab.isPlayingAudio = playing }
                if playing { continue }
            }
            guard tab.loadedEngine === engine, !displayedTabIDs.contains(tab.id), !tab.isPlayingAudio else { continue }
            tab.discard()
        }
    }

    /// The system is short of memory: discard least recently active background pages down to
    /// half the cap (warning) or all of them (critical).
    func relieveMemoryPressure(critical: Bool) async {
        let limit = TabLifecycle.pressureLimit(critical: critical, limit: settings.backgroundTabLimit)
        await discard(lruVictims(limit: limit), verified: [])
    }

    func startMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.relieveMemoryPressure(critical: event.contains(.critical)) }
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    func toggleMedia(_ tab: Tab) {
        guard let engine = tab.loadedEngine else { return }
        Task {
            await engine.evaluateJavaScript("(() => { const media = Array.from(document.querySelectorAll('audio,video')); const playing = media.filter(e => !e.paused && !e.ended); if (playing.length) playing.forEach(e => e.pause()); else { const e = media.find(e => e.currentTime > 0) || media[0]; if (e) e.play(); } })()")
            await pollMediaAndDiscard()
        }
    }
    func enterPictureInPicture() {
        guard let tab = activeTab else { return }
        Task {
            let result = await tab.engine.evaluateJavaScript("window.__graphenePiP?.()")
            notify(result as? Bool == true ? "Click Open Picture in Picture on the page to authorize playback." : "No playing video was found on this page.")
        }
    }
}
