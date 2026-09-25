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

    // MARK: in-page citations (Resources/cite.js)

    /// Marks each passage's first exact (normalised) match in the page and returns the ids
    /// found. Marks with the same ids are replaced; other marks stay. Never marks an
    /// approximate match; private windows and `contenteditable` bodies return `[]`.
    func highlight(passages: [CitedPassage]) async -> [String]
    /// Raises the marks with `id` to `highlightActive`; `nil` clears the active state.
    func setActiveHighlight(_ id: String?) async
    /// Scrolls the first mark with `id` smoothly to the centre of the page.
    func scrollToHighlight(_ id: String) async
    /// Removes every citation mark from the page.
    func clearHighlights() async
}

/// A passage to mark in the page: `id` is the mark's `data-graphene-cite`; `index`, when
/// set, is drawn as the accent superscript before the mark (`data-graphene-index`).
struct CitedPassage: Equatable, Sendable {
    let id: String
    let text: String
    var index: Int? = nil

    /// The text `cite.js` searches for: whitespace runs collapsed to one space, trimmed,
    /// lowercased. Mirrors `normalize` in cite.js.
    var normalized: String { Self.normalized(text) }

    static func normalized(_ text: String) -> String {
        var out = ""
        var space = false
        for character in text {
            if character.isWhitespace { space = !out.isEmpty; continue }
            if space { out.append(" "); space = false }
            out.append(contentsOf: String(character).lowercased())
        }
        return out
    }

    /// Whether `cite.js` would mark this passage in a page whose text is `pageText`:
    /// a non-empty exact match after normalisation, nothing approximate.
    func matches(in pageText: String) -> Bool {
        let needle = normalized
        return !needle.isEmpty && Self.normalized(pageText).contains(needle)
    }
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
    /// The page's background turned dark or light (`Palette.pageIsDark`).
    func engine(_ engine: WebEngine, didChangePageDarkness dark: Bool)
    /// The pointer entered a citation mark (`id`) or left the last one (`nil`).
    func engine(_ engine: WebEngine, didHoverHighlight id: String?)
}

extension WebEngineDelegate {
    func engine(_ engine: WebEngine, didHoverHighlight id: String?) {}
}

/// Raw annotation payload coming up from the injected page script.
struct CapturedAnnotation {
    var text: String
    var note: String
    var url: URL?
    var title: String
    var context: String
}
