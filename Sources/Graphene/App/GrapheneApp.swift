import SwiftUI
import AppKit

@main
struct GrapheneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState.shared
    @StateObject private var mail = MailStore()

    var body: some Scene {
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        (BrowserFocus.shared.app.flatMap { $0.isPrivate ? nil : $0 } ?? AppState.shared).persist()
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
        CommandGroup(replacing: .newItem) {
            buttons(["new-tab", "new-window", "private-window", "new-space", "location"])
            Divider()
            buttons(["close-tab", "close-window"])
        }
        CommandGroup(after: .newItem) {
            buttons(["save", "export", "save-page", "print", "system-browser"])
        }
        CommandGroup(after: .textEditing) { buttons(["find", "find-next", "find-previous", "find-selection"]) }
        CommandGroup(after: .sidebar) {
            buttons(["reload", "stop", "zoom-in", "zoom-in-plus", "zoom-out", "zoom-reset", "reader", "sidebar", "layout", "fullscreen"])
            Menu("Appearance") { actionButton("dark"); actionButton("space-color") }
            buttons(["web", "threads", "vault", "mail", "board", "ask", "summarize", "downloads"])
            Menu("Developer") { actionButton("inspector") }
            Menu("Site") { buttons(["site-controls", "boost", "zap", "clear-site"]) }
        }
        CommandMenu("History") {
            buttons(["back", "forward", "home", "archive", "reopen"])
            Menu("Recently Closed") {
                ForEach(Array(app.archivedTabs.suffix(20).reversed()), id: \.archiveID) { entry in
                    Button(entry.title ?? entry.url ?? "Tab") { if let id = entry.archiveID { app.restoreArchive(id) } }
                }
            }
            Button("Show Full History") { app.show(.threads) }
        }
        CommandMenu("Spaces") {
            ForEach(0..<min(9, app.spaces.count), id: \.self) { index in actionButton("space-\(index + 1)") }
            buttons(["new-space", "next-space", "previous-space", "route-site"])
        }
        CommandMenu("Tabs") {
            buttons(["next-tab", "previous-tab", "next-tab-arrow", "previous-tab-arrow", "mru-next", "mru-previous"])
            Menu("Select Tab") { ForEach(1..<10, id: \.self) { number in actionButton("tab-\(number)") } }
            Divider()
            buttons(["pin", "favorite", "rename", "new-folder", "pinned-folder", "tidy-tabs", "archive-all", "copy-url", "copy-markdown", "pip", "peek"])
            Menu("Split View") { buttons(["split", "split-vertical", "split-horizontal", "separate"]) }
            buttons(["move-up", "move-down"])
            Menu("Move Tab to Space") {
                ForEach(app.spaces.filter { $0.id != app.activeTab?.spaceID }) { space in
                    Button(space.name) { if let tab = app.activeTab { app.placeTab(tab.id, section: tab.section, spaceID: space.id) } }
                }
            }.disabled(app.activeTab == nil)
        }
        CommandGroup(replacing: .appSettings) { actionButton("settings") }
        CommandGroup(replacing: .help) {
            Button("Graphene Help") {
                let alert = NSAlert(); alert.messageText = "Graphene"
                alert.informativeText = "⌘T opens navigation and commands. ⌘D saves a page to Vault. ⌘K searches sources and asks on-device questions. ⌥⌘5 opens this space’s Board. Settings → Shortcuts lists and customizes browser commands."
                alert.runModal()
            }
        }
    }

    @ViewBuilder private func buttons(_ ids: [String]) -> some View { ForEach(ids, id: \.self) { actionButton($0) } }
    @ViewBuilder private func actionButton(_ id: String) -> some View {
        if let action = app.allCommandActions.first(where: { $0.id == id }) { ActionMenuButton(action: action) }
    }
}

struct ActionMenuButton: View {
    let action: BrowserAction
    var body: some View {
        if let key = action.key { Button(action.title) { action.run() }.keyboardShortcut(key, modifiers: action.modifiers).disabled(!action.enabled) }
        else { Button(action.title) { action.run() }.disabled(!action.enabled) }
    }
}
