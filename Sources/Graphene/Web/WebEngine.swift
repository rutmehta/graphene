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

    /// The text `cite.js` searches for. Mirrors `normalize` in cite.js, code point for code
    /// point: bracketed markers ("[4]", "[citation needed]") are dropped, whitespace runs become
    /// one space kept only between two letters or digits (so "carbon.[4] It" and "carbon.It"
    /// agree), format characters vanish and the rest is lowercased.
    var normalized: String { Self.normalized(text) }

    /// Longest bracketed marker dropped, in code points between the brackets (`BRACKET_MAX`).
    static let bracketMaximum = 30
    /// Fewest words a partial match must span (`MIN_RUN`).
    static let minimumRunWords = 8

    static func normalized(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var pending = false
        var last: Unicode.Scalar?
        var i = 0
        while i < scalars.count {
            defer { i += 1 }
            let scalar = scalars[i]
            if scalar == "[", let close = bracketEnd(scalars, from: i) { i = close; continue }
            if isSpace(scalar) { pending = true; continue }
            if scalar.properties.generalCategory == .format { continue }
            if pending, let last, isWord(last), isWord(scalar) { out.append(" ") }
            pending = false
            for lower in String(scalar).lowercased().unicodeScalars { out.append(lower); last = lower }
        }
        return String(out)
    }
    /// The index of the "]" closing a droppable marker opened at `start`, else nil.
    private static func bracketEnd(_ scalars: [Unicode.Scalar], from start: Int) -> Int? {
        var j = start + 1, visible = false
        while j < scalars.count, j - start - 1 <= bracketMaximum, scalars[j] != "[", scalars[j] != "]" {
            if !isSpace(scalars[j]) { visible = true }
            j += 1
        }
        return j < scalars.count && scalars[j] == "]" && visible && j - start - 1 <= bracketMaximum ? j : nil
    }
    /// JavaScript's `\s` plus U+0085.
    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool { scalar.properties.isWhitespace || scalar == "\u{FEFF}" }
    /// JavaScript's `[\p{L}\p{N}]`.
    private static func isWord(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }

    /// What `cite.js` would mark for this passage in a page whose text is `pageText`: the passage
    /// when it matches whole after normalisation, else its longest run of at least
    /// `minimumRunWords` whole words that matches exactly (first on ties), else nil. Never an
    /// approximate match. Mirrors `locate` in cite.js.
    func matchingRun(in pageText: String) -> String? {
        let needle = normalized
        guard !needle.isEmpty else { return nil }
        let page = Self.normalized(pageText)
        if page.contains(needle) { return text }
        let words = text.split(whereSeparator: { $0.unicodeScalars.allSatisfy(Self.isSpace) }).map(String.init)
        var best: (run: String, count: Int)?
        var start = 0
        while start + Self.minimumRunWords <= words.count {
            if let best, words.count - start <= best.count { break }
            var end = start + max(Self.minimumRunWords, (best?.count ?? 0) + 1)
            while end <= words.count {
                let run = words[start..<end].joined(separator: " ")
                guard page.contains(Self.normalized(run)) else { break }
                best = (run, end - start)
                end += 1
            }
            start += 1
        }
        return best?.run
    }

    /// Whether `cite.js` would mark this passage (or a long enough run of it) in `pageText`.
    func matches(in pageText: String) -> Bool { matchingRun(in: pageText) != nil }
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
