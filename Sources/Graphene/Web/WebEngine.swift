import AppKit

/// Abstraction over the web rendering engine so the Chromium/CEF backend can
/// replace WKWebView later without touching the rest of Graphene. Everything
/// above this protocol is engine-agnostic.
@MainActor
protocol WebEngine: AnyObject {
    var hostView: NSView { get }
    var currentURL: URL? { get }
    var pageTitle: String? { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    var isLoading: Bool { get }
    var estimatedProgress: Double { get }
    var delegate: WebEngineDelegate? { get set }

    func load(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    func stop()
    @discardableResult
    func evaluateJavaScript(_ js: String) async -> Any?
    func captureSnapshotText() async -> String
    func captureReadableContent() async -> ReadableContent
    func find(_ text: String, backwards: Bool) async -> Bool
}

struct ReadableContent: Codable {
    var title = ""
    var text = ""
    var selection = ""
    var byline = ""
    var published = ""
    var headings: [String] = []
}
extension WebEngine {
    func captureReadableContent() async -> ReadableContent { ReadableContent(title: pageTitle ?? "", text: await captureSnapshotText()) }
}

/// Events the engine emits. All calls arrive on the main thread.
@MainActor
protocol WebEngineDelegate: AnyObject {
    func engineDidStartNavigation(_ engine: WebEngine, url: URL?)
    func engineDidCommit(_ engine: WebEngine, url: URL?)
    func engineDidFinish(_ engine: WebEngine, url: URL?, title: String?)
    func engine(_ engine: WebEngine, didFail error: Error)
    func engineDidChangeState(_ engine: WebEngine)
    func engine(_ engine: WebEngine, requestNewTabFor url: URL, activate: Bool)
    func engine(_ engine: WebEngine, didCaptureAnnotation annotation: CapturedAnnotation)
    func engine(_ engine: WebEngine, didCopyText text: String, url: URL?)
}

/// Raw annotation payload coming up from the injected page script.
struct CapturedAnnotation {
    var text: String
    var note: String
    var url: URL?
    var title: String
    var context: String
}
