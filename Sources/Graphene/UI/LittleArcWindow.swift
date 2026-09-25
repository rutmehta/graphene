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
        panel = LittlePanel(contentRect: NSRect(origin: .zero, size: ShellLayout.littleArcSize), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        panel.title = "Little Graphene"; WindowAccessor.flattenTitlebar(panel)
        panel.backgroundColor = NSColor(app.pal.chromeTop)
        panel.isReleasedWhenClosed = false; panel.level = .floating; panel.delegate = self
        panel.contentView = NSHostingView(rootView: LittleArcRoot(tab: tab, close: { [weak self] in self?.panel.close() })
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

/// Little Arc's content: the space's `chromeTop` plane with a page card inset `windowGap`.
/// The card springs in (scale 0.96 → 1 with opacity); Reduce Motion fades only.
struct LittleArcRoot: View {
    static let appearScale: CGFloat = 0.96
    @EnvironmentObject var app: AppState
    @ObservedObject var tab: Tab
    var close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    var body: some View {
        TransientBrowser(tab: tab, little: true, close: close)
            .webPageCard(tab)
            .padding(ShellLayout.windowGap)
            .scaleEffect(shown || reduceMotion ? 1 : Self.appearScale)
            .opacity(shown ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(app.pal.chromeTop)
            .ignoresSafeArea()
            .environment(\.colorScheme, app.pal.isDark ? .dark : .light)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.8)) { shown = true }
            }
    }
}

/// The page inside Peek and Little Arc: a 32pt toolbar with the URL, then the page.
/// Peek offers "Open as tab"; Little Arc offers "Move to space".
struct TransientBrowser: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var tab: Tab
    var little = false
    var close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            PageToolbar(tab: tab, reservesTrafficLights: little, cardOriginX: ShellLayout.windowGap,
                        backgroundTap: little ? nil : {}, fill: little ? nil : app.pal.elev) {
                if little {
                    Menu {
                        ForEach(app.spaces) { space in Button(space.name) { promote(space.id) } }
                    } label: { ToolbarGlyph(system: "rectangle.stack.badge.plus") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("Move to space").accessibilityLabel("Move to space").accessibilityIdentifier("little.moveToSpace")
                } else {
                    Button { promote(app.activeSpaceID) } label: {
                        Text("Open as tab").font(ShellType.label).foregroundStyle(app.pal.ink2)
                            .padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.controlSize)
                            .background(app.pal.fill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                    }.buttonStyle(.plain).accessibilityIdentifier("peek.openAsTab").accessibilityLabel("Open as tab").accessibilityAddTraits(.isButton)
                    ToolbarGlyphButton(title: "Close preview", system: "xmark", identifier: "peek.close", action: close)
                }
            }
            WebContainer(tab: tab)
        }.foregroundStyle(app.pal.ink).tint(app.pal.accent)
            .onExitCommand(perform: close)
    }
    private func promote(_ space: UUID) {
        guard let url = tab.url else { return }
        app.selectSpace(space); app.openTab(url: url, parent: nil, activate: true)
        close()
        (app.activeTab?.engine.hostView.window ?? NSApp.mainWindow)?.makeKeyAndOrderFront(nil)
    }
}
