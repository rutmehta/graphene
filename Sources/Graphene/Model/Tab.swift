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
    let id = UUID()
    let engine: WebEngine
    weak var coordinator: BrowserCoordinator?

    @Published var title: String = "New Tab"
    @Published var url: URL?
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isPinned = false

    var spaceID: UUID?
    var parentTabID: UUID?
    /// The search query (if any) that spawned this navigation — the "why."
    var originQuery: String?
    /// Graph node for the page currently shown.
    var currentNodeID: UUID?
    let createdAt = Date()

    init(engine: WebEngine) {
        self.engine = engine
        self.engine.delegate = self
    }

    var displayTitle: String {
        if url == nil { return "New Tab" }
        return title.isEmpty ? (url?.host ?? "New Tab") : title
    }

    func load(_ url: URL) { self.url = url; engine.load(url) }
    func goBack() { engine.goBack() }
    func goForward() { engine.goForward() }
    func reload() { engine.reload() }
    func stop() { engine.stop() }

    // MARK: WebEngineDelegate

    func engineDidStartNavigation(_ engine: WebEngine, url: URL?) { isLoading = true }

    func engineDidCommit(_ engine: WebEngine, url: URL?) {
        if let url { self.url = url }
    }

    func engineDidFinish(_ engine: WebEngine, url: URL?, title: String?) {
        isLoading = false
        if let title, !title.isEmpty { self.title = title }
        if let url {
            self.url = url
            coordinator?.tab(self, didNavigateTo: url, title: title ?? engine.pageTitle)
        }
    }

    func engineDidChangeState(_ engine: WebEngine) {
        canGoBack = engine.canGoBack
        canGoForward = engine.canGoForward
        progress = engine.estimatedProgress
        isLoading = engine.estimatedProgress > 0 && engine.estimatedProgress < 1
        if let t = engine.pageTitle, !t.isEmpty { title = t }
        if let u = engine.currentURL { url = u }
    }

    func engine(_ engine: WebEngine, requestNewTabFor url: URL, activate: Bool) {
        coordinator?.openTab(url: url, parent: self, activate: activate)
    }

    func engine(_ engine: WebEngine, didCaptureAnnotation annotation: CapturedAnnotation) {
        coordinator?.tab(self, didCapture: annotation)
    }

    func engine(_ engine: WebEngine, didCopyText text: String, url: URL?) {
        // Reserved for Phase 2 (quick-clip on copy).
    }
}
