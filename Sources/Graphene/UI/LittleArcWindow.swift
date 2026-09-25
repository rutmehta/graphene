import SwiftUI
import AppKit

enum ExternalLinkPolicy {
    enum Destination { case little, tab }
    static func destination(_ url: URL, littleEnabled: Bool) -> Destination? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return littleEnabled ? .little : .tab
    }
}

@MainActor
final class LittleArcWindow: NSObject, NSWindowDelegate {
    private static var windows: [UUID: LittleArcWindow] = [:]
    private let id = UUID()
    private let panel: NSPanel
    let tab: Tab
    static func open(_ url: URL, app: AppState) {
        let controller = LittleArcWindow(url: url, app: app)
        windows[controller.id] = controller
        controller.panel.center(); controller.panel.makeKeyAndOrderFront(nil)
    }
    private init(url: URL, app: AppState) {
        tab = Tab(engine: WKWebEngine(privateMode: app.isPrivate), privateMode: app.isPrivate)
        (tab.engine as? WKWebEngine)?.downloads = app.downloads
        panel = LittlePanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        panel.title = "Little Graphene"; panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false; panel.level = .floating; panel.delegate = self
        panel.contentView = NSHostingView(rootView: TransientBrowser(tab: tab, little: true, close: { [weak self] in self?.panel.close() })
            .environmentObject(app))
        tab.load(url)
    }
    func windowWillClose(_ notification: Notification) { tab.stop(); Self.windows[id] = nil }
    private final class LittlePanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { close() }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.keyCode == 53 || (event.charactersIgnoringModifiers == "w" && event.modifierFlags.contains(.command)) { close(); return true }
            return super.performKeyEquivalent(with: event)
        }
    }
}

struct TransientBrowser: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var tab: Tab
    var little = false
    var close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if little { Spacer().frame(width: 64) }
                IconButton("Back", system: "chevron.left") { tab.goBack() }.disabled(!tab.canGoBack)
                Text(tab.url?.absoluteString ?? "").font(.system(size: 11)).lineLimit(1).textSelection(.enabled)
                    .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 26)
                    .background(app.pal.hover, in: Capsule())
                if little {
                    Menu("Open in space") {
                        ForEach(app.spaces) { space in
                            Button(space.name) { promote(space.id) }
                        }
                    }.fixedSize()
                } else { Button("Open as tab") { promote(app.activeSpaceID) }.buttonStyle(.bordered) }
                IconButton("Close preview", system: "xmark", action: close)
            }.padding(8).background(app.pal.chromeBg)
            WebContainer(tab: tab)
        }.background(app.pal.ground).foregroundStyle(app.pal.ink).tint(app.pal.accentText)
            .onExitCommand(perform: close)
    }
    private func promote(_ space: UUID) {
        guard let url = tab.url else { return }
        app.selectSpace(space); app.openTab(url: url, parent: nil, activate: true)
        close()
        (app.activeTab?.engine.hostView.window ?? NSApp.mainWindow)?.makeKeyAndOrderFront(nil)
    }
}
