import SwiftUI
import AppKit

@main
struct GrapheneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState.shared
    @StateObject private var mail = MailStore()

    init() { StartupTrace.mark("GrapheneApp.init") }

    var body: some Scene {
        let _ = StartupTrace.once("App.body")
        WindowGroup {
            BrowserWindowRoot(state: WindowState.initial())
                .environmentObject(mail)
                .frame(minWidth: 940, minHeight: 620)
                .frame(idealWidth: 1280, idealHeight: 820)
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands { GrapheneCommands(defaultApp: app) }
        SwiftUI.Settings {
            SettingsView().environmentObject(app).environmentObject(mail)
        }
    }
}

/// An SPM executable launches without a proper activation policy, so set it here
/// and bring the window forward — otherwise `swift run` opens nothing focusable.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        let app = BrowserFocus.shared.app.flatMap { $0.isPrivate ? nil : $0 } ?? AppState.shared
        for url in urls { app.openExternalURL(url) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        StartupTrace.mark("applicationDidFinishLaunching")
        // The content blocker loads while the first window draws, not when the first page asks.
        MainActor.assumeIsolated { ContentBlocker.prewarm() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        (BrowserFocus.shared.app.flatMap { $0.isPrivate ? nil : $0 } ?? AppState.shared).persist()
        SessionWriter.shared.flush()
        AppState.shared.graph.save()
    }
}

/// Keyboard shortcuts, routed to the shared app state.
struct GrapheneCommands: Commands {
    @ObservedObject var defaultApp: AppState
    @FocusedObject private var focusedApp: AppState?
    @ObservedObject private var focus = BrowserFocus.shared
    private var app: AppState { focus.app ?? focusedApp ?? defaultApp }

    var body: some Commands {
        let _ = StartupTrace.once("menu commands body")
        // One action table per menu update: the body re-runs on every AppState change, and
        // building the table per menu item (~90 lookups) made each change pay ~90 full builds.
        let actions = CommandMenuTable(app.allCommandActions)
        CommandGroup(replacing: .newItem) {
            buttons(["new-tab", "new-window", "private-window", "new-space", "location"], actions)
            Divider()
            buttons(["close-tab", "close-window"], actions)
        }
        CommandGroup(after: .newItem) {
            buttons(["save", "export", "save-page", "print", "system-browser"], actions)
        }
        CommandGroup(after: .textEditing) { buttons(["find", "find-next", "find-previous", "find-selection"], actions) }
        CommandGroup(after: .sidebar) {
            buttons(["reload", "stop", "zoom-in", "zoom-in-plus", "zoom-out", "zoom-reset", "reader", "sidebar", "layout", "fullscreen"], actions)
            Menu("Appearance") { actionButton("dark", actions); actionButton("space-color", actions) }
            buttons(["web", "threads", "vault", "mail", "board", "ask", "summarize", "downloads"], actions)
            Menu("Developer") { actionButton("inspector", actions) }
            Menu("Site") { buttons(["site-controls", "boost", "zap", "clear-site"], actions) }
        }
        CommandMenu("History") {
            buttons(["back", "forward", "home", "archive", "reopen"], actions)
            Menu("Recently Closed") {
                ForEach(Array(app.archivedTabs.suffix(20).reversed()), id: \.archiveID) { entry in
                    Button(entry.title ?? entry.url ?? "Tab") { if let id = entry.archiveID { app.restoreArchive(id) } }
                }
            }
            Button("Show Full History") { app.show(.threads) }
        }
        CommandMenu("Spaces") {
            ForEach(0..<min(9, app.spaces.count), id: \.self) { index in actionButton("space-\(index + 1)", actions) }
            buttons(["new-space", "next-space", "previous-space", "route-site"], actions)
        }
        CommandMenu("Tabs") {
            buttons(["next-tab", "previous-tab", "next-tab-arrow", "previous-tab-arrow", "mru-next", "mru-previous"], actions)
            Menu("Select Tab") { ForEach(1..<10, id: \.self) { number in actionButton("tab-\(number)", actions) } }
            Divider()
            buttons(["pin", "favorite", "rename", "new-folder", "pinned-folder", "tidy-today", "archive-stale", "archive-all", "copy-url", "copy-markdown", "pip", "peek"], actions)
            Menu("Split View") { buttons(["split", "split-vertical", "split-horizontal", "separate"], actions) }
            buttons(["move-up", "move-down", "collapse-branch", "expand-branch"], actions)
            Menu("Move Tab to Space") {
                ForEach(app.spaces.filter { $0.id != app.activeTab?.spaceID }) { space in
                    Button(space.name) { if let tab = app.activeTab { app.placeTab(tab.id, section: tab.section, spaceID: space.id) } }
                }
            }.disabled(app.activeTab == nil)
        }
        CommandGroup(replacing: .appSettings) { actionButton("settings", actions) }
        CommandGroup(replacing: .help) {
            Button("Graphene Help") {
                let alert = NSAlert(); alert.messageText = "Graphene"
                alert.informativeText = "⌘T opens navigation and commands. ⌘D saves a page to Vault. ⌘K searches sources and asks on-device questions. ⌥⌘5 opens this space’s Board. Settings → Shortcuts lists and customizes browser commands."
                alert.runModal()
            }
        }
    }

    @ViewBuilder private func buttons(_ ids: [String], _ actions: CommandMenuTable) -> some View { ForEach(ids, id: \.self) { actionButton($0, actions) } }
    @ViewBuilder private func actionButton(_ id: String, _ actions: CommandMenuTable) -> some View {
        if let action = actions[id] { ActionMenuButton(action: action) }
    }
}

/// The command actions of one menu update, looked up by id.
struct CommandMenuTable {
    private let byID: [String: BrowserAction]
    init(_ actions: [BrowserAction]) { byID = Dictionary(actions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
    subscript(id: String) -> BrowserAction? { byID[id] }
}

struct ActionMenuButton: View {
    let action: BrowserAction
    var body: some View {
        if let key = action.key { Button(action.title) { action.run() }.keyboardShortcut(key, modifiers: action.modifiers).disabled(!action.enabled) }
        else { Button(action.title) { action.run() }.disabled(!action.enabled) }
    }
}
