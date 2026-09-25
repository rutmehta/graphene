import Foundation

/// Where `openSource` shows a page: a tab that already has it, the empty active tab,
/// or a new tab.
enum SourceTarget: Equatable {
    case existing(UUID)
    case reuseActive(UUID)
    case newTab

    struct Candidate {
        var id: UUID
        var url: URL?
        var spaceID: UUID?
    }

    /// A tab already showing `url` wins (the current space's first, then any space's);
    /// otherwise an empty active tab loads it; otherwise a new tab opens.
    @MainActor static func choose(url: URL, tabs: [Candidate], activeTabID: UUID?, spaceID: UUID?) -> SourceTarget {
        let key = KnowledgeGraph.canonicalURL(url.absoluteString)
        let showing = tabs.filter { $0.url.map { KnowledgeGraph.canonicalURL($0.absoluteString) } == key }
        if let match = showing.first(where: { $0.id == activeTabID }) ?? showing.first(where: { $0.spaceID == spaceID }) ?? showing.first {
            return .existing(match.id)
        }
        if let active = tabs.first(where: { $0.id == activeTabID }), active.url == nil { return .reuseActive(active.id) }
        return .newTab
    }
}

extension AppState {
    /// The `data-graphene-cite` id of the passage `openSource` marks.
    static let sourceHighlightID = "graphene-source"
    /// How long `openSource` waits for the page to finish loading, and how often it looks.
    static let sourceLoadTimeout: Duration = .seconds(20)
    static let sourcePollInterval: Duration = .milliseconds(250)
    /// Redirects end on another URL: once the page has been idle this long, highlight anyway.
    static let sourceRedirectGrace: Duration = .seconds(1)
    /// Late-rendering pages get a few more tries before the passage counts as missing.
    static let sourceHighlightAttempts = 4
    static let sourceHighlightRetry: Duration = .milliseconds(500)

    /// Opens `url` (switching to a tab that already shows it, loading it in an empty active
    /// tab, or opening a new tab), then, when `passage` is given, waits for the page and
    /// highlights and scrolls to its first exact match. Nothing is marked if the passage
    /// is not on the page. Vault rows, the Resume page and the Vault shelf call this.
    @discardableResult
    func openSource(url: URL, passage: String?) -> Tab? {
        let candidates = tabs.map { SourceTarget.Candidate(id: $0.id, url: $0.url, spaceID: $0.spaceID) }
        let tab: Tab?
        switch SourceTarget.choose(url: url, tabs: candidates, activeTabID: activeTabID, spaceID: activeSpaceID) {
        case .existing(let id):
            activate(id)
            tab = tabs.first { $0.id == id }
        case .reuseActive(let id):
            tab = tabs.first { $0.id == id }
            tab?.load(url)
            activate(id)
        case .newTab:
            openTab(url: url, parent: nil, activate: true)
            tab = activeTab
        }
        if let tab, let passage, !isPrivate, !CitedPassage.normalized(passage).isEmpty {
            Task { [weak self] in await self?.highlightSource(passage, in: tab, url: url) }
        }
        return tab
    }

    private func highlightSource(_ passage: String, in tab: Tab, url: URL) async {
        let key = KnowledgeGraph.canonicalURL(url.absoluteString)
        let clock = ContinuousClock(), start = clock.now
        while clock.now - start < Self.sourceLoadTimeout {
            guard tabs.contains(where: { $0 === tab }) else { return }
            let engine = tab.engine
            if !engine.isLoading, let current = engine.currentURL,
               KnowledgeGraph.canonicalURL(current.absoluteString) == key || clock.now - start >= Self.sourceRedirectGrace { break }
            try? await Task.sleep(for: Self.sourcePollInterval)
        }
        let cited = CitedPassage(id: Self.sourceHighlightID, text: passage)
        for attempt in 0..<Self.sourceHighlightAttempts {
            guard tabs.contains(where: { $0 === tab }), !tab.engine.isLoading else { return }
            if await tab.engine.highlight(passages: [cited]).contains(cited.id) {
                await tab.engine.setActiveHighlight(cited.id)
                await tab.engine.scrollToHighlight(cited.id)
                return
            }
            if attempt + 1 < Self.sourceHighlightAttempts { try? await Task.sleep(for: Self.sourceHighlightRetry) }
        }
    }
}
