import SwiftUI
import AppKit

/// The ⌃Tab switcher's open list and selection.
@MainActor
final class TabSwitcherModel: ObservableObject {
    @Published var ids: [UUID] = []
    @Published var index = 0
}

/// Shows the switcher while it is open; observes only the switcher, not the whole shell.
struct TabSwitcherOverlay: View {
    @ObservedObject var switcher: TabSwitcherModel
    var body: some View {
        if !switcher.ids.isEmpty { TabSwitcher(switcher: switcher) }
    }
}

/// ⌃Tab: a centred card of recent tabs, each a 96×60 thumbnail over a title row.
struct TabSwitcher: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var switcher: TabSwitcherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var thumbnails = ThumbnailCache.shared
    var body: some View {
        // One lookup table per body, not a linear search per tile; tiles are built lazily, so
        // a 200-tab profile draws the few on screen.
        let byID = Dictionary(app.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: ShellLayout.windowGap) {
                    ForEach(Array(switcher.ids.enumerated()), id: \.element) { index, id in
                        if let tab = byID[id] {
                            tile(tab, selected: index == switcher.index)
                                .id(index).onTapGesture { app.switcherIndex = index; app.finishTabSwitch() }
                        }
                    }
                }.padding(ShellLayout.windowGap)
            }
            .frame(maxWidth: ShellLayout.commandWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(app.pal.elev, in: RoundedRectangle(cornerRadius: ShellLayout.popoverRadius))
            .overlay(RoundedRectangle(cornerRadius: ShellLayout.popoverRadius).strokeBorder(app.pal.hairline, lineWidth: ShellLayout.hairline))
            .shadow(color: app.pal.pageShadow, radius: app.pal.pageShadowRadius, y: app.pal.pageShadowY)
            .onChange(of: switcher.index) { _, index in proxy.scrollTo(index) }
        }
        .accessibilityIdentifier("tabSwitcher")
    }

    private func tile(_ tab: Tab, selected: Bool) -> some View {
        let thumb = RoundedRectangle(cornerRadius: ShellLayout.rowRadius)
        return VStack(spacing: 0) {
            Group {
                if !tab.isPrivate, let image = thumbnails.images[tab.id] {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Favicon(host: tab.url?.host, size: ShellLayout.favoriteIconSize, url: tab.url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(app.pal.elevFill)
                }
            }
            .frame(width: ShellLayout.thumbnailSize.width, height: ShellLayout.thumbnailSize.height)
            .clipShape(thumb)
            .overlay(thumb.strokeBorder(selected ? app.pal.accent : app.pal.hairline, lineWidth: ShellLayout.hairline))
            HStack(spacing: ShellLayout.rowInsetLeading / 2) {
                Favicon(host: tab.url?.host, size: ShellLayout.iconSize, url: tab.url)
                Text(tab.displayTitle).font(ShellType.secondary).foregroundStyle(selected ? app.pal.ink : app.pal.ink2).lineLimit(1)
            }
            .frame(width: ShellLayout.thumbnailSize.width, height: ShellLayout.commandRowHeight)
        }
        .padding(.horizontal, ShellLayout.rowInsetLeading).padding(.top, ShellLayout.rowInsetLeading)
        .background(selected ? app.pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
        .animation(Motion.hover.reduced(reduceMotion), value: selected)
        .contentShape(RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
