import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Sidebar: View {
    var width: CGFloat = ShellLayout.sidebarDefault
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renaming = false
    @State private var name = ""
    @State private var deleteSpace: SpaceInfo?
    @State private var draggingTab = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                IconButton("Hide sidebar (⌘S)", system: "sidebar.left") { app.toggleSidebar() }
                Spacer(minLength: 0)
                if let tab = app.activeTab {
                    IconButton("Back", system: "chevron.left") { tab.goBack() }.disabled(!tab.canGoBack)
                    IconButton("Forward", system: "chevron.right") { tab.goForward() }.disabled(!tab.canGoForward)
                    IconButton(tab.isLoading ? "Stop" : "Reload", system: tab.isLoading ? "xmark" : "arrow.clockwise") { tab.isLoading ? tab.stop() : tab.reload() }
                }
            }.padding(.leading, ShellLayout.trafficReserve).padding(.trailing, ShellLayout.windowGap)
                .frame(height: ShellLayout.trafficBandHeight).background(WindowDragRegion())
            if let tab = app.activeTab { SidebarAddress(tab: tab).padding(.horizontal, 10) }
            if app.isPrivate {
                Label("Private", systemImage: "eye.slash").font(ShellType.label)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(app.pal.elev, in: Capsule()).padding(.horizontal, 14)
            }
            HStack(spacing: 6) {
                SpaceGlyph(icon: app.activeSpace.icon)
                if renaming {
                    InlineName(text: $name) { app.renameSpace(app.activeSpaceID, name: name); renaming = false }
                } else {
                    Text(app.activeSpace.name).font(ShellType.label)
                        .lineLimit(1).onTapGesture(count: 2) { name = app.activeSpace.name; renaming = true }
                }
                Spacer(minLength: 0)
                IconButton("Edit space theme", system: "ellipsis") { app.spaceEditorPresented.toggle() }
                    .popover(isPresented: $app.spaceEditorPresented) { SpaceEditor().environmentObject(app) }
            }.foregroundStyle(app.pal.ink2).padding(.horizontal, 16)
            if app.archivePresented { ArchiveView() } else { ScrollViewReader { _ in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if hasContent(.favorites) || draggingTab { favorites }
                        if hasContent(.pinned) || draggingTab {
                            section(.pinned)
                        }
                        Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline).padding(.horizontal, 2)
                        section(.today)
                    }.padding(.horizontal, 8).padding(.bottom, 12)
                        .id(app.activeSpaceID)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }.scrollIndicators(.hidden)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: app.activeSpaceID)
                    .overlay(alignment: .top) { DragAutoScrollEdge(direction: -1).frame(height: 12) }
                    .overlay(alignment: .bottom) { DragAutoScrollEdge(direction: 1).frame(height: 12) }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: app.visibleTabs.map(\.id))
            }
            }
            if let tab = app.tabs.first(where: { $0.id == app.mediaTabID }) { NowPlayingRow(tab: tab).padding(.horizontal, 10) }
            if !app.knowledgeSearchPresented {
                Button { app.toggleKnowledge() } label: {
                    HStack(spacing: 8) { Image(systemName: "sparkle"); Text("Ask Graphene"); Spacer(); Text("⌘K") }
                        .font(ShellType.caption).padding(.horizontal, 10).frame(height: 28)
                }.buttonStyle(ShellButtonStyle()).disabled(app.isPrivate).padding(.horizontal, 6)
                    .accessibilityIdentifier("sidebar.ask").accessibilityLabel("Ask Graphene (⌘K)").accessibilityAddTraits(.isButton)
            }
            ZStack {
                HStack(spacing: 0) {
                    LibraryButton()
                    DownloadsButton(store: app.downloads, onlyWhenRecent: true)
                    Spacer(minLength: 0)
                    IconButton("New Tab (⌘T)", system: "plus") { app.openCommandBar(newTab: true) }
                        .contextMenu {
                            Button("New Space (⌘⌥N)") { app.createSpace(); app.spaceEditorPresented = true }
                            Button("This space’s Board (⌘⌥5)") { app.show(.board) }.disabled(app.isPrivate)
                        }
                }
                ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 3) {
                        ForEach(app.spaces) { space in
                            Button { app.selectSpace(space.id) } label: {
                                Circle().fill(space.id == app.activeSpaceID ? app.pal.ink2 : app.pal.ink3)
                                    .frame(width: space.id == app.activeSpaceID ? 8 : 5, height: space.id == app.activeSpaceID ? 8 : 5).frame(width: 20, height: 28)
                            }.buttonStyle(ShellButtonStyle()).id(space.id)
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
                    }
                }.scrollIndicators(.hidden).clipped().defaultScrollAnchor(.center)
                    .onChange(of: app.activeSpaceID) { _, id in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }.padding(.horizontal, 54)
            }.padding(.horizontal, 10).frame(height: ShellLayout.footerHeight)
        }
        .background(SidebarSwipe { app.selectRelativeSpace($0) })
        .onDrop(of: [.utf8PlainText], isTargeted: $draggingTab) { _ in false }
        .alert("Delete \(deleteSpace?.name ?? "space")?", isPresented: Binding(get: { deleteSpace != nil }, set: { if !$0 { deleteSpace = nil } })) {
            Button("Cancel", role: .cancel) { deleteSpace = nil }
            Button("Delete", role: .destructive) { if let space = deleteSpace { app.deleteSpace(space.id) }; deleteSpace = nil }
        } message: { Text("Tabs and folders move to the previous space. The last space cannot be deleted.") }
    }

    private var favorites: some View {
        VStack(spacing: 0) {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ShellLayout.favoriteGap), count: ShellLayout.favoriteColumns(width: width - 2 * ShellLayout.windowGap)), spacing: ShellLayout.favoriteGap) {
            ForEach(app.visibleTabs.filter { $0.section == .favorites }) { tab in
                SidebarTab(tab: tab, tile: true)
            }
        }

        }.frame(minHeight: 40)
            .modifier(ShellDropTarget { payload in
                if let id = payloadID(payload, prefix: "tab:") { app.placeTab(id, section: .favorites, spaceID: app.activeSpaceID) }
            })
    }

    private func hasContent(_ section: TabSection) -> Bool {
        app.visibleTabs.contains { $0.section == section } || app.folders.contains { $0.spaceID == app.activeSpaceID && $0.section == section }
    }

    private func section(_ section: TabSection) -> some View {
        VStack(spacing: ShellLayout.rowPitch - ShellLayout.rowHeight) {
            HStack {
                Spacer()
                if section == .today {
                    Button("Tidy") { app.tidyToday() }.buttonStyle(.plain).help("Archive stale Today tabs using the interval in Settings")
                        .accessibilityIdentifier("sidebar.tidy").accessibilityLabel("Tidy stale tabs").accessibilityAddTraits(.isButton)
                    Text("|").accessibilityHidden(true)
                    Button("Clear") { app.archiveToday() }.buttonStyle(.plain).help("Archive all Today tabs; restore with ⇧⌘T")
                        .accessibilityIdentifier("sidebar.clear").accessibilityLabel("Clear Today tabs").accessibilityAddTraits(.isButton)
                }
            }.font(ShellType.caption).foregroundStyle(app.pal.ink3).padding(.horizontal, 10).frame(height: section == .today ? 22 : 4)
                .contentShape(Rectangle())
                .contextMenu { Button("New Folder") { app.createFolder(section: section) } }
                .modifier(ShellDropTarget { payload in
                    if let id = payloadID(payload, prefix: "tab:") { app.placeTab(id, section: section, spaceID: app.activeSpaceID) }
                })
            if section == .today {
                Button { app.openCommandBar(newTab: true) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus").frame(width: 18)
                        Text("New Tab"); Spacer(); Text("⌘T").font(ShellType.label)
                    }.font(ShellType.row).padding(.horizontal, 10).frame(height: app.settings.compactSidebar == true ? 26 : ShellLayout.rowHeight)
                }.buttonStyle(ShellButtonStyle()).help("New Tab (⌘T)")
                    .accessibilityIdentifier("sidebar.newTab").accessibilityLabel("New Tab").accessibilityAddTraits(.isButton)
            }
            ForEach(app.folders.filter { $0.spaceID == app.activeSpaceID && $0.section == section }) { folder in
                FolderRow(folder: folder)
            }
            ForEach(app.visibleTabs.filter { $0.section == section && $0.folderID == nil }) { tab in
                SidebarTab(tab: tab).id(tab.id)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

}

private struct SidebarAddress: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack(spacing: 0) {
            Button { app.focusAddress() } label: {
                Text(tab.url?.host?.replacingOccurrences(of: "www.", with: "") ?? "Search…")
                    .font(ShellType.caption).lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 28).padding(.horizontal, 5)
            }.buttonStyle(.plain).help(tab.url?.absoluteString ?? "Open location (⌘L)")
                .accessibilityIdentifier("sidebar.address").accessibilityLabel("Open location").accessibilityAddTraits(.isButton)
                .contextMenu { CaptureSiteMenu(tab: tab) }
            SiteControlsButton(tab: tab)
        }.padding(.horizontal, 4).frame(height: ShellLayout.pageToolbarHeight)
            .background(app.pal.selection, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
    }
}

private struct SidebarTab: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tile = false
    @State private var hovered = false
    @State private var renaming = false
    @State private var name = ""
    @State private var grouping = false
    @State private var groupTask: Task<Void, Never>?
    @State private var previewTask: Task<Void, Never>?
    @State private var previewShown = false
    private var selected: Bool { app.activeTabID == tab.id && app.activeSurface == .web }

    var body: some View {
        HStack(spacing: 8) {
            if tile { Spacer(minLength: 0) }
            Button { app.sidebarClick(tab, reset: tab.isPinned) } label: {
                if tab.isLoading { ProgressView().controlSize(.mini).frame(width: ShellLayout.iconSize, height: ShellLayout.iconSize) }
                else { Favicon(host: tab.url?.host, size: tile ? ShellLayout.favoriteIconSize : ShellLayout.iconSize, url: tab.url) }
            }.buttonStyle(.plain).help(tab.isPinned ? "Return to pinned page" : "Open tab")
                .accessibilityIdentifier("sidebar.tabIcon.\(tab.id)")
                .accessibilityLabel(tile ? tab.displayTitle : "Open \(tab.displayTitle)").accessibilityAddTraits(.isButton)
            if !tile {
                if renaming { InlineName(text: $name) { app.renameTab(tab, name: name); renaming = false } }
                else {
                    Text(tab.displayTitle).font(selected ? ShellType.rowSelected : ShellType.row).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture(count: 2) { beginRename() }
                        .onTapGesture { app.sidebarClick(tab) }
                }
                if tab.isPlayingAudio { Image(systemName: "speaker.wave.2.fill").font(ShellType.glyphMini).help("Playing audio") }
                if tab.isPinned && tab.pinnedURL != tab.url {
                    IconButton("Return to pinned page", system: "arrow.uturn.backward") { app.resetPinnedTab(tab) }
                }
                Button { app.requestCloseTab(tab.id) } label: {
                    Image(systemName: "xmark").font(ShellType.glyphSmall).frame(width: 22, height: 28)
                }.buttonStyle(.plain).opacity(hovered ? 1 : 0).help("Close \(tab.displayTitle)")
                    .accessibilityIdentifier("sidebar.close.\(tab.id)").accessibilityLabel("Close \(tab.displayTitle)").accessibilityAddTraits(.isButton)
            } else { Spacer(minLength: 0) }
        }.padding(.horizontal, tile ? 4 : 10).frame(height: tile ? ShellLayout.favoriteHeight : (app.settings.compactSidebar == true ? 26 : ShellLayout.rowHeight))
            .foregroundStyle(selected ? app.pal.ink : app.pal.ink2)
            .background(app.selectedTabIDs.contains(tab.id) && app.selectedTabIDs.count > 1 ? app.pal.active : (selected ? app.pal.selection : (hovered ? app.pal.hover : (tile ? app.pal.fill : .clear))), in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: hovered)
            .overlay(RoundedRectangle(cornerRadius: ShellLayout.rowRadius).strokeBorder(grouping ? app.pal.accentText : .clear))
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
            HStack(spacing: 8) {
                Button {
                    app.updateFolder(folder.id, collapsed: !folder.collapsed)
                } label: {
                    Image(systemName: hovered ? (folder.collapsed ? "chevron.right" : "chevron.down") : "folder").font(ShellType.glyphSmall).frame(width: ShellLayout.iconSize, height: 26)
                }.buttonStyle(.plain).accessibilityIdentifier("sidebar.folder.\(folder.id)")
                    .accessibilityLabel("\(folder.collapsed ? "Expand" : "Collapse") \(folder.name)").accessibilityAddTraits(.isButton)
                if renaming { InlineName(text: $name) { app.updateFolder(folder.id, name: name); renaming = false } }
                else { Text(folder.name).font(ShellType.row).lineLimit(1).onTapGesture(count: 2) { name = folder.name; renaming = true } }
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).frame(height: app.settings.compactSidebar == true ? 26 : ShellLayout.rowHeight).contentShape(Rectangle())
                .onHover { hovered = $0 }
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
                ForEach(app.visibleTabs.filter { $0.folderID == folder.id }) { tab in SidebarTab(tab: tab).padding(.leading, 16) }
            }
        }.foregroundStyle(app.pal.ink2)
    }
}

struct SpaceGlyph: View {
    var icon: String?
    var body: some View {
        Group {
            if let icon, NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil { Text(String(icon.prefix(2))) }
            else { Image(systemName: icon ?? "circle.hexagongrid.fill") }
        }.font(ShellType.glyphSmall).frame(width: ShellLayout.iconSize, height: 18)
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
    var selected = false
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(enabled ? app.pal.ink2 : app.pal.inkDisabled)
            .background(configuration.isPressed ? app.pal.active : (selected ? app.pal.active : (hovered && enabled ? app.pal.hover : .clear)), in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: hovered)
    }
}

func payloadID(_ payload: String, prefix: String) -> UUID? {
    guard payload.hasPrefix(prefix) else { return nil }
    return UUID(uuidString: String(payload.dropFirst(prefix.count)))
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
