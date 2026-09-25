import Foundation
import AppKit
import WebKit

enum TabLifecycle {
    static func canDiscard(lastActive: Date, now: Date, minutes: Double, protected: Bool, playing: Bool, downloading: Bool, dirty: Bool) -> Bool {
        minutes > 0 && now.timeIntervalSince(lastActive) > minutes * 60 && !protected && !playing && !downloading && !dirty
    }
}

extension AppState {
    func captureThumbnail(_ tab: Tab) {
        guard !isPrivate, !tab.isPrivate, let engine = tab.loadedEngine as? WKWebEngine, engine.webView.bounds.width > 0 else { return }
        let config = WKSnapshotConfiguration(); config.snapshotWidth = 300
        engine.webView.takeSnapshot(with: config) { [weak tab] image, _ in
            guard let tab, !tab.isPrivate, let image else { return }
            ThumbnailCache.shared.put(image, for: tab.id)
        }
    }

    func pollMediaAndDiscard() async {
        let protected = Set(library.states.flatMap { $0.recentTabs.prefix(10).map(\.id) }).union(displayedTabIDs)
        for tab in tabs {
            guard let engine = tab.loadedEngine as? WKWebEngine else { continue }
            let playing = await engine.evaluateJavaScript("Array.from(document.querySelectorAll('audio,video')).some(e => !e.paused && !e.ended && !e.muted && e.volume > 0)") as? Bool ?? false
            if tab.isPlayingAudio != playing { tab.isPlayingAudio = playing }
            if playing && mediaTabID != tab.id { mediaTabID = tab.id }
            if TabLifecycle.canDiscard(lastActive: tab.lastActiveAt, now: clock(), minutes: discardMinutes, protected: protected.contains(tab.id) || tab.id == activeTabID || engine.isLoading, playing: playing, downloading: engine.activeDownloads > 0, dirty: engine.formDirty) {
                tab.discard()
            }
        }

    }

    func toggleMedia(_ tab: Tab) {
        Task {
            await tab.engine.evaluateJavaScript("(() => { const media = Array.from(document.querySelectorAll('audio,video')); const playing = media.filter(e => !e.paused && !e.ended); if (playing.length) playing.forEach(e => e.pause()); else { const e = media.find(e => e.currentTime > 0) || media[0]; if (e) e.play(); } })()")
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
