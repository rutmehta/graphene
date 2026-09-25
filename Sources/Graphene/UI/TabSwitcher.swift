import SwiftUI
import AppKit

struct TabSwitcher: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(app.switcherIDs.enumerated()), id: \.element) { index, id in
                        if let tab = app.tabs.first(where: { $0.id == id }) {
                            VStack(spacing: 10) {
                                Favicon(host: tab.url?.host, size: 28, url: tab.url)
                                Text(tab.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            }.frame(width: 120, height: 84).padding(8)
                                .background(index == app.switcherIndex ? app.pal.active : app.pal.hover, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(index == app.switcherIndex ? app.pal.accentText : app.pal.hairline))
                                .id(index).onTapGesture { app.switcherIndex = index; app.finishTabSwitch() }
                        }
                    }
                }.padding(12)
            }.frame(maxWidth: 650).frame(height: 130)
                .background(app.pal.elev, in: RoundedRectangle(cornerRadius: 12)).shadow(color: app.pal.shadow, radius: 20)
                .onChange(of: app.switcherIndex) { _, index in proxy.scrollTo(index) }
        }
    }
}

struct TabKeyboardMonitor: NSViewRepresentable {
    let app: AppState
    func makeNSView(context: Context) -> MonitorView { MonitorView(app: app) }
    func updateNSView(_ nsView: MonitorView, context: Context) {}
    final class MonitorView: NSView {
        let app: AppState
        private var monitor: Any?
        init(app: AppState) {
            self.app = app
            super.init(frame: .zero)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
                guard let self, self.window?.isKeyWindow == true else { return event }
                if event.type == .leftMouseDown && app.activeSplit != nil {
                    for tab in app.splitTabs {
                        guard let host = tab.loadedEngine?.hostView, host.window === event.window else { continue }
                        if host.bounds.contains(host.convert(event.locationInWindow, from: nil)), tab.id != app.activeTabID { app.activate(tab.id); break }
                    }
                }
                if event.type == .flagsChanged && event.modifierFlags.intersection([.control, .command, .option]).isEmpty && !app.switcherIDs.isEmpty {
                    app.finishTabSwitch()
                }
                if event.type == .keyDown {
                    let flags = event.modifierFlags
                    let pressed = CommandShortcut(key: event.charactersIgnoringModifiers ?? "", command: flags.contains(.command), option: flags.contains(.option), control: flags.contains(.control), shift: flags.contains(.shift))
                    if let action = app.commandActions.first(where: { ["mru-next", "mru-previous"].contains($0.id) && CommandShortcut(action: $0) == pressed }) { action.run(); return nil }
                }
                if event.type == .keyDown && event.keyCode == 53 && !app.switcherIDs.isEmpty { app.switcherIDs = []; return nil }
                if event.type == .keyDown && event.keyCode == 53 && app.peekTab != nil { app.closePeek(); return nil }
                if event.type == .keyDown && event.keyCode == 49, let id = app.hoveredTabID,
                   let tab = app.tabs.first(where: { $0.id == id && $0.isPinned }), let url = tab.url {
                    app.showPeek(url); return nil
                }
                return event
            }
        }
        required init?(coder: NSCoder) { nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
