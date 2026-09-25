import Foundation
import Combine

/// Coordinator the tabs call back into for graph capture and tab spawning.
/// AppState conforms to this.
@MainActor
protocol BrowserCoordinator: AnyObject {
    func tab(_ tab: Tab, didNavigateTo url: URL, title: String?)
    func tab(_ tab: Tab, didCapture annotation: CapturedAnnotation)
    func openTab(url: URL, parent: Tab?, activate: Bool)
}

/// A single browsing tab. Owns a WebEngine, mirrors its state for SwiftUI, and
/// forwards navigation into the knowledge graph via its coordinator.
@MainActor
final class Tab: ObservableObject, Identifiable, WebEngineDelegate {
    let id: UUID
    let isPrivate: Bool
    var profileID = Profile.defaultID
    private var retainedEngine: WebEngine?
    var loadedEngine: WebEngine? { retainedEngine }
    var configureEngine: ((WebEngine) -> Void)?
    @Published private(set) var isDiscarded = false
    var engine: WebEngine { acquireEngine(restoreURL: true) }
    private func acquireEngine(restoreURL: Bool) -> WebEngine {
        if let retainedEngine { return retainedEngine }
        let restored = WKWebEngine(privateMode: isPrivate, profileID: profileID)
        retainedEngine = restored; restored.delegate = self; configureEngine?(restored)
        isDiscarded = false
        if restoreURL, let url { isRestoring = true; restored.load(url) }
        return restored
    }
    func discard() {
        retainedEngine?.stop(); retainedEngine?.delegate = nil; retainedEngine = nil
        if !isDiscarded { isDiscarded = true }
        if isLoading { isLoading = false }
        loading.reset()
    }
    weak var coordinator: BrowserCoordinator?

    @Published var title: String = "New Tab"
    @Published var url: URL?
    @Published var isLoading = false
    /// The page's load progress, published on its own object so only the progress bar redraws
    /// while a page loads (not every view that observes the tab), at most `LoadProgress.maxRate` times a second.
    let loading = LoadProgress()
    var progress: Double { loading.value }
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var articleDetected = false
    @Published var signInBlocked = false
    @Published var isPinned = false
    @Published var isFavorite = false
    @Published var pinnedURL: URL?
    @Published var customTitle: String?
    @Published var folderID: UUID?
    @Published var isPlayingAudio = false
    /// Whether the loaded page is dark, as the engine last reported; `nil` until it does,
    /// in which case the page card follows the appearance.
    @Published var pageIsDark: Bool?
    var section: TabSection { isFavorite ? .favorites : (isPinned ? .pinned : .today) }

    var spaceID: UUID?
    var parentTabID: UUID?
    /// The search query (if any) that spawned this navigation — the "why."
    var originQuery: String?
    /// Graph node for the page currently shown.
    var currentNodeID: UUID?
    var currentThreadID: UUID?
    var isRestoring = false
    var resumeThreadID: UUID?
    @Published var loadError: String?
    let createdAt = Date()
    var lastActiveAt = Date()

    /// Without an `engine` the tab starts discarded: its page loads when it is first shown.
    init(engine: WebEngine?, id: UUID = UUID(), privateMode: Bool = false) {
        isPrivate = privateMode
        self.id = id
        self.retainedEngine = engine
        isDiscarded = engine == nil
        engine?.delegate = self
    }

    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if url == nil { return "New Tab" }
        return title.isEmpty ? (url?.host ?? "New Tab") : title
    }

    func load(_ url: URL) { self.url = url; acquireEngine(restoreURL: false).load(url) }
    func goBack() { engine.goBack() }
    func goForward() { engine.goForward() }
    func reload() { engine.reload() }
    func stop() { engine.stop() }

    // MARK: WebEngineDelegate

    func engineDidStartNavigation(_ engine: WebEngine, url: URL?) {
        if loadError != nil { loadError = nil }
        set(\.isLoading, true)
    }

    func engineDidCommit(_ engine: WebEngine, url: URL?) {
        if let url { set(\.url, url) }
    }

    func engine(_ engine: WebEngine, didHoverHighlight id: String?) { (coordinator as? AppState)?.citationMarkHovered(id, tabID: self.id) }
    func engineDidFinish(_ engine: WebEngine, url: URL?, title: String?) {
        set(\.isLoading, false)
        loading.update(1, loading: false)
        if let title, !title.isEmpty { set(\.title, title) }
        if let url {
            set(\.url, url)
            if isRestoring { isRestoring = false }
            else { coordinator?.tab(self, didNavigateTo: url, title: title ?? engine.pageTitle) }
        }
        (coordinator as? AppState)?.tabDidFinishLoad(self)
    }

    func engine(_ engine: WebEngine, didFail error: Error) {
        set(\.isLoading, false)
        loading.update(engine.estimatedProgress, loading: false)
        if (error as NSError).code != NSURLErrorCancelled { loadError = error.localizedDescription }
    }

    /// Called on every KVO change of the web view (progress ticks many times a load). Each
    /// property is published only when it changed; progress goes to `loading`, throttled.
    func engineDidChangeState(_ engine: WebEngine) {
        set(\.articleDetected, (engine as? WKWebEngine)?.articleDetected ?? false)
        set(\.signInBlocked, (engine as? WKWebEngine)?.signInBlocked ?? false)
        set(\.canGoBack, engine.canGoBack)
        set(\.canGoForward, engine.canGoForward)
        set(\.isLoading, engine.isLoading)
        loading.update(engine.estimatedProgress, loading: engine.isLoading)
        if let t = engine.pageTitle, !t.isEmpty { set(\.title, t) }
        if let u = engine.currentURL { set(\.url, u) }
    }

    /// Assigns a published property only when the value differs, so an unchanged value does
    /// not send `objectWillChange` to every view observing the tab.
    private func set<Value: Equatable>(_ key: ReferenceWritableKeyPath<Tab, Value>, _ value: Value) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    func engine(_ engine: WebEngine, requestNewTabFor url: URL, activate: Bool) {
        coordinator?.openTab(url: url, parent: self, activate: activate)
    }

    func engine(_ engine: WebEngine, didCaptureAnnotation annotation: CapturedAnnotation) {
        coordinator?.tab(self, didCapture: annotation)
    }

    func engine(_ engine: WebEngine, didChangePageDarkness dark: Bool) {
        if pageIsDark != dark { pageIsDark = dark }
    }

    func engine(_ engine: WebEngine, didCopyText text: String, url: URL?) {
        // Reserved for Phase 2 (quick-clip on copy).
    }
}

/// A tab's load progress for the progress bar. Publishes at most `maxRate` times a second
/// while loading; a change of `isLoading`, a restart (lower progress) and completion always
/// publish at once, and the latest throttled value is published when its interval ends.
@MainActor
final class LoadProgress: ObservableObject {
    static let maxRate: Double = 15
    @Published private(set) var value: Double = 0
    @Published private(set) var isLoading = false
    private var lastPublished: TimeInterval = -.infinity
    private var pending: Double?
    private var flush: Task<Void, Never>?
    private let now: () -> TimeInterval
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.now = now }

    func update(_ progress: Double, loading: Bool) {
        let time = now()
        let edge = loading != isLoading || progress < value || progress >= 1
        guard edge || time - lastPublished >= 1 / Self.maxRate else {
            pending = progress
            if flush == nil {
                let wait = max(0, 1 / Self.maxRate - (time - lastPublished))
                flush = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(wait))
                    guard let self, !Task.isCancelled else { return }
                    self.flush = nil
                    if let pending = self.pending { self.publish(pending, loading: self.isLoading, at: self.now()) }
                }
            }
            return
        }
        publish(progress, loading: loading, at: time)
    }

    func reset() {
        flush?.cancel(); flush = nil; pending = nil
        if value != 0 { value = 0 }
        if isLoading { isLoading = false }
    }

    private func publish(_ progress: Double, loading: Bool, at time: TimeInterval) {
        pending = nil; flush?.cancel(); flush = nil
        lastPublished = time
        if value != progress { value = progress }
        if isLoading != loading { isLoading = loading }
    }
}
