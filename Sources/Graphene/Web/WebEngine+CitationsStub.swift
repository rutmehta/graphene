import Foundation

// Stand-in for the G3 in-page citation API (`cite.js`). G3 declares these as `WebEngine`
// requirements and implements them in `WKWebEngine`; delete this file at merge.

/// A passage to find and mark in the page, keyed by the chat citation's stable id.
struct CitedPassage: Equatable, Sendable {
    let id: String
    let text: String
    /// The chip number drawn as the mark's superscript.
    var index: Int? = nil
}

extension WebEngine {
    /// Marks each passage found in the page; returns the ids that were found.
    func highlight(passages: [CitedPassage]) async -> [String] { [] }
    /// Raises one mark to the active state, or none.
    func setActiveHighlight(_ id: String?) async {}
    /// Scrolls the page to a mark.
    func scrollToHighlight(_ id: String) async {}
    /// Removes every citation mark from the page.
    func clearHighlights() async {}
}

extension WebEngineDelegate {
    /// The pointer entered (`id`) or left (`nil`) a citation mark in the page.
    func engine(_ engine: WebEngine, didHoverHighlight id: String?) {}
}
