import Foundation
import Combine
import AppKit

/// Top-level app state and the concrete `BrowserCoordinator`. Owns the tabs,
/// the knowledge graph, and the vault; routes navigation into the graph.
@MainActor
final class AppState: ObservableObject, BrowserCoordinator {
    static let shared = AppState()

    @Published var tabs: [Tab] = []
    @Published var activeTabID: UUID?
    @Published var showGraph = false
    @Published var showAnnotations = false
    @Published var searchEngine: SearchEngine = .google

    let graph = KnowledgeGraph()
    let vault = Vault()
    let defaultSpace = Space(name: "Home", accentHex: "#B4794F")

    private var saveWork: DispatchWorkItem?

    private init() {
        restoreSession()
        if tabs.isEmpty { _ = newTab(activate: true) }
    }

    var activeTab: Tab? { tabs.first { $0.id == activeTabID } }

    // MARK: tab management

    @discardableResult
    func newTab(activate: Bool = true) -> Tab {
        let tab = makeTab()
        tabs.append(tab)
        if activate { activeTabID = tab.id }
        persistSoon()
        return tab
    }

    private func makeTab() -> Tab {
        let tab = Tab(engine: WKWebEngine())
        tab.coordinator = self
        tab.spaceID = defaultSpace.id
        return tab
    }

    func closeTab(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if activeTabID == id {
            activeTabID = tabs[safe: idx]?.id ?? tabs.last?.id
        }
        if tabs.isEmpty { _ = newTab(activate: true) }
        persistSoon()
    }

    func activate(_ id: UUID) { activeTabID = id; persistSoon() }

    func selectRelativeTab(_ delta: Int) {
        guard let idx = tabs.firstIndex(where: { $0.id == activeTabID }), !tabs.isEmpty else { return }
        let next = (idx + delta + tabs.count) % tabs.count
        activeTabID = tabs[next].id
    }

    // MARK: navigation

    /// Submit omnibox text on the active tab (or a given tab). Records the search
    /// query so the resulting page carries the "why" behind it.
    func submit(_ input: String, on tab: Tab? = nil) {
        let target = tab ?? activeTab ?? newTab()
        guard let action = Omnibox.resolve(input, engine: searchEngine) else { return }
        switch action {
        case .navigate(let url):
            target.originQuery = nil
            target.load(url)
        case .search(let url, let query):
            target.originQuery = query
            target.load(url)
        }
    }

    func goBack() { activeTab?.goBack() }
    func goForward() { activeTab?.goForward() }
    func reload() { activeTab?.reload() }
    func stop() { activeTab?.stop() }

    // MARK: BrowserCoordinator

    func tab(_ tab: Tab, didNavigateTo url: URL, title: String?) {
        let node = graph.recordVisit(
            url: url, title: title,
            spaceID: tab.spaceID,
            parentNodeID: tab.currentNodeID,
            query: tab.originQuery
        )
        tab.currentNodeID = node
        tab.originQuery = nil
        persistSoon()
        Task { [weak self, weak tab] in
            guard let tab else { return }
            let text = await tab.engine.captureSnapshotText()
            self?.graph.attachText(nodeID: node, text: text)
            if let t = tab.engine.pageTitle, !t.isEmpty { self?.graph.setTitle(nodeID: node, title: t) }
        }
    }

    func tab(_ tab: Tab, didCapture annotation: CapturedAnnotation) {
        vault.add(text: annotation.text, note: annotation.note, url: annotation.url,
                  title: annotation.title, context: annotation.context)
        if let node = tab.currentNodeID { graph.bumpAnnotationCount(nodeID: node) }
    }

    func openTab(url: URL, parent: Tab?, activate: Bool) {
        let tab = makeTab()
        tab.parentTabID = parent?.id
        tab.currentNodeID = parent?.currentNodeID   // so the child's first page links from the parent's node
        if let idx = tabs.firstIndex(where: { $0.id == parent?.id }) {
            tabs.insert(tab, at: idx + 1)
        } else {
            tabs.append(tab)
        }
        if activate { activeTabID = tab.id }
        tab.load(url)
        persistSoon()
    }

    // MARK: session persistence

    private struct SessionTab: Codable { var url: String?; var pinned: Bool }
    private struct SessionData: Codable { var tabs: [SessionTab]; var activeIndex: Int }

    private func persistSoon() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func persist() {
        let data = SessionData(
            tabs: tabs.map { SessionTab(url: $0.url?.absoluteString, pinned: $0.isPinned) },
            activeIndex: tabs.firstIndex { $0.id == activeTabID } ?? 0
        )
        if let encoded = try? JSONEncoder().encode(data) { try? encoded.write(to: Paths.sessionFile) }
    }

    private func restoreSession() {
        guard let data = try? Data(contentsOf: Paths.sessionFile),
              let session = try? JSONDecoder().decode(SessionData.self, from: data),
              !session.tabs.isEmpty else { return }
        for st in session.tabs {
            let tab = makeTab()
            tab.isPinned = st.pinned
            tabs.append(tab)
            if let s = st.url, let url = URL(string: s) { tab.load(url) }
        }
        activeTabID = tabs[safe: session.activeIndex]?.id ?? tabs.first?.id
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
