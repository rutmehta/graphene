import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Sidebar motion (arc-look.md §4): the space switch slides 24pt with a fade; hover and
/// selection fade in 100ms. Reduce Motion turns the slide into a 120ms fade.
enum SidebarMotion {
    static let hover = Animation.easeOut(duration: 0.10)
    static func spaceSwitch(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.18)
    }
    static func spaceTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .offset(x: ShellLayout.spaceSlide).combined(with: .opacity),
            removal: .offset(x: -ShellLayout.spaceSlide).combined(with: .opacity))
    }
    /// Branch collapse and expand (graphene-identity.md §4): child rows slide 8pt and fade over
    /// 160ms; Reduce Motion keeps only a 120ms fade.
    static let branchSlide: CGFloat = 8
    static func branch(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.16)
    }
    static func branchTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .offset(y: -branchSlide).combined(with: .opacity)
    }
}

/// The footer strip's glyphs, grouped around the centred space dots. Downloads joins the
/// trailing group so both sides stay two glyphs wide and the dots keep room at 180pt.
enum SidebarFooterItem: Hashable { case archive, library, downloads, newTab }

struct SidebarFooterLayout: Equatable {
    var leading: [SidebarFooterItem]
    var trailing: [SidebarFooterItem]
    init(downloadsActive: Bool) {
        leading = [.archive, .library]
        trailing = (downloadsActive ? [.downloads] : []) + [.newTab]
    }
    /// Both side groups take this width so the space dots stay centred in the strip.
    var sideWidth: CGFloat { CGFloat(max(leading.count, trailing.count)) * ShellLayout.controlSize }
}

struct Sidebar: View {
    var width: CGFloat = ShellLayout.sidebarDefault
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deleteSpace: SpaceInfo?
    @State private var draggingTab = false
    private var showsAddress: Bool { app.settings.addressPlacement == .sidebar && app.activeTab != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                SidebarGlyphButton("Hide sidebar (⌘S)", system: "sidebar.left", identifier: "sidebar.toggle") { app.toggleSidebar() }
                Spacer(minLength: 0)
            }.padding(.leading, ShellLayout.trafficReserve)
                .frame(height: ShellLayout.trafficBandHeight).background(WindowDragRegion())
            if showsAddress || app.isPrivate {
                VStack(alignment: .leading, spacing: 0) {
                    if showsAddress, let tab = app.activeTab { SidebarAddress(tab: tab) }
                    if app.isPrivate {
                        Label("Private", systemImage: "eye.slash").font(ShellType.label).foregroundStyle(app.pal.ink2)
                            .padding(.leading, ShellLayout.rowInsetLeading).frame(height: ShellLayout.spaceLabelHeight)
                    }
                }.padding(.horizontal, ShellLayout.windowGap).padding(.bottom, ShellLayout.sectionGap)
            }
            if app.archivePresented {
                SpaceLabel().padding(.horizontal, ShellLayout.windowGap)
                ArchiveView()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if hasContent(.favorites) || draggingTab { favorites.padding(.bottom, ShellLayout.sectionGap) }
                        SpaceLabel()
                        rows(.pinned)
                        TodayDivider()
                        VStack(spacing: ShellLayout.rowPitch - ShellLayout.rowHeight) {
                            NewTabRow()
                            rows(.today)
                        }
                    }.padding(.horizontal, ShellLayout.windowGap).padding(.bottom, ShellLayout.sectionGap)
                        .id(app.activeSpaceID)
                        .transition(SidebarMotion.spaceTransition(reduceMotion: reduceMotion))
                }.scrollIndicators(.hidden)
                    .animation(SidebarMotion.spaceSwitch(reduceMotion: reduceMotion), value: app.activeSpaceID)
                    .overlay(alignment: .top) { DragAutoScrollEdge(direction: -1).frame(height: 12) }
                    .overlay(alignment: .bottom) { DragAutoScrollEdge(direction: 1).frame(height: 12) }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: app.visibleTabs.map(\.id))
            }
            if let tab = app.tabs.first(where: { $0.id == app.mediaTabID }) {
                NowPlayingRow(tab: tab).padding(.horizontal, ShellLayout.windowGap)
            }
            VaultShelf()
            SidebarFooter(store: app.downloads, deleteSpace: $deleteSpace)
        }
        .background(SidebarSwipe { app.selectRelativeSpace($0) })
        .onDrop(of: [.utf8PlainText], isTargeted: $draggingTab) { _ in false }
        .alert("Delete \(deleteSpace?.name ?? "space")?", isPresented: Binding(get: { deleteSpace != nil }, set: { if !$0 { deleteSpace = nil } })) {
            Button("Cancel", role: .cancel) { deleteSpace = nil }
            Button("Delete", role: .destructive) { if let space = deleteSpace { app.deleteSpace(space.id) }; deleteSpace = nil }
        } message: { Text("Tabs and folders move to the previous space. The last space cannot be deleted.") }
    }

    /// Shown only when the space has favorites, or while a tab is dragged so it can become one.
    private var favorites: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ShellLayout.favoriteGap), count: ShellLayout.favoriteColumns(width: ShellLayout.sidebarContentWidth(width))), spacing: ShellLayout.favoriteGap) {
            ForEach(app.visibleTabs.filter { $0.section == .favorites }) { tab in
                SidebarTab(tab: tab, tile: true)
            }
        }.frame(minHeight: ShellLayout.favoriteHeight)
            .modifier(ShellDropTarget { payload in
                if let id = payloadID(payload, prefix: "tab:") { app.placeTab(id, section: .favorites, spaceID: app.activeSpaceID) }
            })
    }

    private func hasContent(_ section: TabSection) -> Bool {
        app.visibleTabs.contains { $0.section == section } || app.folders.contains { $0.spaceID == app.activeSpaceID && $0.section == section }
    }

    private func rows(_ section: TabSection) -> some View {
        // Only a space whose Today list has a child tab pays for provenance rows.
        let branches = section == .today ? app.todayProvenance() : nil
        return VStack(spacing: ShellLayout.rowPitch - ShellLayout.rowHeight) {
            ForEach(app.folders.filter { $0.spaceID == app.activeSpaceID && $0.section == section }) { folder in
                FolderRow(folder: folder)
            }
            if let branches, branches.hasBranches {
                ProvenanceRows(layout: branches)
            } else {
                ForEach(app.visibleTabs.filter { $0.section == section && $0.folderID == nil }) { tab in
                    SidebarTab(tab: tab).id(tab.id)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

/// Today rows as branches (graphene-identity.md §3.1): children indent `threadIndent` per
/// depth under their parent, joined by one hairline path per parent drawn behind the rows.
private struct ProvenanceRows: View {
    let layout: ProvenanceLayout
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let tabs = Dictionary(app.visibleTabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        VStack(spacing: ShellLayout.rowPitch - ShellLayout.rowHeight) {
            ForEach(layout.rows) { row in
                if let tab = tabs[row.id] {
                    SidebarTab(tab: tab, hiddenDescendants: row.collapsed ? row.descendants : nil)
                        .padding(.leading, CGFloat(row.indent) * ShellLayout.threadIndent)
                        .id(tab.id)
                        .transition(row.depth > 0 ? SidebarMotion.branchTransition(reduceMotion: reduceMotion) : .opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(alignment: .topLeading) { ThreadLines(connectors: layout.connectors(activeID: app.activeTabID)) }
        .background(BranchKeyMonitor(app: app))
    }
}

/// The connector paths: `threadLine`, or `threadLineActive` on the selected tab's branch.
private struct ThreadLines: View {
    let connectors: [ProvenanceConnector]
    @EnvironmentObject var app: AppState
    var body: some View {
        let pal = app.pal
        Canvas { context, _ in
            for connector in connectors {
                var path = Path(connector.vertical)
                for tick in connector.ticks { path.addRect(tick) }
                context.fill(path, with: .color(connector.active ? pal.threadLineActive : pal.threadLine))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// ⌥← / ⌥→ collapse and expand the selected Today row's branch. The keys belong to the
/// sidebar only after a click in the Today rows and until the next other key or click, so
/// word-wise caret movement in the page and in text fields keeps working.
private struct BranchKeyMonitor: NSViewRepresentable {
    let app: AppState
    func makeNSView(context: Context) -> MonitorView { MonitorView(app: app) }
    func updateNSView(_ nsView: MonitorView, context: Context) {}
    final class MonitorView: NSView {
        let app: AppState
        private var monitor: Any?
        private var engaged = false
        init(app: AppState) {
            self.app = app
            super.init(frame: .zero)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                if event.type == .leftMouseDown {
                    self.engaged = self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                    return event
                }
                let arrow = event.keyCode == 123 || event.keyCode == 124
                let modifiers = event.modifierFlags.intersection([.command, .control, .shift, .option])
                guard arrow, modifiers == .option, self.engaged, window.isKeyWindow,
                      let id = self.app.activeTabID, !self.app.branchChildren(of: id).isEmpty else {
                    if !event.modifierFlags.contains(.option) || !arrow { self.engaged = false }
                    return event
                }
                let collapse = event.keyCode == 123
                withAnimation(SidebarMotion.branch(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
                    self.app.setBranch(id, collapsed: collapse)
                }
                return nil
            }
        }
        required init?(coder: NSCoder) { nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// A 15pt `ink3` glyph in a `controlSize` target: the sidebar's toolbar and footer control.
struct SidebarGlyphButton: View {
    let title: String
    let system: String
    var font: Font
    var size: CGFloat
    var identifier: String
    var action: () -> Void
    init(_ title: String, system: String, font: Font = ShellType.glyph, size: CGFloat = ShellLayout.controlSize, identifier: String, action: @escaping () -> Void) {
        self.title = title; self.system = system; self.font = font; self.size = size; self.identifier = identifier; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(font).frame(width: size, height: size).contentShape(Rectangle())
        }.buttonStyle(ShellButtonStyle(muted: true))
            .help(title).accessibilityLabel(title).accessibilityIdentifier(identifier).accessibilityAddTraits(.isButton)
    }
}

/// Row hover for the sidebar's own button rows (New Tab): `rowHover`, `ink3`, 100ms fade.
private struct SidebarRowButtonStyle: ButtonStyle {
    @EnvironmentObject var app: AppState
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(app.pal.ink3)
            .background(configuration.isPressed ? app.pal.rowSelected : (hovered ? app.pal.rowHover : .clear), in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(SidebarMotion.hover, value: hovered)
    }
}

/// The space's glyph and name; the label is the pinned section's header and drop target.
private struct SpaceLabel: View {
    @EnvironmentObject var app: AppState
    @State private var hovered = false
    @State private var renaming = false
    @State private var name = ""
    var body: some View {
        HStack(spacing: ShellLayout.iconGap) {
            SpaceGlyph(icon: app.activeSpace.icon).frame(width: ShellLayout.iconSlot)
            if renaming {
                InlineName(text: $name) { app.renameSpace(app.activeSpaceID, name: name); renaming = false }
            } else {
                Text(app.activeSpace.name).font(ShellType.label).lineLimit(1)
                    .onTapGesture(count: 2) { beginRename() }
            }
            Spacer(minLength: 0)
            SidebarGlyphButton("Space options", system: "ellipsis", font: ShellType.glyphSmall, size: ShellLayout.closeTarget, identifier: "sidebar.spaceMenu") {
                app.spaceEditorPresented.toggle()
            }.opacity(hovered || app.spaceEditorPresented ? 1 : 0)
                .popover(isPresented: $app.spaceEditorPresented) { SpaceEditor().environmentObject(app) }
        }.foregroundStyle(app.pal.ink2).padding(.leading, ShellLayout.rowInsetLeading)
            .frame(height: ShellLayout.spaceLabelHeight).contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(SidebarMotion.hover, value: hovered)
            .contextMenu {
                Button("Rename Space") { beginRename() }
                Button("Space Theme…") { app.spaceEditorPresented = true }
                Button("New Folder") { app.createFolder(section: .pinned) }
            }
            .modifier(ShellDropTarget { payload in
                if let id = payloadID(payload, prefix: "tab:") { app.placeTab(id, section: .pinned, spaceID: app.activeSpaceID) }
            })
            .accessibilityElement(children: .contain).accessibilityLabel("Space \(app.activeSpace.name)")
            .accessibilityIdentifier("sidebar.spaceLabel")
            .accessibilityAction(named: "Space options") { app.spaceEditorPresented = true }
    }
    private func beginRename() { name = app.activeSpace.name; renaming = true }
}

/// The hairline above Today; hovering it reveals "Clear", which archives the Today tabs.
private struct TodayDivider: View {
    @EnvironmentObject var app: AppState
    @State private var hovered = false
    var body: some View {
        HStack(spacing: ShellLayout.iconGap) {
            Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline)
            if hovered {
                Button("Clear") { app.archiveToday() }.buttonStyle(.plain)
                    .font(ShellType.label).foregroundStyle(app.pal.ink3)
                    .help("Archive all Today tabs; restore with ⇧⌘T")
                    .accessibilityIdentifier("sidebar.clear").accessibilityLabel("Clear Today tabs").accessibilityAddTraits(.isButton)
                    .transition(.opacity)
            }
        }.frame(height: 2 * ShellLayout.sectionGap).contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(SidebarMotion.hover, value: hovered)
            .contextMenu {
                Button("Clear Today") { app.archiveToday() }
                Button("Tidy Stale Tabs") { app.tidyToday() }
                Button("New Folder") { app.createFolder(section: .today) }
            }
            .modifier(ShellDropTarget { payload in
                if let id = payloadID(payload, prefix: "tab:") { app.placeTab(id, section: .today, spaceID: app.activeSpaceID) }
            })
            .accessibilityElement(children: .contain).accessibilityLabel("Today")
            .accessibilityIdentifier("sidebar.todayDivider")
            .accessibilityAction(named: "Clear Today tabs") { app.archiveToday() }
    }
}

private struct NewTabRow: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Button { app.openCommandBar(newTab: true) } label: {
            HStack(spacing: ShellLayout.iconGap) {
                Image(systemName: "plus").font(ShellType.glyph).frame(width: ShellLayout.iconSlot)
                Text("New Tab").font(ShellType.row)
                Spacer(minLength: 0)
            }.padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.rowHeight).contentShape(Rectangle())
        }.buttonStyle(SidebarRowButtonStyle()).help("New Tab (⌘T)")
            .accessibilityIdentifier("sidebar.newTab").accessibilityLabel("New Tab").accessibilityAddTraits(.isButton)
    }
}

/// Footer strip: archive and library leading, space dots centred, downloads (when active) and plus trailing.
private struct SidebarFooter: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var store: DownloadStore
    @Binding var deleteSpace: SpaceInfo?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let layout = SidebarFooterLayout(downloadsActive: app.downloadsPresented || store.hasRecentActivity(at: context.date))
            HStack(spacing: 0) {
                HStack(spacing: 0) { ForEach(layout.leading, id: \.self) { item($0) } }
                    .frame(width: layout.sideWidth, alignment: .leading)
                SpaceDots(deleteSpace: $deleteSpace).frame(maxWidth: .infinity)
                HStack(spacing: 0) { ForEach(layout.trailing, id: \.self) { item($0) } }
                    .frame(width: layout.sideWidth, alignment: .trailing)
            }.padding(.horizontal, ShellLayout.windowGap).frame(height: ShellLayout.footerHeight)
        }
    }
    @ViewBuilder private func item(_ item: SidebarFooterItem) -> some View {
        switch item {
        case .archive:
            SidebarGlyphButton("Archived tabs (⇧⌘A)", system: "archivebox", identifier: "sidebar.archive") { app.archivePresented.toggle() }
        case .library:
            LibraryButton()
        case .downloads:
            DownloadsButton(store: store)
        case .newTab:
            SidebarGlyphButton("New Tab (⌘T)", system: "plus", identifier: "sidebar.plus") { app.openCommandBar(newTab: true) }
                .contextMenu {
                    Button("New Space (⌘⌥N)") { app.createSpace(); app.spaceEditorPresented = true }
                    Button("This space’s Board (⌘⌥5)") { app.show(.board) }.disabled(app.isPrivate)
                }
        }
    }
}

/// 6pt dots at a 14pt pitch (a custom space glyph replaces its dot); scrolls when they overflow.
private struct SpaceDots: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var deleteSpace: SpaceInfo?
    var body: some View {
        ViewThatFits(in: .horizontal) {
            dots
            ScrollViewReader { proxy in
                ScrollView(.horizontal) { dots }.scrollIndicators(.hidden)
                    .onAppear { proxy.scrollTo(app.activeSpaceID, anchor: .center) }
                    .onChange(of: app.activeSpaceID) { _, id in
                        withAnimation(SidebarMotion.spaceSwitch(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: .center) }
                    }
            }
        }
    }
    private var dots: some View {
        HStack(spacing: 0) {
            ForEach(app.spaces) { space in
                Button { app.selectSpace(space.id) } label: {
                    Group {
                        if let icon = space.icon, !icon.isEmpty { SpaceGlyph(icon: icon) }
                        else { Circle().frame(width: ShellLayout.statusDot, height: ShellLayout.statusDot) }
                    }.foregroundStyle(space.id == app.activeSpaceID ? app.pal.ink : app.pal.ink3)
                        .frame(width: ShellLayout.spaceDotPitch, height: ShellLayout.controlSize).contentShape(Rectangle())
                }.buttonStyle(.plain).id(space.id)
                    .help(space.name).accessibilityLabel("Switch to \(space.name)")
                    .accessibilityIdentifier("sidebar.space.\(space.id)").accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(space.id == app.activeSpaceID ? [.isSelected] : [])
                    .onDrag { NSItemProvider(object: "space:\(space.id)" as NSString) }
                    .modifier(ShellDropTarget { payload in
                        if let id = payloadID(payload, prefix: "space:") { app.moveSpace(id, before: space.id) }
                        else if let id = payloadID(payload, prefix: "tab:"), let tab = app.tabs.first(where: { $0.id == id }) {
                            app.placeTab(id, section: tab.section, spaceID: space.id)
                        }
                    })
                    .contextMenu {
                        Button("Rename / Theme…") { app.selectSpace(space.id); app.spaceEditorPresented = true }
                        Button("Move left") { if let i = app.spaces.firstIndex(where: { $0.id == space.id }), i > 0 { app.moveSpace(space.id, before: app.spaces[i - 1].id) } }
                        Button("Delete space…") { deleteSpace = space }.disabled(app.spaces.count == 1)
                        Button("New Space") { app.createSpace(); app.spaceEditorPresented = true }
                    }
            }
        }.fixedSize()
    }
}

/// Shown only with Settings → Appearance → Address bar: In sidebar.
private struct SidebarAddress: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack(spacing: 0) {
            Button { app.focusAddress() } label: {
                Text(tab.url?.host?.replacingOccurrences(of: "www.", with: "") ?? "Search…")
                    .font(ShellType.caption).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, ShellLayout.rowInsetLeading)
                    .frame(height: ShellLayout.sidebarAddressHeight).contentShape(Rectangle())
            }.buttonStyle(.plain).help(tab.url?.absoluteString ?? "Open location (⌘L)")
                .accessibilityIdentifier("sidebar.address").accessibilityLabel("Open location").accessibilityAddTraits(.isButton)
                .contextMenu { CaptureSiteMenu(tab: tab) }
            SiteControlsButton(tab: tab)
        }.foregroundStyle(app.pal.ink2).frame(height: ShellLayout.sidebarAddressHeight)
            .background(app.pal.fill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
    }
}

private struct SidebarTab: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    var tile = false
    /// Set on a collapsed branch's parent: the count shown at the trailing edge.
    var hiddenDescendants: Int? = nil
    @State private var hovered = false
    @State private var renaming = false
    @State private var name = ""
    @State private var grouping = false
    @State private var groupTask: Task<Void, Never>?
    @State private var previewTask: Task<Void, Never>?
    @State private var previewShown = false
    private var selected: Bool { app.activeTabID == tab.id && app.activeSurface == .web }
    private var highlighted: Bool { selected || (app.selectedTabIDs.contains(tab.id) && app.selectedTabIDs.count > 1) }
    /// A pinned tab that has navigated away from its base URL; clicking its favicon resets it.
    private var offBase: Bool { tab.isPinned && tab.pinnedURL != nil && tab.pinnedURL != tab.url }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: tile ? ShellLayout.favoriteRadius : ShellLayout.rowRadius) }

    var body: some View {
        Group { if tile { tileContent } else { rowContent } }
            .overlay(shape.strokeBorder(grouping ? app.pal.accent : .clear))
            .animation(SidebarMotion.hover, value: hovered)
            .animation(SidebarMotion.hover, value: highlighted)
            .contentShape(Rectangle()).onTapGesture { app.sidebarClick(tab) }
            .onHover { inside in
                hovered = inside; app.hoveredTabID = inside ? tab.id : nil
                previewTask?.cancel()
                if inside {
                    previewTask = Task { try? await Task.sleep(for: .milliseconds(600)); if !Task.isCancelled { previewShown = true } }
                } else { previewShown = false }
            }.help(tab.displayTitle)
            .popover(isPresented: $previewShown, arrowEdge: .trailing) { TabPreview(tab: tab).environmentObject(app) }
            .onDisappear { previewTask?.cancel(); previewShown = false }
            .accessibilityElement(children: .contain).accessibilityLabel(tab.displayTitle)
            .accessibilityIdentifier("sidebar.\(tile ? "favorite" : tab.section.rawValue).\(tab.id)").accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityAction { app.activate(tab.id) }
            .accessibilityAction(named: "Rename") { beginRename() }
            .onDrag { NSItemProvider(object: "tab:\(tab.id)" as NSString) }
            .modifier(ShellDropTarget(onTarget: { inside in
                groupTask?.cancel()
                if inside && !tile {
                    grouping = false
                    groupTask = Task { try? await Task.sleep(for: .milliseconds(500)); if !Task.isCancelled { grouping = true } }
                }
            }, accept: { payload in
                guard let id = payloadID(payload, prefix: "tab:"), id != tab.id else { return }
                if grouping && !tile {
                    let folder = tab.folderID ?? app.createFolder(section: tab.section)
                    app.placeTab(tab.id, section: tab.section, folderID: folder)
                    app.placeTab(id, section: tab.section, folderID: folder, spaceID: tab.spaceID)
                } else {
                    app.placeTab(id, section: tab.section, folderID: tab.folderID, spaceID: tab.spaceID)
                    app.moveTab(id, onto: tab.id, before: true)
                }
                grouping = false; groupTask?.cancel()
            }))
            .popover(isPresented: Binding(get: { tile && renaming }, set: { if !$0 { renaming = false } })) {
                InlineName(text: $name) { app.renameTab(tab, name: name); renaming = false }.padding(16).frame(width: 230)
            }
            .contextMenu { TabContextMenu(tab: tab, rename: beginRename) }
    }

    private func icon(size: CGFloat) -> some View {
        Group {
            if tab.isLoading { ProgressView().controlSize(.mini).frame(width: size, height: size) }
            else { Favicon(host: tab.url?.host, size: size, url: tab.url) }
        }
    }

    /// Favorite tile: translucent fill and a centred 20pt icon; selected adds a 1px stroke.
    private var tileContent: some View {
        Button { app.sidebarClick(tab, reset: tab.isPinned) } label: {
            icon(size: ShellLayout.favoriteIconSize)
                .frame(maxWidth: .infinity).frame(height: ShellLayout.favoriteHeight).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("sidebar.tabIcon.\(tab.id)").accessibilityLabel(tab.displayTitle).accessibilityAddTraits(.isButton)
            .background(highlighted ? app.pal.fillSelected : (hovered ? app.pal.fillHover : app.pal.fill), in: shape)
            .overlay(shape.strokeBorder(highlighted ? app.pal.fillSelectedStroke : .clear, lineWidth: ShellLayout.hairline))
    }

    /// Pinned and Today row: 20pt icon slot, title, audio glyph; Today rows add a close glyph.
    private var rowContent: some View {
        HStack(spacing: ShellLayout.iconGap) {
            Button { app.sidebarClick(tab, reset: offBase) } label: {
                icon(size: ShellLayout.iconSize)
                    .overlay(alignment: .bottomTrailing) {
                        if offBase {
                            Circle().fill(app.pal.accent).frame(width: ShellLayout.statusDot, height: ShellLayout.statusDot)
                                .offset(x: ShellLayout.statusDot / 2, y: ShellLayout.statusDot / 2)
                        }
                    }
                    .frame(width: ShellLayout.iconSlot, height: ShellLayout.rowHeight).contentShape(Rectangle())
            }.buttonStyle(.plain).help(offBase ? "Return to pinned page" : "Open tab")
                .accessibilityIdentifier("sidebar.tabIcon.\(tab.id)")
                .accessibilityLabel(offBase ? "Return \(tab.displayTitle) to pinned page" : "Open \(tab.displayTitle)").accessibilityAddTraits(.isButton)
                .modifier(BranchDropTarget(enabled: tab.section == .today && tab.folderID == nil) { payload in
                    if let id = payloadID(payload, prefix: "tab:") { app.adoptTab(id, under: tab.id) }
                })
            if renaming { InlineName(text: $name) { app.renameTab(tab, name: name); renaming = false } }
            else {
                Text(tab.displayTitle).font(selected ? ShellType.rowSelected : ShellType.row).lineLimit(1)
                    .foregroundStyle(selected ? app.pal.ink : app.pal.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { beginRename() }
                    .onTapGesture { app.sidebarClick(tab) }
            }
            if tab.isPlayingAudio {
                Image(systemName: "speaker.wave.2.fill").font(ShellType.glyphMini).foregroundStyle(app.pal.ink3).help("Playing audio")
            }
            if let hiddenDescendants {
                Text("\(hiddenDescendants)").font(ShellType.label).monospacedDigit().foregroundStyle(app.pal.ink3)
                    .help("\(hiddenDescendants) hidden tabs; ⌥→ expands")
                    .accessibilityLabel("\(hiddenDescendants) collapsed tabs")
            }
            if tab.section == .today {
                Button { app.requestCloseTab(tab.id) } label: {
                    Image(systemName: "xmark").font(ShellType.glyphSmall).foregroundStyle(app.pal.ink3)
                        .frame(width: ShellLayout.closeTarget, height: ShellLayout.closeTarget).contentShape(Rectangle())
                }.buttonStyle(.plain).opacity(hovered || selected ? 1 : 0).help("Close \(tab.displayTitle)")
                    .accessibilityIdentifier("sidebar.close.\(tab.id)").accessibilityLabel("Close \(tab.displayTitle)").accessibilityAddTraits(.isButton)
            }
        }.padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.rowHeight)
            .background(highlighted ? app.pal.rowSelected : (hovered ? app.pal.rowHover : .clear), in: shape)
    }

    private func beginRename() { name = tab.displayTitle; renaming = true }
}

private struct FolderRow: View {
    let folder: TabFolder
    @EnvironmentObject var app: AppState
    @State private var renaming = false
    @State private var name = ""
    @State private var hovered = false
    var body: some View {
        VStack(spacing: ShellLayout.rowPitch - ShellLayout.rowHeight) {
            HStack(spacing: ShellLayout.iconGap) {
                Button {
                    app.updateFolder(folder.id, collapsed: !folder.collapsed)
                } label: {
                    Image(systemName: folder.collapsed ? "chevron.right" : "chevron.down").font(ShellType.glyphMini).foregroundStyle(app.pal.ink3)
                        .frame(width: ShellLayout.iconSlot, height: ShellLayout.rowHeight).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("sidebar.folder.\(folder.id)")
                    .accessibilityLabel("\(folder.collapsed ? "Expand" : "Collapse") \(folder.name)").accessibilityAddTraits(.isButton)
                if renaming { InlineName(text: $name) { app.updateFolder(folder.id, name: name); renaming = false } }
                else {
                    Text(folder.name).font(ShellType.row).foregroundStyle(app.pal.ink2).lineLimit(1)
                        .onTapGesture(count: 2) { name = folder.name; renaming = true }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.rowHeight)
                .background(hovered ? app.pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
                .animation(SidebarMotion.hover, value: hovered)
                .contextMenu {
                    Button("Rename") { name = folder.name; renaming = true }
                    Button("Remove Folder, Keep Tabs") { app.deleteFolder(folder.id) }
                }
                .modifier(ShellDropTarget(onTarget: { inside in
                    if inside { app.updateFolder(folder.id, collapsed: false) }
                }, accept: { payload in
                    if let id = payloadID(payload, prefix: "tab:") { app.placeTab(id, section: folder.section, folderID: folder.id, spaceID: folder.spaceID) }
                }))
            if !folder.collapsed {
                ForEach(app.visibleTabs.filter { $0.folderID == folder.id }) { tab in SidebarTab(tab: tab).padding(.leading, ShellLayout.folderIndent) }
            }
        }
    }
}

/// A space's emoji or SF Symbol at 12pt; callers size the slot.
struct SpaceGlyph: View {
    var icon: String?
    var body: some View {
        Group {
            if let icon, NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil { Text(String(icon.prefix(2))) }
            else { Image(systemName: icon ?? "circle.hexagongrid.fill") }
        }.font(ShellType.glyphSmall)
    }
}

struct InlineName: View {
    @Binding var text: String
    var commit: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        TextField("Name", text: $text).textFieldStyle(.plain).font(ShellType.row).focused($focused)
            .onSubmit(commit).onExitCommand(perform: commit).onAppear { focused = true }
    }
}

struct ShellButtonStyle: ButtonStyle {
    @EnvironmentObject var app: AppState
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// On a web page card the hover fills follow the page, not the appearance.
    @Environment(\.pageIsDark) private var pageIsDark
    var selected = false
    /// Sidebar toolbar and footer glyphs use `ink3`.
    var muted = false
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        let pal = app.pal.page(dark: pageIsDark)
        configuration.label.foregroundStyle(enabled ? (muted ? pal.ink3 : pal.ink2) : pal.inkDisabled)
            .background(configuration.isPressed ? pal.active : (selected ? pal.active : (hovered && enabled ? pal.hover : .clear)), in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: hovered)
    }
}

func payloadID(_ payload: String, prefix: String) -> UUID? {
    guard payload.hasPrefix(prefix) else { return nil }
    return UUID(uuidString: String(payload.dropFirst(prefix.count)))
}

/// A Today row's icon slot: dropping a tab here makes it the row's child. Rows that cannot
/// take children get no drop target, so the row's own reorder target handles the drop.
private struct BranchDropTarget: ViewModifier {
    var enabled: Bool
    var accept: (String) -> Void
    func body(content: Content) -> some View {
        if enabled { content.modifier(ShellDropTarget(accept: accept)) } else { content }
    }
}

private struct ShellDropTarget: ViewModifier {
    @EnvironmentObject var app: AppState
    @State private var targeted = false
    var onTarget: (Bool) -> Void = { _ in }
    var accept: (String) -> Void
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) { if targeted { Rectangle().fill(app.pal.accentText).frame(height: 2) } }
            .onDrop(of: [.utf8PlainText], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let payload = object as? String else { return }
                    Task { @MainActor in accept(payload) }
                }
                return true
            }.onChange(of: targeted) { _, inside in onTarget(inside) }
    }
}


func copyLink(_ url: URL?) {
    guard let url else { return }
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
}

struct SettingsMenu: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Menu {
            Button("Settings…") { app.settingsPresented = true }
            Picker("Layout", selection: $app.layout) { ForEach(BrowserLayout.allCases, id: \.self) { Text($0.title).tag($0) } }
            Toggle("Search suggestions", isOn: $app.searchSuggestions)
            Button("New Space") { app.createSpace(); app.spaceEditorPresented = true }
            Menu("General · Auto-archive") {
                Picker("Archive inactive Today tabs", selection: $app.archiveHours) {
                    Text("12 hours").tag(12.0)
                    Text("24 hours").tag(24.0)
                    Text("7 days").tag(168.0)
                    Text("Never").tag(0.0)
                }
            }
            Button("Archived tabs") { app.archivePresented.toggle() }

            Menu("General · Sleeping tabs") {
                Picker("Discard inactive background tabs", selection: $app.discardMinutes) {
                    Text("After 30 minutes").tag(30.0)
                    Text("After 1 hour").tag(60.0)
                    Text("Never").tag(0.0)
                }
            }
            Button("Space Theme…") { app.spaceEditorPresented = true }
            Menu("Privacy") {
                if let tab = app.activeTab { CaptureSiteMenu(tab: tab) }
                ForEach(app.excludedHosts.sorted(), id: \.self) { host in
                    Button("Allow capture: \(host)") { app.excludedHosts.remove(host); app.persist() }
                }
            }
            Menu("Appearance") {
                ForEach(ThemeMode.allCases, id: \.self) { mode in Button(mode.rawValue.capitalized) { app.mode = mode; app.persist() } }
            }
            Menu("Search engine") {
                ForEach(SearchEngine.allCases, id: \.self) { engine in Button(engine == .google ? "Google" : "DuckDuckGo") { app.searchEngine = engine; app.persist() } }
            }
            Button("Widen Sidebar") { app.resizeSidebar(app.sidebarWidth + 16) }
            Button("Narrow Sidebar") { app.resizeSidebar(app.sidebarWidth - 16) }
            Divider()
            Button("Open Vault in Finder") { NSWorkspace.shared.open(Paths.vault) }
        } label: { Image(systemName: "gearshape").font(ShellType.glyphSmall).frame(width: 24, height: 28) }
            .menuStyle(.borderlessButton).fixedSize().help("Settings")
            .accessibilityIdentifier("shell.settingsMenu").accessibilityLabel("Settings").accessibilityAddTraits(.isButton)
    }
}
