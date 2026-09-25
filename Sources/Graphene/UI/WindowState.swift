import SwiftUI
import AppKit

@MainActor
final class BrowserFocus: ObservableObject {
    static let shared = BrowserFocus()
    @Published var app: AppState?
    weak var window: NSWindow?
}

@MainActor
final class WindowState: ObservableObject {
    private static var primaryClaimed = false
    static func initial() -> WindowState {
        let app = primaryClaimed ? AppState(sharing: AppState.shared) : AppState.shared
        primaryClaimed = true
        return WindowState(app: app)
    }
    let app: AppState
    weak var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?
    init(app: AppState) { self.app = app }
    var activeTabID: UUID? { get { app.activeTabID } set { app.activeTabID = newValue } }
    var activeSpaceID: UUID { get { app.activeSpaceID } set { app.selectSpace(newValue) } }
    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        if window.isKeyWindow { BrowserFocus.shared.app = app; BrowserFocus.shared.window = window }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { BrowserFocus.shared.app = self.app; BrowserFocus.shared.window = self.window } }
        }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if BrowserFocus.shared.app === self.app { BrowserFocus.shared.app = nil; BrowserFocus.shared.window = nil }
                self.app.closePeek()
                self.app.persist()
                self.app.activeTabID = nil
                if self.app.isPrivate {
                    for tab in self.app.tabs { tab.loadedEngine?.stop(); tab.coordinator = nil }
                    self.app.tabs = []
                    return
                }
                // Tabs outlive windows; route surviving navigation to the primary coordinator.
                for tab in self.app.tabs where tab.coordinator === self.app { tab.coordinator = AppState.shared }
            }
        }
    }
    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    }
}

struct BrowserWindowRoot: View {
    @StateObject var state: WindowState
    var body: some View {
        RootView().environmentObject(state.app).environmentObject(state)
            .focusedSceneObject(state.app)
            .frame(minWidth: 940, minHeight: 620)
    }
}

@MainActor
final class BrowserWindows: NSObject, NSWindowDelegate {
    private static var controllers: [Int: BrowserWindows] = [:]
    private let window: NSWindow
    private let state: WindowState
    private let mail = MailStore()
    static func openPrivate() {
        let controller = BrowserWindows(app: AppState(privateMode: true))
        controllers[controller.window.windowNumber] = controller
        controller.window.center(); controller.window.makeKeyAndOrderFront(nil)
    }
    static func open(sharing app: AppState, moving tabID: UUID? = nil) {
        if app.isPrivate { openPrivate(); return }
        let state = AppState(sharing: app)
        if let tabID {
            let empty = state.activeTabID
            state.activate(tabID)
            if let empty { state.tabs.removeAll { $0.id == empty } }
        }
        let controller = BrowserWindows(app: state)
        controllers[controller.window.windowNumber] = controller
        controller.window.center(); controller.window.makeKeyAndOrderFront(nil)
    }
    private init(app: AppState) {
        state = WindowState(app: app)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "Graphene"; window.isReleasedWhenClosed = false; window.delegate = self
        window.contentView = NSHostingView(rootView: BrowserWindowRoot(state: self.state).environmentObject(mail))
        state.attach(window)
    }
    func windowWillClose(_ notification: Notification) { Self.controllers[window.windowNumber] = nil }
}
