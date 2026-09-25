import Foundation
import Combine
import AppKit

/// Top-level app state and the concrete `BrowserCoordinator`. Owns the tabs,
/// the knowledge graph, and the vault; routes navigation into the graph.
@MainActor
final class AppState: ObservableObject, BrowserCoordinator {
    static let shared = AppState()

    let library: BrowserLibrary
    let isPrivate: Bool
    var settings: Settings { get { library.settings } set { library.settings = newValue; persistSoon() } }
    var dataDirectory: URL { sessionFile.deletingLastPathComponent() }
    var profiles: [Profile] { get { library.profiles } set { library.profiles = newValue } }
    var exportedSettings: Settings {
        var copy = settings
        copy.layout = layout; copy.appearance = mode; copy.searchEngine = searchEngine
        copy.suggestions = searchSuggestions; copy.archiveHours = archiveHours; copy.discardMinutes = discardMinutes
        copy.spaces = spaces; copy.excludedHosts = excludedHosts
        return copy
    }
    func importSettings(_ imported: Settings) {
        settings = imported
        if let value = imported.layout { layout = value }
        if let value = imported.appearance { mode = value }
        if let value = imported.searchEngine { searchEngine = value }
        if let value = imported.suggestions { searchSuggestions = value }
        if let value = imported.archiveHours { archiveHours = max(0, value) }
        if let value = imported.discardMinutes { discardMinutes = max(0, value) }
        if let value = imported.excludedHosts { excludedHosts = value }
        for space in imported.spaces ?? [] {
            if let index = spaces.firstIndex(where: { $0.id == space.id }) { spaces[index] = space }
            else { spaces.append(space) }
        }
        persist()
    }
    @Published var onboardingPresented = false
    @Published var settingsPage = "General"
    @Published private(set) var settingsError: String?
    private var canPersistSettings = true
    var tabs: [Tab] { get { library.tabs } set { library.tabs = newValue } }
    @Published var activeTabID: UUID? {
        didSet {
            if oldValue != activeTabID, let old = tabs.first(where: { $0.id == oldValue }) { old.lastActiveAt = clock(); captureThumbnail(old) }
            if let id = activeTabID {
                claimTab(id)
                recentIDs.removeAll { $0 == id }; recentIDs.insert(id, at: 0)
                if !collapsedBranchIDs.isEmpty { revealInBranch(id) }
                tabs.first { $0.id == id }?.lastActiveAt = clock()
            }
        }
    }
    private var recentIDs: [UUID] = []
    @Published var switcherIDs: [UUID] = []
    @Published var switcherIndex = 0
    var recentTabs: [Tab] {
        let ordered = recentIDs.compactMap { id in tabs.first { $0.id == id } }
        return ordered + tabs.filter { !recentIDs.contains($0.id) }
    }

    func cycleRecentTab(_ delta: Int) {
        if switcherIDs.isEmpty { switcherIDs = recentTabs.map(\.id); switcherIndex = 0 }
        guard !switcherIDs.isEmpty else { return }
        switcherIndex = (switcherIndex + delta + switcherIDs.count) % switcherIDs.count
    }
    func finishTabSwitch() {
        let id = switcherIDs[safe: switcherIndex]
        switcherIDs = []
        if let id { activate(id) }
    }
    func selectNumberedTab(_ number: Int) {
        if let tab = number == 9 ? visibleTabs.last : visibleTabs[safe: number - 1] { activate(tab.id) }
    }
    @Published var activeSurface: Surface = .web
    @Published var sidebarWidth: CGFloat = ShellLayout.sidebarDefault
    @Published var sidebarWidths: [String: Double] = [:]
    var focusedWindowID: String?
    @Published var sidebarCollapsed = false
    @Published var mode: ThemeMode = .light
    var spaces: [SpaceInfo] { get { library.spaces } set { library.spaces = newValue } }
    @Published var activeSpaceID: UUID = UUID()
    @Published var searchEngine: SearchEngine = .google
    var layout: BrowserLayout { get { library.layout } set { library.layout = newValue; persistSoon() } }
    var searchSuggestions: Bool { get { library.searchSuggestions } set { library.searchSuggestions = newValue; persistSoon() } }
    @Published var settingsPresented = false
    @Published var addressFocusRequest = 0
    @Published var vaultSelectionID: UUID?
    @Published var downloadsPresented = false
    @Published var readerPresented = false
    @Published var readerText = ""
    @Published var readerArticle: ReaderArticle?
    @Published var askRequest: AskRequest?
    @Published var commandContextIDs: [UUID] = []
    @Published var attachedSources: [KnowledgeSource] = []

    let graph: KnowledgeGraph
    let vault: Vault
    let downloads: DownloadStore
    let boards: BoardStore
    let sites: SiteSettings
    let boosts: Boosts
    @Published var boostHost: String?
    @Published var siteControlsTabID: UUID?
    private let sessionFile: URL
    private let archiveFile: URL
    let clock: () -> Date
    private var lifecycleTimer: Timer?
    @Published var archivePresented = false
    /// The sidebar footer's Library popover.
    @Published var libraryPresented = false
    @Published var peekTab: Tab?
    var hoveredTabID: UUID?
    @Published var selectedTabIDs: Set<UUID> = []
    var selectionAnchor: UUID?
    var littleEnabled: Bool { get { library.littleEnabled } set { library.littleEnabled = newValue; persistSoon() } }
    var littlePinnedLinks: Bool { get { library.littlePinnedLinks } set { library.littlePinnedLinks = newValue; persistSoon() } }
    var discardMinutes: Double { get { library.discardMinutes } set { library.discardMinutes = newValue; persistSoon() } }

    @Published var mediaTabID: UUID?
    private var mediaTimer: Timer?
    private var pollingMedia = false
    var archiveHours: Double { get { library.archiveHours } set { library.archiveHours = newValue; persistSoon() } }

    /// The current space (its color drives the whole palette, Arc-style).
    var activeSpace: SpaceInfo { spaces.first { $0.id == activeSpaceID } ?? spaces[0] }
    /// The resolved color system for the current mode + space.
    var pal: Palette { Palette(mode: mode, space: activeSpace.color, theme: activeSpace.theme, neutralChrome: layout == .topTabs) }
    @Published var spaceEditorPresented = false
    @Published var sidebarPeek = false

    @Published var commandBarFocusRequest = 0
    @Published var commandBarPresented = false
    @Published var commandBarCreatesTab = true
    @Published var commandBarDraft = ""
    /// Bumped when a Resume page should take the keyboard (a new blank tab from "+ New Tab").
    @Published var resumeFocusRequest = 0
    private var pendingNewTabDraft = ""
    /// Keys typed on the Resume page after the first opened the command bar, before its field took
    /// focus; `nil` when not buffering (see `resumeTyped`).
    var resumeKeyBuffer: String?
    private var lastActiveTabs: [UUID: UUID] = [:]
    var archivedTabs: [SessionTab] { get { library.archivedTabs } set { library.archivedTabs = newValue } }
    var folders: [TabFolder] { get { library.folders } set { library.folders = newValue } }
    var splits: [TabSplit] { get { library.splits } set { library.splits = newValue } }
    var excludedHosts: Set<String> { get { library.excludedHosts } set { library.excludedHosts = newValue } }
    var pausedSpaces: Set<UUID> { get { library.pausedSpaces } set { library.pausedSpaces = newValue } }
    @Published var knowledgeThreadID: UUID?
    @Published var knowledgeSearchPresented = false { didSet { if !knowledgeSearchPresented { citations.clear() } } }
    /// Links the latest Ask answer to marks in a page (D6 G4); cleared on close and navigation.
    let citations = CitationLinker()
    @Published var noteDrafts: [UUID: String] = [:]
    /// ⌘D and the toolbar's Save: with text selected in the page, the selection is saved as a
    /// note and marked in place (graphene-language.md §5.3); otherwise the composer opens.
    @Published var noteComposerPresented = false {
        didSet {
            guard noteComposerPresented, !oldValue, !composingPage, !isPrivate, activeSurface == .web,
                  let engine = activeTab?.loadedEngine as? WKWebEngine else { return }
            noteComposerPresented = false
            Task { [weak self] in
                guard await !engine.saveSelection(), let self else { return }
                self.composingPage = true
                self.noteComposerPresented = true
                self.composingPage = false
            }
        }
    }
    /// Set while the composer opens after the page had no selection to save.
    private var composingPage = false
    @Published var findPresented = false
    @Published var findQuery = ""
    @Published var findRequest = 0
    var findBackwards = false
    @Published var toasts = ToastQueue()
    @Published var selectedThreadID: UUID?
    /// Today branches collapsed with ⌥← (per window, not persisted).
    @Published var collapsedBranchIDs: Set<UUID> = []
    private var subscriptions = Set<AnyCancellable>()

    @Published private(set) var sessionError: String?
    private var canPersistSession = true
    private var saveWork: DispatchWorkItem?

    init(directory: URL? = nil, clock: @escaping () -> Date = Date.init, sharing owner: AppState? = nil, privateMode: Bool = false) {
        isPrivate = privateMode || owner?.isPrivate == true
        let root = owner?.sessionFile.deletingLastPathComponent() ?? directory ?? (isPrivate ? FileManager.default.temporaryDirectory.appendingPathComponent("Graphene-private-\(UUID())") : Paths.root)
        library = owner?.library ?? BrowserLibrary()
        self.clock = clock
        archiveFile = root.appendingPathComponent("archive.json")
        if !isPrivate { try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        sessionFile = root.appendingPathComponent("session.json")
        sites = owner?.sites ?? SiteSettings(file: root.appendingPathComponent("sites.json"), persistent: !isPrivate)
        boosts = owner?.boosts ?? Boosts(directory: root.appendingPathComponent("boosts"), persistent: !isPrivate)
        if owner == nil && !isPrivate {
            let file = root.appendingPathComponent("settings.json")
            if FileManager.default.fileExists(atPath: file.path) {
                do { library.settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: file)) }
                catch { canPersistSettings = false; settingsError = "Settings couldn’t be read. The original file is untouched." }
            }
            onboardingPresented = !FileManager.default.fileExists(atPath: root.appendingPathComponent("session.json").path) && !library.settings.onboardingComplete
        }
        graph = owner?.graph ?? KnowledgeGraph(file: root.appendingPathComponent("graph.json"), inMemory: isPrivate)
        vault = owner?.vault ?? Vault(file: root.appendingPathComponent("annotations.json"), directory: isPrivate ? root : (directory ?? Paths.vault), inMemory: isPrivate)
        downloads = owner?.downloads ?? DownloadStore(file: isPrivate ? nil : root.appendingPathComponent("downloads.json"))
        boards = owner?.boards ?? BoardStore(file: isPrivate ? nil : root.appendingPathComponent("boards.json"))
        activeSpaceID = spaces[0].id
        if owner == nil && !isPrivate { restoreSession() }
        if owner == nil && !isPrivate && FileManager.default.fileExists(atPath: archiveFile.path) {
            do { archivedTabs = try JSONDecoder().decode([SessionTab].self, from: Data(contentsOf: archiveFile)) }
            catch { canPersistSession = false; sessionError = "The archive couldn’t be read. Its file has been left untouched." }
        }
        library.windows.append(WeakBrowserState(self))
        library.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        if let owner {
            activeSpaceID = owner.activeSpaceID; mode = owner.mode
            archiveHours = owner.archiveHours; discardMinutes = owner.discardMinutes
            littleEnabled = owner.littleEnabled; littlePinnedLinks = owner.littlePinnedLinks
        }
        if owner == nil { archiveInactiveTabs() }
        if tabs.isEmpty || owner != nil { _ = newTab(activate: true) }
        else if owner == nil && settings.startupBlank == true { _ = newTab(activate: true) }
        downloads.preferredDirectory = { [weak self] in self?.settings.downloadsFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } }
        if !isPrivate { downloads.onFinished = { [weak self] in self?.tidyDownload($0) } }
        if directory == nil && owner == nil {
            mediaTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.pollingMedia else { return }
                    self.pollingMedia = true
                    await self.pollMediaAndDiscard()
                    self.pollingMedia = false
                }
            }
            lifecycleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.archiveInactiveTabs() }
            }
        }
        graph.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        boards.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        vault.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        if isPrivate { mode = .dark }
        if directory == nil && owner == nil && !isPrivate { startDebugDriverIfEnabled() }
    }

    /// A WKWebView has exactly one host. Selecting a visible tab in another
    /// window hands it over and leaves that window with a fresh tab, not a hole.
    private func claimTab(_ id: UUID) {
        let ids = Set(splits.first(where: { $0.tabIDs.contains(id) })?.tabIDs ?? [id])
        for other in library.states where other !== self {
            if let active = other.activeTabID, ids.contains(active) {
                other.activeTabID = nil
                _ = other.newTab()
            }
        }
    }

    var displayedTabIDs: Set<UUID> {
        Set(library.states.flatMap { state in state.activeSplit?.tabIDs ?? state.activeTabID.map { [$0] } ?? [] })
    }

    // MARK: theming actions

    @discardableResult
    func createSpace(name: String = "New Space") -> UUID {
        let space = SpaceInfo(id: UUID(), name: name, color: SpaceColor.defaultPreset)
        spaces.append(space)
        selectSpace(space.id)
        return space.id
    }

    func renameSpace(_ id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].name = name
        persistSoon()
    }

    func deleteSpace(_ id: UUID) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let destination = spaces[index == 0 ? 1 : index - 1].id
        for tab in tabs where tab.spaceID == id { tab.spaceID = destination }
        for i in folders.indices where folders[i].spaceID == id { folders[i].spaceID = destination }
        spaces.remove(at: index)
        lastActiveTabs.removeValue(forKey: id)
        if activeSpaceID == id { selectSpace(destination) }
        persistSoon()
    }

    func moveSpace(_ id: UUID, before destination: UUID) {
        guard id != destination, spaces.contains(where: { $0.id == destination }),
              let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let space = spaces.remove(at: index)
        spaces.insert(space, at: spaces.firstIndex(where: { $0.id == destination })!)
        persistSoon()
    }

    func selectRelativeSpace(_ delta: Int) {
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        selectSpace(spaces[(index + delta + spaces.count) % spaces.count].id)
    }

    var visibleTabs: [Tab] { tabs.filter { $0.spaceID == activeSpaceID } }
    var currentThreads: [KnowledgeGraph.Thread] { graph.threads(spaceID: activeSpaceID) }

    func selectSpace(_ id: UUID) {
        guard spaces.contains(where: { $0.id == id }) else { return }
        selectedTabIDs = []; selectionAnchor = nil
        if let activeTabID { lastActiveTabs[activeSpaceID] = activeTabID }
        activeSpaceID = id
        activeTabID = visibleTabs.first(where: { $0.id == lastActiveTabs[id] })?.id ?? visibleTabs.first?.id
        if activeTabID == nil { newTab() }
        selectedThreadID = nil
        activeSurface = .web
        persistSoon()
    }

    func notify(_ message: String) {
        if message == "Saved to Vault" {
            toasts.enqueue(title: message, actionTitle: "View") { [weak self] in self?.show(.vault) }
        } else { toasts.enqueue(title: message) }
    }

    func openThread(_ thread: KnowledgeGraph.Thread) { selectedThreadID = thread.id; show(.threads) }

    // MARK: thread map actions (graphene-language.md §5.2)

    /// The thread's map, from its recorded visits.
    func threadLayout(_ thread: KnowledgeGraph.Thread) -> ThreadLayout {
        ThreadLayout(thread: thread, visits: graph.visits(inThread: thread.id))
    }

    /// A map node was clicked. Plain: the page loads in the current tab and the visit rejoins
    /// the thread under its map parent, so the tree stays as drawn. `asChild` (⌘-click): the page
    /// opens as a child tab of the current tab, which the sidebar draws with its connector.
    func openThreadNode(_ nodeID: UUID, in thread: KnowledgeGraph.Thread, asChild: Bool) {
        guard let page = thread.nodes.first(where: { $0.id == nodeID }), let url = URL(string: page.url) else { return }
        if asChild, let parent = activeTab {
            openTab(url: url, parent: parent, activate: true)
            return
        }
        let tab = activeTab ?? newTab()
        tab.currentNodeID = threadLayout(thread).node(nodeID)?.parentID
        tab.currentThreadID = thread.id
        tab.resumeThreadID = thread.id
        tab.originQuery = nil
        tab.load(url)
        activate(tab.id)
    }

    /// "Resume from here": reopens the branch from `nodeID` forward as Today tabs, each child
    /// tab linked to its map parent's tab so the sidebar shows the same tree. The first tab is
    /// activated. Returns the opened tabs in map order.
    @discardableResult
    func resumeThread(from nodeID: UUID, in thread: KnowledgeGraph.Thread) -> [Tab] {
        let layout = threadLayout(thread)
        var opened: [UUID: Tab] = [:], result: [Tab] = []
        for node in layout.branch(from: nodeID) {
            guard let page = thread.nodes.first(where: { $0.id == node.id }), let url = URL(string: page.url) else { continue }
            let parent = node.id == nodeID ? nil : node.parentID.flatMap { opened[$0] }
            let before = Set(tabs.map(\.id))
            openTab(url: url, parent: parent, activate: false)
            guard let tab = tabs.first(where: { !before.contains($0.id) }) else { continue }
            // The revisit is recorded under the node's map parent, in this thread.
            tab.currentNodeID = node.parentID
            tab.currentThreadID = thread.id
            tab.resumeThreadID = thread.id
            opened[node.id] = tab
            result.append(tab)
        }
        if let first = result.first { activate(first.id) }
        return result
    }

    /// "Note" on a map node: the page's Vault note if it has one, else the page opens in the
    /// current tab with the note composer.
    func openThreadNote(_ nodeID: UUID, in thread: KnowledgeGraph.Thread) {
        guard let page = thread.nodes.first(where: { $0.id == nodeID }) else { return }
        if let note = vault.annotations(forURL: page.url).max(by: { $0.created < $1.created }) {
            vaultSelectionID = note.id
            show(.vault)
            return
        }
        openThreadNode(nodeID, in: thread, asChild: false)
        noteComposerPresented = true
    }
    func pin(_ tab: Tab) { placeTab(tab.id, section: tab.isPinned ? .today : .pinned) }

    func placeTab(_ id: UUID, section: TabSection, folderID: UUID? = nil, spaceID: UUID? = nil) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let destination = spaceID ?? tab.spaceID ?? activeSpaceID
        guard spaces.contains(where: { $0.id == destination }) else { return }
        if let folderID {
            guard folders.contains(where: { $0.id == folderID && $0.spaceID == destination && $0.section == section }) else { return }
        }
        if tab.spaceID != destination {
            for index in splits.indices { splits[index].tabIDs.removeAll { $0 == id } }
            splits.removeAll { $0.tabIDs.count < 2 }
        }
        if tab.spaceID != destination || section != .today || folderID != nil { detachFromBranch(tab) }
        tab.spaceID = destination
        tab.isFavorite = section == .favorites
        tab.isPinned = section != .today
        tab.pinnedURL = tab.isPinned ? (tab.pinnedURL ?? tab.url) : nil
        if tab.isPinned { tidyTitle(tab) }
        tab.folderID = section == .favorites ? nil : folderID
        if activeTabID == id && destination != activeSpaceID { activeTabID = visibleTabs.first?.id }
        objectWillChange.send(); persistSoon()
    }

    func renameTab(_ tab: Tab, name: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tab.customTitle = title.isEmpty ? nil : title
        objectWillChange.send(); persistSoon()
    }

    func resetPinnedTab(_ tab: Tab) { if let url = tab.pinnedURL { tab.load(url); activate(tab.id) } }

    func duplicateTab(_ tab: Tab) {
        let copy = makeTab()
        copy.spaceID = tab.spaceID; copy.customTitle = tab.customTitle
        copy.currentThreadID = tab.currentThreadID; copy.currentNodeID = tab.currentNodeID
        tabs.append(copy)
        if let url = tab.url { copy.load(url) }
        activate(copy.id)
    }

    @discardableResult
    func createFolder(name: String = "New Folder", section: TabSection) -> UUID {
        let folder = TabFolder(name: name, spaceID: activeSpaceID, section: section == .favorites ? .pinned : section)
        folders.append(folder); persistSoon(); return folder.id
    }

    func updateFolder(_ id: UUID, name: String? = nil, collapsed: Bool? = nil) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { folders[index].name = name }
        if let collapsed { folders[index].collapsed = collapsed }
        persistSoon()
    }

    func deleteFolder(_ id: UUID) {
        for tab in tabs where tab.folderID == id { tab.folderID = nil }
        folders.removeAll { $0.id == id }; persistSoon()
    }

    func archiveToday() {
        for tab in visibleTabs where tab.section == .today { closeTab(tab.id) }
        notify("Today archived. Reopen with ⇧⌘T.")
    }

    func archiveInactiveTabs() {
        archiveInactiveTabs(in: nil)
    }

    func tidyToday() {
        guard archiveHours > 0 else { notify("Auto-archive is set to Never in Settings."); return }
        let before = tabs.count
        archiveInactiveTabs(in: activeSpaceID)
        notify(before == tabs.count ? "No stale Today tabs." : "Stale Today tabs archived.")
    }

    private func archiveInactiveTabs(in spaceID: UUID?) {
        guard archiveHours > 0 else { return }
        let now = clock()
        for tab in tabs where (spaceID == nil || tab.spaceID == spaceID) && !displayedTabIDs.contains(tab.id) && tab.section == .today && !tab.isPlayingAudio && now.timeIntervalSince(tab.lastActiveAt) >= archiveHours * 3600 {
            closeTab(tab.id)
        }
    }

    func deleteArchive(_ id: UUID) {
        archivedTabs.removeAll { $0.archiveID == id }; persistSoon()
    }

    func restoreArchive(_ id: UUID) {
        guard let index = archivedTabs.firstIndex(where: { $0.archiveID == id }) else { return }
        let entry = archivedTabs.remove(at: index)
        archivedTabs.append(entry); reopenClosedTab()
    }

    func requestCloseTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if tab.isPinned {
            let alert = NSAlert(); alert.messageText = "Unpin or close?"
            alert.informativeText = "\(tab.displayTitle) is a saved destination. Unpin keeps it in Today."
            alert.addButton(withTitle: "Unpin"); alert.addButton(withTitle: "Close"); alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: placeTab(id, section: .today)
            case .alertSecondButtonReturn: closeTab(id)
            default: break
            }
        } else { closeTab(id) }
    }
    func focusAddress() {
        presentCommandBar()
    }

    /// Opens the command bar to replace the current page, prefilled with `seedURL`
    /// (the active tab's URL when nil) and fully selected, so typing replaces it.
    /// The page toolbar's URL, `⌘L` and the top-tabs address all use this.
    func presentCommandBar(seedURL: URL? = nil) {
        openCommandBar(newTab: false)
        if let seedURL { commandBarDraft = seedURL.absoluteString }
    }

    func openCommandBar(newTab: Bool) {
        commandBarFocusRequest += 1
        if commandBarPresented && commandBarCreatesTab == newTab { return }
        if commandBarPresented && commandBarCreatesTab { pendingNewTabDraft = commandBarDraft }
        commandBarCreatesTab = newTab
        commandBarDraft = newTab ? pendingNewTabDraft : (activeTab?.url?.absoluteString ?? "")
        commandBarPresented = true
    }

    /// The sidebar's "+ New Tab" row, the footer "+" and the command bar's New Tab action: a
    /// blank Today tab showing the Resume page, with its search row taking the keyboard.
    /// ⌘T keeps opening the command bar instead (Arc). An already blank selected tab is reused.
    func openResumeTab() {
        if commandBarPresented { commandBarPresented = false }
        if let tab = activeTab, tab.url == nil, tab.section == .today { show(.web) } else { newTab() }
        resumeFocusRequest += 1
    }
    func dismissCommandBar() {
        resumeKeyBuffer = nil
        if commandBarCreatesTab { pendingNewTabDraft = commandBarDraft }
        commandBarPresented = false
        focusBrowser()
    }

    func completeCommandBarSwitch(_ id: UUID) {
        resumeKeyBuffer = nil
        activate(id)
        pendingNewTabDraft = ""
        commandBarDraft = ""
        commandBarPresented = false
        focusBrowser()
    }

    func commitCommandBar(_ input: String) {
        resumeKeyBuffer = nil
        guard Omnibox.resolve(input, engine: searchEngine, customSearchURL: settings.customSearchURL) != nil else { return }
        let target = commandBarCreatesTab && activeTab?.url != nil ? newTab() : (activeTab ?? newTab())
        submit(input, on: target)
        pendingNewTabDraft = ""
        commandBarDraft = ""
        commandBarPresented = false
        focusBrowser()
    }

    private func focusBrowser() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.commandBarPresented, self.activeSurface == .web,
                  let host = self.activeTab?.engine.hostView, let window = host.window else { return }
            window.makeFirstResponder(host)
        }
    }

    func askThread(_ thread: KnowledgeGraph.Thread) {
        attachedSources = []
        knowledgeThreadID = thread.id
        knowledgeSearchPresented = true
        show(.web)
    }

    func toggleKnowledge() {
        guard !isPrivate else { notify("Knowledge capture is unavailable in Private windows."); return }
        if knowledgeSearchPresented { knowledgeSearchPresented = false }
        else { knowledgeThreadID = nil; knowledgeSearchPresented = true }
    }

    func setColor(_ color: SpaceColor) {
        if let i = spaces.firstIndex(where: { $0.id == activeSpaceID }) { spaces[i].color = color; spaces[i].theme = nil }
        persistSoon()
    }
    func updateSpaceTheme(_ theme: SpaceTheme, icon: String? = nil) {
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        spaces[index].theme = theme
        if let icon { spaces[index].icon = icon }
        persistSoon()
    }
    func resizeSidebar(_ width: CGFloat, windowID: String? = nil) {
        sidebarWidth = ShellLayout.clampedSidebarWidth(width)
        if let id = windowID ?? focusedWindowID { sidebarWidths[id] = Double(sidebarWidth) }
        persistSoon()
    }
    func toggleMode() { mode = (mode == .dark ? .light : .dark); persistSoon() }
    func toggleSidebar() { sidebarCollapsed.toggle(); persistSoon() }
    func show(_ surface: Surface) {
        guard !isPrivate || surface == .web else { notify("Private windows don’t access your saved knowledge or mail."); return }
        activeSurface = surface; persistSoon()
    }

    var activeTab: Tab? { tabs.first { $0.id == activeTabID } }

    // MARK: tab management

    @discardableResult
    func newTab(activate: Bool = true) -> Tab {
        let tab = makeTab()
        tabs.append(tab)
        if activate { activeTabID = tab.id; activeSurface = .web }
        persistSoon()
        return tab
    }

    private func makeTab(id: UUID = UUID(), spaceID: UUID? = nil) -> Tab {
        let space = spaces.first { $0.id == spaceID } ?? activeSpace
        let profileID = space.profileID ?? Profile.defaultID
        let tab = Tab(engine: WKWebEngine(privateMode: isPrivate, profileID: profileID), id: id, privateMode: isPrivate)
        tab.profileID = profileID
        tab.lastActiveAt = clock()
        tab.coordinator = self
        tab.spaceID = space.id
        tab.configureEngine = { [weak tab] engine in
            (engine as? WKWebEngine)?.aiOwner = tab?.coordinator as? AppState
            (engine as? WKWebEngine)?.sites = (tab?.coordinator as? AppState)?.sites
            (engine as? WKWebEngine)?.boosts = (tab?.coordinator as? AppState)?.boosts
            (engine as? WKWebEngine)?.refreshBoosts()
            (engine as? WKWebEngine)?.globalBlocking = { [weak tab] in
                (tab?.coordinator as? AppState)?.settings.contentBlocking ?? true
            }
            (engine as? WKWebEngine)?.downloads = (tab?.coordinator as? AppState)?.downloads
            (engine as? WKWebEngine)?.capturePermitted = { [weak tab] in
                guard let tab, let owner = tab.coordinator as? AppState else { return false }
                return owner.captureAllowed(tab)
            }
            (engine as? WKWebEngine)?.savedNotes = { [weak tab] url in
                (tab?.coordinator as? AppState)?.vault.markedNotes(forURL: url) ?? []
            }
            (engine as? WKWebEngine)?.linkHandler = { [weak tab] url, modifiers in
                guard let tab, tab.isPinned, let owner = (BrowserFocus.shared.app ?? tab.coordinator as? AppState) else { return false }
                if modifiers.contains(.shift) { owner.showPeek(url); return true }
                if modifiers.contains(.command) && owner.littlePinnedLinks { LittleArcWindow.open(url, app: owner); return true }
                return false
            }
        }
        tab.configureEngine?(tab.engine)
        return tab
    }

    @discardableResult
    func closeTab(_ id: UUID, announce: Bool = true) -> UUID? {
        guard let target = tabs.first(where: { $0.id == id }) else { return nil }
        promoteChildren(of: target)
        collapsedBranchIDs.remove(id)
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        selectedTabIDs.remove(id)
        for state in library.states { state.recentIDs.removeAll { $0 == id } }
        let closing = tabs[idx]
        let sibling = splits.first(where: { $0.tabIDs.contains(id) })?.tabIDs.first { $0 != id }
        for index in splits.indices { splits[index].tabIDs.removeAll { $0 == id } }
        splits.removeAll { $0.tabIDs.count < 2 }
        var archived: UUID?
        if closing.url != nil && !isPrivate {
            var entry = SessionTab(closing)
            entry.archiveID = UUID(); entry.archivedAt = clock()
            archivedTabs.append(entry)
            archived = entry.archiveID
            if announce, let archiveID = entry.archiveID {
                toasts.enqueue(title: "Closed \(closing.displayTitle)", icon: "xmark.circle", seconds: 5, actionTitle: "Undo") { [weak self] in
                    self?.restoreArchive(archiveID)
                }
            }
            if archivedTabs.count > 2000 { archivedTabs.removeFirst(archivedTabs.count - 2000) }
        }
        tabs.remove(at: idx)
        for other in library.states where other !== self && other.activeTabID == id {
            other.activeTabID = nil; _ = other.newTab()
        }
        if activeTabID == id {
            activeTabID = sibling ?? visibleTabs.last?.id
        }
        if visibleTabs.isEmpty { _ = newTab(activate: true) }
        persistSoon()
        return archived
    }

    func reopenClosedTab() {
        guard let closed = archivedTabs.popLast() else { return }
        restore(closed)
    }

    /// Reopens an archived entry. Its parent link survives only when that parent is open,
    /// under its original id or the id `remap` gives it (a branch restored in one Undo).
    @discardableResult
    private func restore(_ closed: SessionTab, remap: [UUID: UUID] = [:]) -> Tab {
        if let id = closed.spaceID, spaces.contains(where: { $0.id == id }) { selectSpace(id) }
        let tab = activeTab?.url == nil ? activeTab! : newTab()
        tab.profileID = activeSpace.profileID ?? Profile.defaultID; tab.discard()
        tab.currentThreadID = closed.threadID
        tab.currentNodeID = closed.nodeID
        tab.isPinned = closed.pinned
        tab.isFavorite = closed.favorite ?? false
        tab.pinnedURL = closed.pinnedURL.flatMap(URL.init(string:))
        tab.customTitle = closed.customTitle
        tab.title = closed.title ?? ""
        tab.lastActiveAt = clock()
        tab.folderID = closed.folderID.flatMap { id in folders.contains { $0.id == id } ? id : nil }
        tab.isRestoring = true
        tab.parentTabID = closed.parentTabID.map { remap[$0] ?? $0 }.flatMap { id in tabs.contains { $0.id == id && $0.id != tab.id } ? id : nil }
        if let url = closed.url.flatMap(URL.init(string:)) { tab.load(url) }
        show(.web)
        persistSoon()
        return tab
    }

    func moveTab(_ id: UUID, onto destinationID: UUID, before: Bool = false) {
        guard id != destinationID,
              let source = tabs.firstIndex(where: { $0.id == id }),
              let destinationIndex = tabs.firstIndex(where: { $0.id == destinationID }),
              let target = tabs[safe: destinationIndex],
              tabs[source].spaceID == target.spaceID,
              tabs[source].isPinned == target.isPinned else { return }
        let tab = tabs.remove(at: source)
        guard let destination = tabs.firstIndex(where: { $0.id == destinationID }) else { return }
        tabs.insert(tab, at: !before && source < destinationIndex ? destination + 1 : destination)
        // A reordered child leaves its branch and becomes a root at the drop position.
        tab.parentTabID = nil
        objectWillChange.send()
        persistSoon()
    }

    func activate(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.lastActiveAt = clock()
        if let activeTabID { lastActiveTabs[activeSpaceID] = activeTabID }
        if let spaceID = tab.spaceID { activeSpaceID = spaceID }
        activeTabID = id; activeSurface = .web; persistSoon()
        if !commandBarPresented { focusBrowser() }
    }

    func selectRelativeTab(_ delta: Int) {
        let visible = visibleTabs
        guard let idx = visible.firstIndex(where: { $0.id == activeTabID }), !visible.isEmpty else { return }
        activate(visible[(idx + delta + visible.count) % visible.count].id)
    }

    func reorderActiveTab(_ delta: Int) {
        guard let tab = activeTab else { return }
        let rows = visibleTabs.filter { $0.section == tab.section && $0.folderID == tab.folderID }
        guard let index = rows.firstIndex(where: { $0.id == tab.id }), let target = rows[safe: index + delta] else { return }
        moveTab(tab.id, onto: target.id)
    }

    // MARK: navigation

    /// Submit omnibox text on the active tab (or a given tab). Records the search
    /// query so the resulting page carries the "why" behind it.
    func submit(_ input: String, on tab: Tab? = nil) {
        activeSurface = .web
        let target = tab ?? activeTab ?? newTab()
        guard let action = Omnibox.resolve(input, engine: searchEngine, customSearchURL: settings.customSearchURL) else { notify("Check the custom search URL in Settings."); return }
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
        citations.pageNavigated(tabID: tab.id)
        guard captureAllowed(tab, url: url) else { tab.currentNodeID = nil; tab.currentThreadID = nil; return }
        let node = graph.recordVisit(
            url: url, title: title,
            spaceID: tab.spaceID,
            parentNodeID: tab.currentNodeID,
            query: tab.originQuery, continuingThreadID: tab.currentThreadID, resumeThreadID: tab.resumeThreadID
        )
        tab.currentNodeID = node
        tab.currentThreadID = graph.visits.last?.threadID
        tab.originQuery = nil
        tab.resumeThreadID = nil
        persistSoon()
        Task { [weak self, weak tab] in
            guard let tab else { return }
            let text = await tab.engine.captureSnapshotText()
            guard tab.currentNodeID == node, tab.url == url, self?.captureAllowed(tab, url: url) == true else { return }
            self?.graph.attachText(nodeID: node, text: text)
            if let t = tab.engine.pageTitle, !t.isEmpty { self?.graph.setTitle(nodeID: node, title: t) }
        }
    }

    /// A citation mark in `tabID`'s page was hovered (`id`) or left (`nil`); raises its chip in the Ask panel.
    /// Called from the tab's `engine(_:didHoverHighlight:)`.
    func citationMarkHovered(_ id: String?, tabID: UUID) { citations.markHovered(id, tabID: tabID) }

    func tab(_ tab: Tab, didCapture annotation: CapturedAnnotation) {
        guard captureAllowed(tab, url: annotation.url) else { return }
        vault.add(text: annotation.text, note: annotation.note, url: annotation.url,
                  title: annotation.title, context: annotation.context, spaceID: tab.spaceID)
        if let error = vault.errorText { notify("Couldn’t save: \(error)"); return }
        if let node = tab.currentNodeID { graph.bumpAnnotationCount(nodeID: node) }
        markSavedNotes(in: tab)
        notify("Saved to Vault")
    }

    // MARK: saved notes in pages (graphene-language.md §5.3)

    /// Re-marks `tab`'s page with its saved notes (after a save, an edit or a delete).
    func markSavedNotes(in tab: Tab) {
        guard !isPrivate, let engine = tab.loadedEngine as? WKWebEngine else { return }
        Task { await engine.markSavedNotes() }
    }

    /// Re-marks every open tab showing `url`.
    func refreshNoteMarks(url: String) {
        let key = KnowledgeGraph.canonicalURL(url)
        for tab in tabs where tab.url.map({ KnowledgeGraph.canonicalURL($0.absoluteString) }) == key { markSavedNotes(in: tab) }
    }

    /// Changes a note's text from the Vault or from its card in the page.
    func updateNote(_ note: Annotation, text: String) {
        vault.update(note, note: text)
        guard vault.errorText == nil else { notify("Couldn’t save note"); return }
        noteDrafts.removeValue(forKey: note.id)
        refreshNoteMarks(url: note.url)
        notify("Note updated")
    }

    /// Deletes a note and removes its mark from open pages.
    func deleteNote(_ note: Annotation) {
        vault.delete(note)
        guard !vault.annotations.contains(where: { $0.id == note.id }) else { return }
        noteDrafts.removeValue(forKey: note.id)
        if vaultSelectionID == note.id { vaultSelectionID = nil }
        refreshNoteMarks(url: note.url)
    }

    /// "Open in Vault" on a note card: the Vault with the note selected.
    func openNoteInVault(_ id: UUID) {
        vaultSelectionID = id
        show(.vault)
    }

    /// Ask on the selection bar: opens the Ask panel with the selected text attached as a source.
    /// The source takes the page's graph node id, so it carries the page's space provenance.
    func askAboutSelection(_ text: String, in tab: Tab) {
        guard !isPrivate, aiTabAllowed(tab), let url = tab.url, let node = tab.currentNodeID else { return }
        attachedSources = [KnowledgeSource(id: node, title: tab.displayTitle, url: url.absoluteString, text: text, kind: "Selection")]
        sendToAsk("")
    }

    func openTab(url: URL, parent: Tab?, activate: Bool) {
        let routedSpace = settings.routingRules.first { rule in
            rule.matches(url) && spaces.contains { $0.id == rule.spaceID }
        }?.spaceID
        let tab = makeTab(spaceID: routedSpace ?? parent?.spaceID ?? activeSpaceID)
        tab.parentTabID = parent?.id
        tab.spaceID = routedSpace ?? parent?.spaceID ?? activeSpaceID
        tab.currentThreadID = parent?.currentThreadID
        tab.currentNodeID = parent?.currentNodeID   // so the child's first page links from the parent's node
        if let idx = tabs.firstIndex(where: { $0.id == parent?.id }) {
            // Siblings read oldest first, so a new child follows its parent's whole branch.
            let branch = parent.map { branchIDs($0.id) } ?? []
            tabs.insert(tab, at: (tabs.lastIndex { branch.contains($0.id) } ?? idx) + 1)
        } else {
            tabs.append(tab)
        }
        if activate || routedSpace != nil { self.activate(tab.id) }
        tab.load(url)
        persistSoon()
    }

    /// A link in a Mail message (graphene-language.md §5.7) opens as a child of the tab the Mail
    /// surface sits over, so it shows its provenance in the sidebar. Only web links open.
    func openMailLink(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        openTab(url: url, parent: activeTab, activate: true)
    }

    // MARK: provenance (graphene-identity.md §3.1)

    /// Only unfoldered Today tabs take part in branches; pinned tabs and favorites never do.
    private func inTodayList(_ tab: Tab) -> Bool { tab.section == .today && tab.folderID == nil }

    /// The Today list of a space as branches, with `collapsedBranchIDs` applied.
    func todayProvenance(spaceID: UUID? = nil) -> ProvenanceLayout {
        let space = spaceID ?? activeSpaceID
        let today = tabs.filter { $0.spaceID == space && inTodayList($0) }
        var parents: [UUID: UUID] = [:]
        for tab in today { if let parent = tab.parentTabID { parents[tab.id] = parent } }
        return ProvenanceLayout(ids: today.map(\.id), parents: parents, collapsed: collapsedBranchIDs)
    }

    /// The participating parent of a tab: an open Today tab in the same space.
    func branchParent(of id: UUID) -> Tab? {
        guard let tab = tabs.first(where: { $0.id == id }), inTodayList(tab), let parentID = tab.parentTabID, parentID != id,
              let parent = tabs.first(where: { $0.id == parentID }), parent.spaceID == tab.spaceID, inTodayList(parent) else { return nil }
        return parent
    }

    /// Direct children shown under a Today row, in list order.
    func branchChildren(of id: UUID) -> [Tab] {
        tabs.filter { $0.parentTabID == id && branchParent(of: $0.id)?.id == id }
    }

    /// The tab and every descendant, parents before children.
    func branchIDs(_ id: UUID) -> [UUID] {
        var result: [UUID] = [], queue = [id]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard !result.contains(next) else { continue }
            result.append(next)
            queue.append(contentsOf: branchChildren(of: next).map(\.id))
        }
        return result
    }

    /// Children of a closing or leaving tab take its place: they join its own parent (or become
    /// roots) at its position in the list, so the branch closes without a gap.
    private func promoteChildren(of tab: Tab) {
        let children = tabs.filter { $0.parentTabID == tab.id && $0.id != tab.id }
        guard !children.isEmpty else { return }
        let adopter = branchParent(of: tab.id)?.id
        let moving = inTodayList(tab) ? children.filter { $0.spaceID == tab.spaceID && inTodayList($0) } : []
        for child in children { child.parentTabID = adopter }
        if !moving.isEmpty {
            tabs.removeAll { candidate in moving.contains { $0 === candidate } }
            if let index = tabs.firstIndex(where: { $0 === tab }) { tabs.insert(contentsOf: moving, at: index) }
        }
        objectWillChange.send()
    }

    private func detachFromBranch(_ tab: Tab) {
        guard tab.parentTabID != nil || tabs.contains(where: { $0.parentTabID == tab.id }) else { return }
        promoteChildren(of: tab)
        tab.parentTabID = nil
        collapsedBranchIDs.remove(tab.id)
    }

    /// "Detach from parent": the tab becomes a root and keeps its own children.
    func detachFromParent(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }), tab.parentTabID != nil else { return }
        tab.parentTabID = nil
        objectWillChange.send(); persistSoon()
    }

    /// Dropping a tab on a Today row's icon slot makes it that row's newest child.
    func adoptTab(_ id: UUID, under parentID: UUID) {
        guard id != parentID, let parent = tabs.first(where: { $0.id == parentID }), inTodayList(parent),
              tabs.contains(where: { $0.id == id }), !branchIDs(id).contains(parentID) else { return }
        placeTab(id, section: .today, spaceID: parent.spaceID)
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: index)
        let branch = branchIDs(parentID)
        tabs.insert(tab, at: (tabs.lastIndex { branch.contains($0.id) } ?? tabs.count - 1) + 1)
        tab.parentTabID = parentID
        collapsedBranchIDs.remove(parentID)
        objectWillChange.send(); persistSoon()
    }

    /// "Close branch": archives the tab and its descendants with one Undo toast.
    func closeBranch(_ id: UUID) {
        let ids = branchIDs(id)
        guard ids.count > 1 else { closeTab(id); return }
        // Deepest first, so no child is promoted and every entry keeps its original parent.
        let restoring = Array(ids.reversed().compactMap { closeTab($0, announce: false) }.reversed())
        guard !restoring.isEmpty else { return }
        toasts.enqueue(title: "Archived \(restoring.count) tabs", icon: "archivebox", seconds: 5, actionTitle: "Undo") { [weak self] in
            self?.restoreBranch(restoring)
        }
    }

    /// Reopens archive entries parents first, relinking children to their restored parents.
    func restoreBranch(_ archiveIDs: [UUID]) {
        var remap: [UUID: UUID] = [:], first: Tab?
        for archiveID in archiveIDs {
            guard let index = archivedTabs.firstIndex(where: { $0.archiveID == archiveID }) else { continue }
            let entry = archivedTabs.remove(at: index)
            let tab = restore(entry, remap: remap)
            if let old = entry.id { remap[old] = tab.id }
            if first == nil { first = tab }
        }
        if let first { activate(first.id) }
    }

    /// ⌥← / ⌥→ on a Today row with children.
    func setBranch(_ id: UUID, collapsed: Bool) {
        guard !branchChildren(of: id).isEmpty else { return }
        if collapsed { collapsedBranchIDs.insert(id) } else { collapsedBranchIDs.remove(id) }
    }

    /// The branch "Collapse Branch" / "Expand Branch" act on: the selected tab when it has
    /// children, else the parent it hangs from. `nil` when the selected tab is in no branch.
    var selectedBranchID: UUID? {
        guard let id = activeTabID else { return nil }
        if !branchChildren(of: id).isEmpty { return id }
        return branchParent(of: id)?.id
    }
    /// Collapses or expands the selected tab's branch, whatever has focus (⌃⌥⌘← / ⌃⌥⌘→).
    /// Collapsing from a child selects the parent, so the selection stays visible.
    func setSelectedBranch(collapsed: Bool) {
        guard let id = selectedBranchID else { return }
        setBranch(id, collapsed: collapsed)
        if collapsed, activeTabID != id { activate(id) }
    }

    /// Selecting a tab inside a collapsed branch opens the branches above it.
    private func revealInBranch(_ id: UUID) {
        var current = id, seen: Set<UUID> = []
        while let parent = branchParent(of: current), seen.insert(parent.id).inserted {
            collapsedBranchIDs.remove(parent.id); current = parent.id
        }
    }

    // MARK: session persistence

    struct SessionTab: Codable {
        var url: String?; var pinned: Bool; var spaceID: UUID?; var nodeID: UUID?; var threadID: UUID?
        var favorite: Bool?; var pinnedURL: String?; var customTitle: String?; var folderID: UUID?
        var lastActiveAt: Date?; var archivedAt: Date?; var archiveID: UUID?; var title: String?
        var id: UUID?
        var parentTabID: UUID?
        @MainActor init(_ tab: Tab) {
            url = tab.url?.absoluteString; pinned = tab.isPinned; spaceID = tab.spaceID
            nodeID = tab.currentNodeID; threadID = tab.currentThreadID
            favorite = tab.isFavorite; pinnedURL = tab.pinnedURL?.absoluteString
            customTitle = tab.customTitle; folderID = tab.folderID
            lastActiveAt = tab.lastActiveAt; title = tab.title
            id = tab.id; parentTabID = tab.parentTabID
        }
    }
    struct SessionData: Codable {
        var spaces: [SpaceInfo]?
        var searchEngine: String?
        var surface: String?
        var tabs: [SessionTab]
        var activeIndex: Int
        var sidebarWidth: Double?
        var sidebarCollapsed: Bool?
        var mode: String?
        var spaceColors: [String]?
        var activeSpaceIndex: Int?
        var folders: [TabFolder]?
        var archivedTabs: [SessionTab]?
        var sidebarWidths: [String: Double]?
        var archiveHours: Double?
        var version: Int?
        var splits: [TabSplit]?
        var littleEnabled: Bool?
        var littlePinnedLinks: Bool?
        var discardMinutes: Double?
        var excludedHosts: Set<String>?
        var pausedSpaces: Set<UUID>?
        var layout: BrowserLayout?
        var searchSuggestions: Bool?
        var profiles: [Profile]?
    }

    private func persistSoon() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func persist() {
        if !isPrivate && canPersistSettings {
            do { try JSONEncoder().encode(exportedSettings).write(to: dataDirectory.appendingPathComponent("settings.json"), options: .atomic); settingsError = nil }
            catch { settingsError = "Couldn’t save settings: \(error.localizedDescription)" }
        }
        guard canPersistSession, !isPrivate else { return }
        let data = SessionData(
            spaces: spaces,
            searchEngine: searchEngine.rawValue,
            surface: activeSurface.rawValue,
            tabs: tabs.map { SessionTab($0) },
            activeIndex: tabs.firstIndex { $0.id == activeTabID } ?? 0,
            sidebarWidth: Double(sidebarWidth),
            sidebarCollapsed: sidebarCollapsed,
            mode: mode.rawValue,
            spaceColors: spaces.map { $0.color.rawValue },
            activeSpaceIndex: spaces.firstIndex { $0.id == activeSpaceID },
            folders: folders, archivedTabs: nil, sidebarWidths: sidebarWidths,
            archiveHours: archiveHours, version: 2, splits: splits,
            littleEnabled: littleEnabled, littlePinnedLinks: littlePinnedLinks, discardMinutes: discardMinutes,
            excludedHosts: excludedHosts, pausedSpaces: pausedSpaces,
            layout: layout, searchSuggestions: searchSuggestions, profiles: profiles
        )
        do {
            try JSONEncoder().encode(archivedTabs).write(to: archiveFile, options: .atomic)
            try JSONEncoder().encode(data).write(to: sessionFile, options: .atomic)
            sessionError = nil
        } catch { sessionError = "Couldn’t save the browser session: \(error.localizedDescription)" }
    }

    private func restoreSession() {
        guard FileManager.default.fileExists(atPath: sessionFile.path) else { return }
        let session: SessionData
        do { session = try JSONDecoder().decode(SessionData.self, from: Data(contentsOf: sessionFile)) }
        catch { canPersistSession = false; sessionError = "The previous session couldn’t be read. Its file has been left untouched."; return }
        if (session.version ?? 1) > 2 { canPersistSession = false; sessionError = "This session was saved by a newer Graphene. Its file is untouched."; return }
        if (session.version ?? 1) < 2 {
            do {
                let backup = sessionFile.appendingPathExtension("v1.backup")
                if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: sessionFile, to: backup) }
            } catch { canPersistSession = false; sessionError = "Couldn’t back up the previous session. Migration was stopped."; return }
        }
        archiveHours = session.archiveHours ?? 12
        profiles = session.profiles ?? []
        library.layout = session.layout ?? .sidebar
        library.searchSuggestions = session.searchSuggestions ?? true
        littleEnabled = false
        littlePinnedLinks = false
        discardMinutes = session.discardMinutes ?? 30
        excludedHosts = session.excludedHosts ?? []
        pausedSpaces = session.pausedSpaces ?? []
        folders = session.folders ?? []
        archivedTabs = session.archivedTabs ?? []
        for index in archivedTabs.indices where archivedTabs[index].archiveID == nil {
            archivedTabs[index].archiveID = UUID(); archivedTabs[index].archivedAt = clock()
        }
        sidebarWidths = (session.sidebarWidths ?? [:]).mapValues { Double(ShellLayout.clampedSidebarWidth($0)) }
        if let saved = session.spaces, !saved.isEmpty { spaces = saved; activeSpaceID = saved[0].id }
        if let raw = session.searchEngine, let engine = SearchEngine(rawValue: raw) { searchEngine = engine }
        if let w = session.sidebarWidth { sidebarWidth = ShellLayout.clampedSidebarWidth(CGFloat(w)) }
        if let c = session.sidebarCollapsed { sidebarCollapsed = c }
        if let m = session.mode, let tm = ThemeMode(rawValue: m) { mode = tm }
        if let colors = session.spaceColors {
            for (i, raw) in colors.enumerated() where i < spaces.count {
                if let sc = SpaceColor(rawValue: raw) { spaces[i].color = sc }
            }
        }
        if let idx = session.activeSpaceIndex, spaces.indices.contains(idx) { activeSpaceID = spaces[idx].id }
        var restoredParents: [(Tab, UUID)] = []
        for st in session.tabs {
            let tab = makeTab(id: st.id ?? UUID())
            if let parent = st.parentTabID { restoredParents.append((tab, parent)) }
            tab.isPinned = st.pinned
            tab.isFavorite = st.favorite ?? false
            tab.pinnedURL = (st.pinnedURL ?? (st.pinned ? st.url : nil)).flatMap(URL.init(string:))
            tab.customTitle = st.customTitle
            tab.title = st.title ?? ""
            tab.lastActiveAt = st.lastActiveAt ?? clock()
            tab.folderID = st.folderID
            tab.spaceID = st.spaceID.flatMap { id in spaces.contains { $0.id == id } ? id : nil } ?? activeSpaceID
            tab.profileID = spaces.first { $0.id == tab.spaceID }?.profileID ?? Profile.defaultID
            tabs.append(tab)
            tab.currentNodeID = st.nodeID
            tab.currentThreadID = st.threadID
            if let s = st.url, let url = URL(string: s) {
                tab.currentNodeID = st.nodeID ?? graph.node(for: url)?.id
                tab.isRestoring = true
                tab.url = url
            }
            // Blank tabs also need their own space's store, not the active space's.
            tab.discard()
        }
        // A parent that did not come back leaves its children as roots.
        for (tab, parent) in restoredParents where parent != tab.id && tabs.contains(where: { $0.id == parent }) { tab.parentTabID = parent }
        splits = (session.splits ?? []).filter { group in
            group.tabIDs.count >= 2 && group.tabIDs.count <= 4 && Set(group.tabIDs).count == group.tabIDs.count && group.tabIDs.allSatisfy { id in tabs.contains { $0.id == id } }
        }
        activeTabID = tabs[safe: session.activeIndex]?.id ?? tabs.first?.id
        if let id = activeTab?.spaceID { activeSpaceID = id }
        if let surface = session.surface.flatMap(Surface.init(rawValue:)) { activeSurface = surface }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
