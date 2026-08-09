import SwiftUI
import AppKit

@main
struct GrapheneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 940, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { GrapheneCommands(app: app) }
    }
}

/// An SPM executable launches without a proper activation policy, so set it here
/// and bring the window forward — otherwise `swift run` opens nothing focusable.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.persist()
        AppState.shared.graph.save()
    }
}

/// Keyboard shortcuts, routed to the shared app state.
struct GrapheneCommands: Commands {
    let app: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { app.newTab() }.keyboardShortcut("t")
            Button("Close Tab") { if let id = app.activeTabID { app.closeTab(id) } }.keyboardShortcut("w")
        }
        CommandMenu("View") {
            Button("Reload") { app.reload() }.keyboardShortcut("r")
            Button("Back") { app.goBack() }.keyboardShortcut("[")
            Button("Forward") { app.goForward() }.keyboardShortcut("]")
            Divider()
            Button(app.showGraph ? "Hide Graph" : "Graph") { app.showGraph.toggle() }.keyboardShortcut("g")
            Button("Annotations") { app.showAnnotations.toggle() }.keyboardShortcut("d")
            Divider()
            Button("Select Next Tab") { app.selectRelativeTab(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Select Previous Tab") { app.selectRelativeTab(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }
}
