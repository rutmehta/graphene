import SwiftUI
import AppKit
import WebKit

/// Word prefixes and initials, not arbitrary subsequences that drown out URLs.
enum CommandMatch {
    static func matches(_ query: String, title: String) -> Bool {
        let query = query.lowercased().trimmingCharacters(in: .whitespaces)
        let words = title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if query.isEmpty || title.lowercased().hasPrefix(query) { return true }
        if words.compactMap(\.first).map(String.init).joined().hasPrefix(query) { return true }
        var remaining = words[...]
        for term in query.split(separator: " ") {
            guard let index = remaining.firstIndex(where: { $0.hasPrefix(term) }) else { return false }
            remaining = remaining.suffix(from: remaining.index(after: index))
        }
        return true
    }
}

struct BrowserAction: Identifiable {
    let id: String
    let title: String
    var key: KeyEquivalent? = nil
    var modifiers: EventModifiers = .command
    var hint = ""
    var enabled = true
    let run: @MainActor () -> Void
    var group: String {
        if ["site-controls", "boost", "zap"].contains(id) { return "View & Settings" }
        if ["save-page", "system-browser"].contains(id) { return "File" }
        if ["settings", "dark", "space-color", "layout", "sidebar", "fullscreen", "inspector", "downloads", "library", "zoom-in", "zoom-out", "zoom-reset", "reader", "stop", "reload"].contains(id) { return "View & Settings" }
        if ["new-tab", "new-window", "private-window", "close-tab", "close-window", "location", "save", "export", "print"].contains(id) { return "File" }
        if id.hasPrefix("find") { return "Find" }
        if id.hasPrefix("space-") || ["new-space", "next-space", "previous-space", "route-site"].contains(id) { return "Spaces" }
        if ["web", "threads", "vault", "mail", "board", "ask", "summarize"].contains(id) { return "Knowledge" }
        return "Tabs & History"
    }
}

extension AppState {
    func closeFromKeyboard(in window: NSWindow?) {
        // Settings and auxiliary windows must not close the last browser's tab.
        if let window, window !== BrowserFocus.shared.window { window.performClose(nil); return }
        if let id = activeTabID { requestCloseTab(id) }
    }

    var commandActions: [BrowserAction] { allCommandActions.filter(\.enabled) }
    var allCommandActions: [BrowserAction] {
        var actions: [BrowserAction] = []
        func add(_ id: String, _ title: String, _ key: KeyEquivalent? = nil, _ modifiers: EventModifiers = .command, _ hint: String = "", enabled: Bool = true, run: @escaping @MainActor () -> Void) {
            var action = BrowserAction(id: id, title: title, key: key, modifiers: modifiers, hint: hint, enabled: enabled, run: run)
            if let override = settings.shortcutOverrides[id] {
                action.key = override.key.first.map { KeyEquivalent($0) }
                action.modifiers = override.modifiers; action.hint = override.hint
            }
            actions.append(action)
        }
        let tab = activeTab
        let page = tab?.url != nil
        add("site-controls", "Site Controls", enabled: page) { self.siteControlsTabID = tab?.id }
        add("boost", "Edit Site Boost", enabled: page) { self.boostHost = tab?.url?.host }
        add("zap", "Zap an Element", enabled: page) { (tab?.engine as? WKWebEngine)?.startZap(); self.notify("Click an element to hide it. Escape cancels.") }
        add("system-browser", "Open in Default Browser", enabled: page) { if let url = tab?.url { self.openInSystemBrowser(url) } }
        add("save-page", "Save Page As…", enabled: page) {
            guard let engine = tab?.engine as? WKWebEngine else { return }
            let panel = NSSavePanel(); panel.nameFieldStringValue = "Page.webarchive"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            engine.webView.createWebArchiveData { result in
                Task { @MainActor in
                    do { try result.get().write(to: url, options: .atomic); self.notify("Web archive saved") }
                    catch { self.notify("Couldn’t save page: \(error.localizedDescription)") }
                }
            }
        }
        add("private-window", "New Private Window", "n", [.command, .shift], "⇧⌘N") { BrowserWindows.openPrivate() }
        add("close-tab", "Close Tab", "w", .command, "⌘W", enabled: tab != nil) { self.closeFromKeyboard(in: NSApp.keyWindow) }
        add("close-window", "Close Window", "w", [.command, .shift], "⇧⌘W") { NSApp.keyWindow?.performClose(nil) }
        add("reopen", "Reopen Closed Tab", "t", [.command, .shift], "⇧⌘T", enabled: !archivedTabs.isEmpty) { self.reopenClosedTab() }
        add("location", "Open Location", "l", .command, "⌘L") { self.focusAddress() }
        add("stop", "Stop Loading", enabled: tab?.isLoading == true) { self.stop() }
        add("back", "Back", "[", .command, "⌘[", enabled: tab?.canGoBack == true) { self.goBack() }
        add("forward", "Forward", "]", .command, "⌘]", enabled: tab?.canGoForward == true) { self.goForward() }
        add("home", "Home") { self.newTab() }
        add("web", "Web", "1", [.command, .option], "⌥⌘1") { self.show(.web) }
        add("next-tab", "Select Next Tab", "]", [.command, .shift], "⇧⌘]") { self.selectRelativeTab(1) }
        add("previous-tab", "Select Previous Tab", "[", [.command, .shift], "⇧⌘[") { self.selectRelativeTab(-1) }
        add("next-tab-arrow", "Next Tab", .rightArrow, [.command, .option], "⌥⌘→") { self.selectRelativeTab(1) }
        add("previous-tab-arrow", "Previous Tab", .leftArrow, [.command, .option], "⌥⌘←") { self.selectRelativeTab(-1) }
        add("next-space", "Next Space") { self.selectRelativeSpace(1) }
        add("previous-space", "Previous Space") { self.selectRelativeSpace(-1) }
        add("mru-next", "Recent Tab", .tab, [.control], "⌃Tab") { self.cycleRecentTab(1) }
        add("mru-previous", "Previous Recent Tab", .tab, [.control, .shift], "⇧⌃Tab") { self.cycleRecentTab(-1) }
        add("split-vertical", "Split Vertically", .upArrow, [.command, .option], "⌥⌘↑") { self.splitNextTab(vertical: true) }
        add("split-horizontal", "Split Horizontally", .downArrow, [.command, .option], "⌥⌘↓") { self.splitNextTab(vertical: false) }
        add("separate", "Separate Split", enabled: activeSplit != nil) { self.separateSplit() }
        add("move-up", "Move Tab Up", .upArrow, [.command, .option, .control], "⌃⌥⌘↑") { self.reorderActiveTab(-1) }
        add("move-down", "Move Tab Down", .downArrow, [.command, .option, .control], "⌃⌥⌘↓") { self.reorderActiveTab(1) }
        let branch = selectedBranchID, branchCollapsed = branch.map(collapsedBranchIDs.contains) ?? false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        add("collapse-branch", "Collapse Branch", .leftArrow, [.command, .option, .control], "⌃⌥⌘←", enabled: branch != nil && !branchCollapsed) {
            withAnimation(SidebarMotion.branch(reduceMotion: reduceMotion)) { self.setSelectedBranch(collapsed: true) }
        }
        add("expand-branch", "Expand Branch", .rightArrow, [.command, .option, .control], "⌃⌥⌘→", enabled: branch != nil && branchCollapsed) {
            withAnimation(SidebarMotion.branch(reduceMotion: reduceMotion)) { self.setSelectedBranch(collapsed: false) }
        }
        add("pinned-folder", "New Pinned Folder") { self.createFolder(section: .pinned) }
        add("peek", "Peek Current Page", enabled: page) { if let url = tab?.url { self.showPeek(url) } }
        add("fullscreen", "Enter / Exit Full Screen", "f", [.command, .control], "⌃⌘F") { NSApp.keyWindow?.toggleFullScreen(nil) }
        add("inspector", "Enable Web Inspector", enabled: page) {
            (tab?.engine as? WKWebEngine)?.webView.isInspectable = true
            self.notify("Web Inspector enabled. Right-click the page and choose Inspect Element.")
        }
        add("print", "Print…", "p", .command, "⌘P", enabled: page) {
            (tab?.engine as? WKWebEngine)?.webView.printOperation(with: NSPrintInfo.shared).run()
        }
        for number in 1...9 {
            add("tab-\(number)", "Select Tab \(number)", KeyEquivalent(Character(String(number))), .command, "⌘\(number)") { self.selectNumberedTab(number) }
        }
        for index in 0..<min(9, spaces.count) {
            let space = spaces[index]
            add("space-\(index + 1)", "Switch to \(space.name)", KeyEquivalent(Character(String(index + 1))), .control, "⌃\(index + 1)") { self.selectSpace(space.id) }
        }
        add("new-tab", "New Tab", "t", .command, "⌘T") { self.openCommandBar(newTab: true) }
        add("new-space", "New Space", "n", [.command, .option], "⌥⌘N") { self.createSpace(); self.spaceEditorPresented = true }
        add("new-window", "New Window", "n", .command, "⌘N") { BrowserWindows.open(sharing: self) }
        add("new-folder", "New Folder") { self.createFolder(section: .today) }
        add("split", "Split View", .rightArrow, [.command, .option, .shift], "⇧⌥⌘→", enabled: tab != nil && (activeSplit?.tabIDs.count ?? 1) < 4) {
            guard let original = self.activeTabID else { return }
            let next = self.newTab(activate: false)
            self.activate(original); self.openSplit(next.id)
        }
        add("sidebar", "Toggle Sidebar", "s", .command, "⌘S") { self.toggleSidebar() }
        add("pin", tab?.isPinned == true ? "Unpin Tab" : "Pin Tab", "p", [.command, .control], "⌃⌘P", enabled: page) { if let tab { self.pin(tab) } }
        add("favorite", "Add to Favorites", enabled: page && tab?.isFavorite == false) { if let tab { self.placeTab(tab.id, section: .favorites) } }
        add("rename", "Rename Tab", enabled: tab != nil) {
            guard let tab else { return }
            let alert = NSAlert(); alert.messageText = "Rename Tab"
            let field = NSTextField(string: tab.displayTitle); field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
            alert.accessoryView = field; alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            if alert.runModal() == .alertFirstButtonReturn { self.renameTab(tab, name: field.stringValue) }
        }
        add("move-space", "Move Tab to Space ▸", enabled: tab != nil && spaces.count > 1) { self.openCommandBar(newTab: true); self.commandBarDraft = "Move Tab to Space ▸" }
        add("archive-all", "Archive All Tabs", enabled: visibleTabs.contains { $0.section == .today }) { self.archiveToday() }
        add("tidy-tabs", "Tidy Stale Tabs") { self.tidyToday() }
        add("copy-url", "Copy URL", "c", [.command, .shift], "⇧⌘C", enabled: page) { copyLink(tab?.url) }
        add("copy-markdown", "Copy URL as Markdown", "c", [.command, .shift, .option], "⌥⇧⌘C", enabled: page) {
            guard let tab, let url = tab.url else { return }
            let title = tab.displayTitle.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString("[\(title)](<\(url.absoluteString)>)", forType: .string)
        }
        add("reload", "Reload", "r", .command, "⌘R", enabled: page) { self.reload() }
        add("find", "Find in Page", "f", .command, "⌘F", enabled: page) { self.findPresented = true; self.show(.web) }
        add("find-next", "Find Next", "g", .command, "⌘G", enabled: page && !findQuery.isEmpty) { self.findBackwards = false; self.findPresented = true; self.findRequest += 1 }
        add("find-previous", "Find Previous", "g", [.command, .shift], "⇧⌘G", enabled: page && !findQuery.isEmpty) { self.findBackwards = true; self.findPresented = true; self.findRequest += 1 }
        add("find-selection", "Use Selection for Find", "e", .command, "⌘E", enabled: page) {
            Task { if let selected = await tab?.engine.evaluateJavaScript("String(window.getSelection() || '')") as? String, !selected.isEmpty {
                self.findQuery = selected; self.findPresented = true
            } }
        }
        for (id, title, key, hint, factor) in [("zoom-in", "Zoom In", "=", "⌘=", 1.1), ("zoom-out", "Zoom Out", "-", "⌘−", 1 / 1.1), ("zoom-reset", "Zoom Reset", "0", "⌘0", 0.0)] {
            add(id, title, KeyEquivalent(Character(key)), .command, hint, enabled: page) {
                if let web = tab?.engine as? WKWebEngine { web.setZoom(SiteSettings.zoom(web.webView.pageZoom, factor: factor)) }
            }
        }
        add("dark", "Toggle Dark Mode", "l", [.command, .shift], "⇧⌘L") { self.toggleMode() }
        add("zoom-in-plus", "Zoom In (+)", "+", .command, "⌘+", enabled: page) {
            if let web = tab?.engine as? WKWebEngine { web.setZoom(SiteSettings.zoom(web.webView.pageZoom, factor: 1.1)) }
        }
        add("space-color", "Change Space Color") { self.spaceEditorPresented = true }
        add("route-site", "Route this site to space…", enabled: page && !isPrivate) {
            guard let host = tab?.url?.host else { return }
            let alert = NSAlert(); alert.messageText = "Route \(host) to space"
            let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
            picker.addItems(withTitles: self.spaces.map(\.name)); alert.accessoryView = picker
            alert.addButton(withTitle: "Add Rule"); alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn, let space = self.spaces[safe: picker.indexOfSelectedItem] {
                self.settings.routingRules.append(RoutingRule(pattern: "https://\(host)/*", spaceID: space.id))
                self.notify("Routing rule added")
            }
        }
        add("settings", "Open Settings", ",", .command, "⌘,") { self.settingsPresented = true }
        add("archive", "Open Archive", "a", [.command, .shift], "⇧⌘A") { self.archivePresented = true }
        add("library", "Open Library") {
            // The Library popover hangs off the sidebar footer; without a visible sidebar, open Threads instead.
            if self.layout == .sidebar && !self.sidebarCollapsed { self.libraryPresented = true } else { self.show(.threads) }
        }
        add("downloads", "Open Downloads") { self.downloadsPresented = true }
        add("threads", "Open Threads", "2", [.command, .option], "⌥⌘2") { self.show(.threads) }
        add("vault", "Open Vault", "4", [.command, .option], "⌥⌘4") { self.show(.vault) }
        add("board", "Open Board", "5", [.command, .option], "⌥⌘5", enabled: !isPrivate) { self.show(.board) }
        add("mail", "Open Mail", "3", [.command, .option], "⌥⌘3") { self.show(.mail) }
        add("ask", "Ask Graphene about this page", "k", .command, "⌘K", enabled: !isPrivate) { self.toggleKnowledge() }
        add("find-ask", "Ask on Page", "f", [.command, .shift], "⇧⌘F", enabled: page && !isPrivate) { self.sendToAsk("") }
        add("summarize", "Summarize page", enabled: page && !isPrivate) { self.sendToAsk("Summarize this page") }
        add("clear-site", "Clear browsing data for this site", enabled: page && !isPrivate) { self.clearCurrentSiteData() }
        add("pip", "Enter Picture in Picture", "p", [.command, .option], "⌥⌘P", enabled: page) { self.enterPictureInPicture() }
        add("reader", "Reader Mode", "r", [.command, .shift], "⇧⌘R", enabled: page) {
            if self.readerPresented { self.readerPresented = false; return }
            guard let tab, let url = tab.url else { return }
            Task { let text = await tab.engine.evaluateJavaScript(ReaderMode.extractor) as? String ?? ""; guard tab.url == url else { return }
                self.readerArticle = ReaderArticle(title: tab.displayTitle, url: url, text: text.isEmpty ? "No readable text on this page." : text)
                self.readerPresented = true }
        }
        add("save", "Save page to Vault", "d", .command, "⌘D", enabled: page && !isPrivate) { self.noteComposerPresented = true }
        add("export", "Export thread", enabled: commandThread != nil && !isPrivate) { if let thread = self.commandThread { self.exportThread(thread) } }
        add("layout", "Switch layout") { self.layout = self.layout == .sidebar ? .topTabs : .sidebar }
        return actions
    }

    var commandThread: KnowledgeGraph.Thread? {
        currentThreads.first { $0.id == (selectedThreadID ?? activeTab?.currentThreadID) } ?? currentThreads.first
    }
    func resumeThread(_ thread: KnowledgeGraph.Thread) {
        guard let node = thread.nodes.last, let url = URL(string: node.url) else { return }
        let tab = newTab(); tab.currentNodeID = node.id; tab.currentThreadID = thread.id; tab.resumeThreadID = thread.id; tab.load(url)
    }
    func exportThread(_ thread: KnowledgeGraph.Thread) {
        var text = "# \(thread.title)\n\n\(thread.start.formatted(date: .long, time: .shortened))\n\n"
        for node in thread.nodes {
            text += "## [\(node.title)](\(node.url))\n\n\(node.snippet)\n\n"
            for note in vault.annotations(forURL: node.url) { text += "> \(note.text)\n\n\(note.note)\n\n" }
        }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Graphene thread.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8); notify("Thread exported") }
        catch { notify("Couldn’t export: \(error.localizedDescription)") }
    }
    func clearCurrentSiteData() {
        guard let tab = activeTab, let host = tab.url?.host, let engine = tab.engine as? WKWebEngine else { return }
        let alert = NSAlert(); alert.messageText = "Clear browsing data for \(host)?"
        alert.informativeText = "Remove cookies, caches and captured history for this host and its subdomains. WebKit groups some storage by parent domain, which can also sign sibling sites out. Vault notes are kept."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Clear Data")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let store = engine.webView.configuration.websiteDataStore
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let matches = records.filter { $0.displayName == host || $0.displayName.hasSuffix("." + host) || host.hasSuffix("." + $0.displayName) }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matches) {
                Task { @MainActor in self.forgetSite(host); self.notify("Site data cleared") }
            }
        }
    }
    func sendToAsk(_ query: String) {
        guard !isPrivate else { return }
        askRequest = AskRequest(query: query, tabIDs: Array(Set(commandContextIDs + (attachedSources.isEmpty ? (activeTabID.map { [$0] } ?? []) : []))))
        commandContextIDs = []; knowledgeThreadID = nil; commandBarPresented = false
        knowledgeSearchPresented = true; show(.web)
    }
    func openInSystemBrowser(_ url: URL) {
        guard let target = NSWorkspace.shared.urlForApplication(toOpen: url) else { notify("No browser is available."); return }
        if Bundle(url: target)?.bundleIdentifier == Bundle.main.bundleIdentifier {
            guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else { notify("Choose another default browser in macOS Settings."); return }
            NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
        } else { NSWorkspace.shared.open(url) }
    }
}

struct AskRequest: Identifiable {
    let id = UUID()
    let query: String
    let tabIDs: [UUID]
}

enum BrowserLayout: String, Codable, CaseIterable {
    case sidebar, topTabs
    var title: String { self == .sidebar ? "Sidebar (Arc)" : "Top tabs (Dia)" }
}
