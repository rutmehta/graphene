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
        isDiscarded = true; isLoading = false
    }
    weak var coordinator: BrowserCoordinator?

    @Published var title: String = "New Tab"
    @Published var url: URL?
    @Published var isLoading = false
    @Published var progress: Double = 0
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

    init(engine: WebEngine, id: UUID = UUID(), privateMode: Bool = false) {
        isPrivate = privateMode
        self.id = id
        self.retainedEngine = engine
        engine.delegate = self
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

    func engineDidStartNavigation(_ engine: WebEngine, url: URL?) { loadError = nil; isLoading = true }

    func engineDidCommit(_ engine: WebEngine, url: URL?) {
        if let url { self.url = url }
    }

    func engineDidFinish(_ engine: WebEngine, url: URL?, title: String?) {
        isLoading = false
        if let title, !title.isEmpty { self.title = title }
        if let url {
            self.url = url
            if isRestoring { isRestoring = false }
            else { coordinator?.tab(self, didNavigateTo: url, title: title ?? engine.pageTitle) }
        }
    }

    func engine(_ engine: WebEngine, didFail error: Error) {
        isLoading = false
        if (error as NSError).code != NSURLErrorCancelled { loadError = error.localizedDescription }
    }

    func engineDidChangeState(_ engine: WebEngine) {
        articleDetected = (engine as? WKWebEngine)?.articleDetected ?? false
        signInBlocked = (engine as? WKWebEngine)?.signInBlocked ?? false
        canGoBack = engine.canGoBack
        canGoForward = engine.canGoForward
        progress = engine.estimatedProgress
        isLoading = engine.isLoading
        if let t = engine.pageTitle, !t.isEmpty { title = t }
        if let u = engine.currentURL { url = u }
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
