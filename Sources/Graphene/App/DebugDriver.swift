import Foundation
import AppKit

/// A dev-only command channel so the app can be driven deterministically without
/// GUI automation: write a line to `cmd.txt` and it runs a real app action. Only
/// active when launched with GRAPHENE_DEBUG=1.
extension AppState {
    func startDebugDriverIfEnabled() {
        guard ProcessInfo.processInfo.environment["GRAPHENE_DEBUG"] == "1" else { return }
        let cmdFile = Paths.root.appendingPathComponent("cmd.txt")
        try? "".write(to: cmdFile, atomically: true, encoding: .utf8)
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let content = try? String(contentsOf: cmdFile, encoding: .utf8),
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                try? "".write(to: cmdFile, atomically: true, encoding: .utf8)
                for line in content.split(separator: "\n") {
                    let app = BrowserFocus.shared.app ?? AppState.shared
                    if !app.isPrivate { app.runDebugCommand(String(line)) }
                }
            }
        }
    }

    private func runDebugCommand(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let cmd = parts.first else { return }
        let arg = parts.count > 1 ? parts[1] : ""
        let window = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
        switch cmd {
        case "wp5-import-arc":
            Task {
                let output: String
                do { output = await applyImport(try Importer.read(.arc, file: arg.isEmpty ? nil : URL(fileURLWithPath: arg))) }
                catch { output = "Import failed: \(error.localizedDescription)" }
                try? output.write(to: Paths.root.appendingPathComponent("import-result.txt"), atomically: true, encoding: .utf8)
            }
        case "wp5-dismiss": siteControlsTabID = nil; boostHost = nil; readerPresented = false
        case "wp5-blocking":
            if let tab = activeTab, let host = tab.url?.host {
                var site = sites.site(host); site.blocking = arg == "on"
                do { try sites.set(site, host: host); Task { await (tab.engine as? WKWebEngine)?.applyBlocking(host: host) } }
                catch { notify(error.localizedDescription) }
            }
        case "wp5-boost-css":
            if let host = activeTab?.url?.host {
                var boost = boosts.boost(host); boost.css = arg
                do { try boosts.save(boost); for tab in tabs { (tab.loadedEngine as? WKWebEngine)?.refreshBoosts() } }
                catch { notify(error.localizedDescription) }
            }
        case "wp5-profile":
            let profile = profiles.first { $0.name == arg } ?? Profile(name: arg)
            if !profiles.contains(where: { $0.id == profile.id }) { profiles.append(profile) }
            if let i = spaces.firstIndex(where: { $0.id == activeSpaceID }) { spaces[i].profileID = profile.id }; persist()
        case "wp5-state":
            if let tab = activeTab, let engine = tab.engine as? WKWebEngine {
                let state: [String: Any] = ["zoom": engine.webView.pageZoom, "blocking": engine.blockingActive,
                    "blockerError": engine.blockerError ?? "", "article": tab.articleDetected,
                    "profile": tab.profileID.uuidString, "certificate": engine.certificateSummary ?? "",
                    "boostCSS": boosts.boost(tab.url?.host ?? "").renderedCSS,
                    "zapCount": boosts.boost(tab.url?.host ?? "").selectors.count]
                if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: Paths.root.appendingPathComponent("wp5-state.json"), options: .atomic) }
            }
        case "command": commandActions.first { $0.id == arg }?.run()
        case "activate": window?.makeKeyAndOrderFront(nil); NSApp.activate()
        case "external": if let url = URL(string: arg) { openExternalURL(url) }
        case "settings": settingsPage = arg.isEmpty ? "General" : arg; settingsPresented = true
        case "board-text": boards.upsert(BoardItem(spaceID: activeSpaceID, title: "Note", text: arg))
        case "board-link": if let tab = activeTab { var item = BoardItem(spaceID: activeSpaceID, title: tab.displayTitle, url: tab.url?.absoluteString); item.x = 300; boards.upsert(item) }
        case "toast-undo": if let toast = toasts.items.first, toast.actionTitle == "Undo" { toast.action?(); toasts.dismiss(toast.id) }
        case "peek": sidebarPeek = arg != "close"
        case "create-space": createSpace(name: arg)
        case "rename-space": renameSpace(activeSpaceID, name: arg)
        case "delete-space": deleteSpace(activeSpaceID)
        case "edit-space": spaceEditorPresented = arg != "close"
        case "theme":
            if let data = arg.data(using: .utf8), let theme = try? JSONDecoder().decode(SpaceTheme.self, from: data) { updateSpaceTheme(theme) }
        case "icon": updateSpaceTheme(activeSpace.theme ?? SpaceTheme(), icon: arg)
        case "pin": if let tab = activeTab { pin(tab) }
        case "favorite": if let tab = activeTab { placeTab(tab.id, section: .favorites) }
        case "today": if let tab = activeTab { placeTab(tab.id, section: .today) }
        case "rename-tab": if let tab = activeTab { renameTab(tab, name: arg) }
        case "folder":
            let section = activeTab?.section == .pinned ? TabSection.pinned : .today
            let folder = createFolder(name: arg, section: section)
            if let tab = activeTab { placeTab(tab.id, section: section, folderID: folder) }
        case "folder-toggle": if let folder = folders.last { updateFolder(folder.id, collapsed: !folder.collapsed) }
        case "reset-pin": if let tab = activeTab { resetPinnedTab(tab) }
        case "archive": archiveToday()
        case "reopen": reopenClosedTab()
        case "show-archive": archivePresented = arg != "close"
        case "split": if let index = Int(arg), let tab = tabs[safe: index] { openSplit(tab.id) }
        case "separate": separateSplit()
        case "page-peek": if arg == "close" { closePeek() } else if let url = URL(string: arg) { showPeek(url) }
        case "little": if let url = URL(string: arg) { openExternalURL(url) }
        case "mru": cycleRecentTab(Int(arg) ?? 1)
        case "mru-finish": finishTabSwitch()
        case "pip": enterPictureInPicture()
        case "new-window": BrowserWindows.open(sharing: self)
        case "private-window": BrowserWindows.openPrivate()
        case "ask": toggleKnowledge()
        case "fullscreen": window?.toggleFullScreen(nil)
        case "window-size":
            let values = arg.split(separator: " ").compactMap { Double($0) }
            if values.count == 2 { window?.setContentSize(NSSize(width: values[0], height: values[1])) }
        case "js":
            if let tab = activeTab {
                Task {
                    let result = await tab.engine.evaluateJavaScript(arg)
                    try? String(describing: result ?? "null").write(to: Paths.root.appendingPathComponent("js-result.txt"), atomically: true, encoding: .utf8)
                }
            }
        case "snapshot":
            persist()
            let snapshot: [String: Any] = [
                "activeSpace": activeSpace.name, "activeTab": activeTab?.displayTitle ?? "",
                "surface": activeSurface.rawValue, "onboarding": onboardingPresented,
                "boardCount": boards.items(in: activeSpaceID).count, "toastTitles": toasts.items.map(\.title),
                "archiveCount": archivedTabs.count, "archivePresented": archivePresented,
                "peekURL": peekTab?.url?.absoluteString ?? "", "splits": splits.map { $0.tabIDs.map(\.uuidString) },
                "mru": switcherIDs.map(\.uuidString), "mediaTab": mediaTabID?.uuidString ?? "",
                "sidebarWidth": sidebarWidth, "sidebarCollapsed": sidebarCollapsed, "sidebarPeek": sidebarPeek,
                "tabs": tabs.map { ["id": $0.id.uuidString, "title": $0.displayTitle, "section": $0.section.rawValue, "space": $0.spaceID?.uuidString ?? "", "folder": $0.folderID?.uuidString ?? ""] },
                "window": window.map { ["x": $0.frame.minX, "y": $0.frame.minY, "width": $0.frame.width, "height": $0.frame.height] } ?? [:]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: Paths.root.appendingPathComponent("snapshot.json"), options: .atomic)
            }
        case "quit": NSApp.terminate(nil)
        case "go":       submit(arg)
        case "new":      newTab()
        case "select":   if let i = Int(arg), let t = tabs[safe: i] { activate(t.id) }
        case "close":    if let id = activeTabID { closeTab(id) }
        case "surface":  if let s = Surface(rawValue: arg) { activeSurface = s }
        case "space":    if let i = Int(arg), spaces.indices.contains(i) { selectSpace(spaces[i].id) }
        case "color":    if let c = SpaceColor(rawValue: arg) { setColor(c) }
        case "mode":     if let mode = ThemeMode(rawValue: arg) { self.mode = mode }
        case "sidebar":
            if arg == "toggle" { toggleSidebar() }
            else if let w = Double(arg) { resizeSidebar(CGFloat(w)) }
        case "annotate":
            if let tab = activeTab {
                self.tab(tab, didCapture: CapturedAnnotation(
                    text: arg, note: "", url: tab.url, title: tab.title, context: ""))
            }
        default: break
        }
    }
}
