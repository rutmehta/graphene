import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TopTabBar: View {
    @EnvironmentObject var app: AppState
    @State private var spacesPresented = false
    var body: some View {
        HStack(spacing: 4) {
            Button { spacesPresented.toggle() } label: { SpaceGlyph(icon: app.activeSpace.icon).frame(width: 30, height: 30) }
                .buttonStyle(.plain).help("Spaces and tabs")
                .accessibilityIdentifier("topTabs.spaces").accessibilityLabel("Spaces and tabs").accessibilityAddTraits(.isButton)
                .popover(isPresented: $spacesPresented) { Sidebar().frame(width: 280, height: 600).background { ChromeBackground() }.environmentObject(app) }
            ForEach(app.visibleTabs.filter { $0.isPinned }) { tab in TopTabChip(tab: tab, pinned: true).frame(width: 32) }
            GeometryReader { geometry in
                let tabs = app.visibleTabs.filter { !$0.isPinned }
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(tabs) { tab in
                            TopTabChip(tab: tab, pinned: false).frame(width: max(80, min(200, (geometry.size.width - CGFloat(max(0, tabs.count - 1)) * 4) / CGFloat(max(1, tabs.count)))))
                        }
                    }
                }.scrollIndicators(.hidden)
            }.frame(height: 32)
            IconButton("New Tab (⌘T)", system: "plus") { app.openCommandBar(newTab: true) }
            Menu {
                ForEach(app.visibleTabs) { tab in Button(tab.displayTitle) { app.activate(tab.id); app.show(.web) } }
                Divider()
                Button("Archived tabs") { app.archivePresented = true; spacesPresented = true }
            } label: { Image(systemName: "chevron.down").frame(width: 26, height: 30) }
                .menuStyle(.borderlessButton).fixedSize().help("All tabs")
                .accessibilityIdentifier("topTabs.overflow").accessibilityLabel("All tabs").accessibilityAddTraits(.isButton)
        }.padding(.leading, ShellLayout.trafficReserve).padding(.trailing, 8).frame(height: ShellLayout.topTabHeight)
            .background(WindowDragRegion())
            .background(app.pal.sidebarBg)
            .onChange(of: app.archivePresented) { _, value in if value { spacesPresented = true } }
            .onChange(of: app.spaceEditorPresented) { _, value in if value { spacesPresented = true } }
    }
}

private struct TopTabChip: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var tab: Tab
    let pinned: Bool
    @State private var hovered = false
    @State private var targeted = false
    @State private var renaming = false
    @State private var name = ""
    var body: some View {
        HStack(spacing: 6) {
            Favicon(host: tab.url?.host, size: ShellLayout.iconSize)
            if !pinned {
                Text(tab.displayTitle).font(app.activeTabID == tab.id ? ShellType.rowSelected : ShellType.row).lineLimit(1)
                Spacer(minLength: 0)
                Button { app.requestCloseTab(tab.id) } label: { Image(systemName: "xmark").font(ShellType.glyphMini).frame(width: 18, height: 24) }
                    .buttonStyle(.plain).opacity(hovered ? 1 : 0).help("Close tab").accessibilityLabel("Close \(tab.displayTitle)")
                    .accessibilityIdentifier("topTabs.close.\(tab.id)").accessibilityAddTraits(.isButton)
            }
        }.padding(.horizontal, pinned ? 0 : 8).frame(maxWidth: .infinity).frame(height: 32)
            .foregroundStyle(app.pal.ink2)
            .background(app.activeTabID == tab.id ? app.pal.ground : hovered ? app.pal.hover : app.pal.sidebarBg, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .overlay(alignment: .leading) { if targeted { Rectangle().fill(app.pal.accent).frame(width: 2) } }
            .contentShape(Rectangle()).onTapGesture { app.activate(tab.id); app.show(.web) }
            .onHover { hovered = $0 }.help(tab.displayTitle)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: hovered)
            .accessibilityAddTraits(app.activeTabID == tab.id ? [.isSelected] : [])
            .accessibilityElement(children: .contain).accessibilityIdentifier("topTabs.tab.\(tab.id)")
            .accessibilityLabel(tab.displayTitle).accessibilityAddTraits(.isButton)
            .accessibilityAction { app.activate(tab.id); app.show(.web) }
            .background(MiddleTabClick { app.requestCloseTab(tab.id) })
            .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
            .onDrop(of: [.text], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: String.self) { value, _ in
                    guard let value, let id = UUID(uuidString: value) else { return }
                    Task { @MainActor in
                        guard let source = app.tabs.firstIndex(where: { $0.id == id }), id != tab.id,
                              app.tabs[source].spaceID == tab.spaceID else { return }
                        let moved = app.tabs.remove(at: source)
                        if let target = app.tabs.firstIndex(where: { $0.id == tab.id }) { app.tabs.insert(moved, at: target) }
                        else { app.tabs.append(moved) }
                        app.persist()
                    }
                }
                return true
            }
            .contextMenu { TabContextMenu(tab: tab) { name = tab.displayTitle; renaming = true } }
            .popover(isPresented: $renaming) {
                InlineName(text: $name) { app.renameTab(tab, name: name); renaming = false }.padding(16).frame(width: 230)
            }
    }
}

private struct MiddleTabClick: NSViewRepresentable {
    var close: () -> Void
    func makeNSView(context: Context) -> HitView { let view = HitView(); view.close = close; return view }
    func updateNSView(_ view: HitView, context: Context) { view.close = close }
    final class HitView: NSView {
        var close: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .otherMouseDown || NSApp.currentEvent?.type == .otherMouseUp else { return nil }
            return super.hitTest(point)
        }
        override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { close() } }
    }
}

struct TopBrowserToolbar: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                IconButton("Back", system: "chevron.left") { app.goBack() }.disabled(app.activeTab?.canGoBack != true)
                IconButton("Forward", system: "chevron.right") { app.goForward() }.disabled(app.activeTab?.canGoForward != true)
                IconButton(app.activeTab?.isLoading == true ? "Stop loading" : "Reload", system: app.activeTab?.isLoading == true ? "xmark" : "arrow.clockwise") {
                    if let tab = app.activeTab { tab.isLoading ? tab.stop() : tab.reload() }
                }
            }.frame(width: 140, alignment: .leading)
            Spacer(minLength: 8)
            VStack(spacing: 0) {
                if app.commandBarPresented {
                    CommandBar(integrated: true).fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 8) {
                        if let tab = app.activeTab { SiteControlsButton(tab: tab) }
                        Button { app.focusAddress() } label: {
                            Text(app.activeTab?.url?.host ?? "Search or ask").lineLimit(1)
                                .frame(maxWidth: .infinity).frame(height: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("toolbar.address")
                            .accessibilityLabel("Search or ask").accessibilityAddTraits(.isButton)
                        Text("⌘L").foregroundStyle(app.pal.ink3).frame(width: 26)
                    }.font(ShellType.secondary).foregroundStyle(app.pal.ink2).padding(.horizontal, 12)
                }
            }.frame(maxWidth: 680)
                .background(app.pal.elev, in: RoundedRectangle(cornerRadius: ShellLayout.pageRadius))
                .overlay(RoundedRectangle(cornerRadius: ShellLayout.pageRadius).strokeBorder(app.pal.hairline))
                .frame(height: 32, alignment: .top)
                .zIndex(1)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
            Button { app.toggleKnowledge() } label: {
                Label("Chat", systemImage: ShellGlyph.ask).font(ShellType.rowSelected)
                    .padding(.horizontal, 10).frame(height: 28)
            }.buttonStyle(ShellButtonStyle(selected: app.knowledgeSearchPresented)).help("Ask Graphene (⌘K)").disabled(app.isPrivate)
                .accessibilityIdentifier("toolbar.chat").accessibilityLabel("Chat").accessibilityAddTraits(.isButton)
            IconButton("Save to Vault", system: "bookmark") { app.noteComposerPresented = true }.disabled(app.activeTab?.url == nil || app.isPrivate)
            DownloadsButton(store: app.downloads, onlyWhenRecent: true)
            }.frame(width: 140, alignment: .trailing)
        }.padding(.horizontal, 8).frame(height: 40).background(app.pal.ground)

    }
}

struct BrowserSettings: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(ShellType.title)
            Picker("Layout", selection: $app.layout) { ForEach(BrowserLayout.allCases, id: \.self) { Text($0.title).tag($0) } }
            Picker("Search engine", selection: $app.searchEngine) { ForEach(SearchEngine.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Toggle("Search suggestions", isOn: $app.searchSuggestions)
            Text("Suggestions send search text to your selected search engine. URLs and tab mentions stay local.").font(ShellType.secondary).foregroundStyle(app.pal.ink3)
            HStack { Spacer(); Button("Done") { app.persist(); app.settingsPresented = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 420).foregroundStyle(app.pal.ink).background(app.pal.ground)
    }
}
