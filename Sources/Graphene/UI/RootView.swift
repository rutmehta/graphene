import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var windowState: WindowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.openSettings) private var openSettings
    @State private var askResizeStart: Double?
    @SceneStorage("shell.windowID") private var windowID = UUID().uuidString
    private var sidebarWidth: CGFloat { app.sidebarWidths[windowID].map { CGFloat($0) } ?? app.sidebarWidth }
    private var sidebarLayout: Bool { app.layout == .sidebar }
    private var showsSidebar: Bool { sidebarLayout && !app.sidebarCollapsed }
    /// The page card's inset from the window's top, right and bottom (and left when collapsed).
    private var cardGap: CGFloat { sidebarLayout && app.settings.pageGutter ? ShellLayout.windowGap : 0 }
    /// Sidebar collapse: a short spring; Reduce Motion fades only.
    private var collapseAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.30, dampingFraction: 0.75)
    }
    /// Floating chat, or docked chat that would squeeze the page below its minimum, draws as a floating card.
    private func chatFloats(window width: CGFloat) -> Bool {
        app.settings.chatPanelMode == .floating
            || width - (showsSidebar ? sidebarWidth : 0) - app.settings.askWidth - 24 < ShellLayout.minimumPageWidth
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if showsSidebar {
                    Sidebar(width: sidebarWidth).frame(width: sidebarWidth)
                        .overlay(alignment: .trailing) {
                            SidebarResizeHandle(width: Binding(get: { sidebarWidth }, set: { app.resizeSidebar($0, windowID: windowID) }))
                        }
                        .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                }
                ShellContentLayout(overlayAsk: geometry.size.width - (showsSidebar ? sidebarWidth : 0) - app.settings.askWidth - 24 < ShellLayout.minimumPageWidth, showAsk: app.knowledgeSearchPresented, preferredAskWidth: app.settings.askWidth, floating: app.settings.chatPanelMode == .floating) {
                    VStack(spacing: 0) {
                        if app.layout == .topTabs { TopTabBar(); TopBrowserToolbar().zIndex(10) }
                        if let error = app.graph.errorText ?? app.sessionError {
                            Text(error).font(ShellType.secondary).foregroundStyle(app.pal.ink2)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Group {
                            if app.activeSurface == .web {
                                SplitBrowserView(reservesTrafficLights: app.sidebarCollapsed && sidebarLayout, cardOriginX: cardGap)
                            } else if sidebarLayout {
                                librarySurface.pageCard()
                            } else { librarySurface }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .modifier(TopTabsPageSurface(active: !sidebarLayout))
                            .overlay {
                                if app.commandBarPresented {
                                    (app.layout == .topTabs ? app.pal.scrimSubtle : app.pal.commandScrim).contentShape(Rectangle())
                                        .onTapGesture { app.dismissCommandBar() }
                                        .transition(.opacity)
                                }
                            }
                            .overlay(alignment: .bottom) { ToastOverlay() }
                    }
                    .background(sidebarLayout ? Color.clear : app.pal.chromeBg)

                    if app.knowledgeSearchPresented {
                        KnowledgeSearchView(scopedNodes: app.currentThreads.first(where: { $0.id == app.knowledgeThreadID })?.nodes,
                                            threadTitle: app.currentThreads.first(where: { $0.id == app.knowledgeThreadID })?.title, embedded: true)
                            .id(app.knowledgeThreadID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(app.pal.elev, in: RoundedRectangle(cornerRadius: ShellLayout.popoverRadius))
                            .clipShape(RoundedRectangle(cornerRadius: ShellLayout.popoverRadius))
                            .overlay(RoundedRectangle(cornerRadius: ShellLayout.popoverRadius).strokeBorder(app.pal.hairline, lineWidth: ShellLayout.hairline))
                            .shadow(color: chatFloats(window: geometry.size.width) ? app.pal.pageShadow : .clear, radius: app.pal.pageShadowRadius, y: app.pal.pageShadowY)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(app.pal.hitTarget).frame(width: ShellLayout.windowGap / 2).contentShape(Rectangle())
                                    .gesture(DragGesture().onChanged { value in
                                        if askResizeStart == nil { askResizeStart = app.settings.askWidth }
                                        app.settings.askWidth = (askResizeStart ?? Double(ShellLayout.chatWidth)) - value.translation.width
                                    }.onEnded { _ in askResizeStart = nil; app.persist() })
                                    .accessibilityLabel("Resize Ask panel")
                                    .accessibilityIdentifier("chat.resize")
                                    .accessibilityAdjustableAction { direction in
                                        app.settings.askWidth += direction == .increment ? 10 : -10; app.persist()
                                    }
                            }
                            .transition(Motion.panel(reduced: reduceMotion))
                    }
                }
                .overlay { if let tab = app.peekTab { PeekOverlay(tab: tab) } }
                .padding(.vertical, cardGap).padding(.trailing, cardGap).padding(.leading, showsSidebar ? 0 : cardGap)
                .transaction { if reduceMotion { $0.animation = nil } }
            }
            .background { ChromeBackground() }
            .overlay(alignment: .leading) {
                if app.layout == .sidebar && app.sidebarCollapsed {
                    if app.sidebarPeek {
                        // The peeked sidebar floats over the page card as an elevated panel (§3.3, §4).
                        Sidebar(width: sidebarWidth).frame(width: sidebarWidth).background(app.pal.sidebarPeekBg)
                            .clipShape(RoundedRectangle(cornerRadius: ShellLayout.popoverRadius))
                            .overlay(RoundedRectangle(cornerRadius: ShellLayout.popoverRadius).strokeBorder(app.pal.hairline, lineWidth: ShellLayout.hairline))
                            .shadow(color: app.pal.pageShadow, radius: app.pal.pageShadowRadius, y: app.pal.pageShadowY)
                            .padding(ShellLayout.windowGap)
                            .onHover { inside in if !inside && !app.spaceEditorPresented { app.sidebarPeek = false } }
                            .transition(reduceMotion ? .opacity : .offset(x: -sidebarWidth).combined(with: .opacity))
                    }
                }
            }
            .background {
                if app.layout == .sidebar && app.sidebarCollapsed {
                    SidebarPeekEdgeMonitor(peeking: app.sidebarPeek, sidebarWidth: sidebarWidth) { app.sidebarPeek = $0 }.frame(width: 0, height: 0)
                }
            }
            .overlay(alignment: .top) {
                if app.commandBarPresented && app.layout == .sidebar {
                    // The scrim dims only the page card; this catches clicks on the rest of the window.
                    app.pal.hitTarget.contentShape(Rectangle()).onTapGesture { app.dismissCommandBar() }
                    CommandBar()
                        .frame(width: CommandBarLayout.width(window: geometry.size.width))
                        .padding(.top, CommandBarLayout.top(window: geometry.size.height))
                        .transition(Motion.commandBar(reduced: reduceMotion))
                }
            }
            .animation(collapseAnimation, value: app.sidebarCollapsed)
            .animation(Motion.panel.reduced(reduceMotion), value: app.knowledgeSearchPresented)
            .animation((app.commandBarPresented ? Motion.commandIn : Motion.commandOut).reduced(reduceMotion), value: app.commandBarPresented)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.8), value: app.sidebarPeek)
        }
        .ignoresSafeArea()
        .background(WindowAccessor(onKeyWindow: { app.focusedWindowID = windowID }, state: windowState))
        .background(TabKeyboardMonitor(app: app))
        .overlay { if !app.switcherIDs.isEmpty { TabSwitcher() } }
        .overlay { WindowOutline() }
        .onAppear {
            app.focusedWindowID = windowID
            if app.sidebarWidths[windowID] == nil { app.resizeSidebar(app.sidebarWidth, windowID: windowID) }
        }
        .onChange(of: systemScheme) { _, _ in if app.mode == .automatic { app.objectWillChange.send() } }
        .sheet(isPresented: $app.noteComposerPresented) { NoteComposer() }
        .sheet(isPresented: Binding(get: { app.boostHost != nil }, set: { if !$0 { app.boostHost = nil } })) {
            if let host = app.boostHost { BoostEditor(host: host) }
        }
        .onChange(of: app.settingsPresented) { _, presented in
            if presented { app.settingsPresented = false; openSettings() }
        }
        .sheet(isPresented: $app.onboardingPresented) { OnboardingView() }
        .sheet(isPresented: $app.readerPresented) {
            if let article = app.readerArticle { ReaderPage(article: article) }
        }
        .foregroundStyle(app.pal.ink)
        .environment(\.colorScheme, app.pal.isDark ? .dark : .light)
        .preferredColorScheme(app.mode == .automatic ? nil : (app.pal.isDark ? .dark : .light))
        .tint(app.pal.accentText)
    }

    @ViewBuilder private var librarySurface: some View {
        switch app.activeSurface {
        case .threads: LedgerView()
        case .vault: VaultView()
        case .mail: MailView()
        case .board: EaselView()
        case .web: EmptyView()
        }
    }
}

/// The top-tabs layout keeps its inset, clipped page surface; the sidebar layout's cards style themselves.
private struct TopTabsPageSurface: ViewModifier {
    @EnvironmentObject var app: AppState
    var active: Bool
    func body(content: Content) -> some View {
        if active {
            content.background(app.pal.pageBg)
                .clipShape(RoundedRectangle(cornerRadius: ShellLayout.pageRadius))
                .padding(app.settings.pageGutter ? ShellLayout.windowGap : 0)
        } else { content }
    }
}


struct IconButton: View {
    let title: String
    let system: String
    var font: Font
    var action: () -> Void
    @EnvironmentObject var app: AppState
    @FocusState private var focused: Bool
    init(_ title: String, system: String, font: Font = ShellType.glyph, action: @escaping () -> Void) { self.title = title; self.system = system; self.font = font; self.action = action }
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(font).frame(width: ShellLayout.controlSize, height: ShellLayout.controlSize)
                .contentShape(Rectangle())
        }.buttonStyle(ShellButtonStyle()).focused($focused)
            .overlay { RoundedRectangle(cornerRadius: ShellLayout.rowRadius).strokeBorder(focused ? app.pal.accentText : .clear, lineWidth: 2).allowsHitTesting(false) }
            .help(title).accessibilityLabel(title).accessibilityIdentifier("icon.\(system).\(title)")
            .accessibilityAddTraits(.isButton)
    }
}
struct BrowserPage: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(spacing: 0) {
            if app.findPresented && tab.url != nil && (app.activeSplit == nil || app.activeTabID == tab.id) { FindBar(tab: tab) }
            page
        }
        .task(id: app.activeTabID) {
            while !Task.isCancelled && app.activeTabID == tab.id {
                let playing = await tab.engine.evaluateJavaScript("Array.from(document.querySelectorAll('audio,video')).some(e => !e.paused && !e.ended && !e.muted && e.volume > 0)")
                guard !Task.isCancelled else { return }
                tab.isPlayingAudio = playing as? Bool ?? false
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    private var page: some View {
        ZStack(alignment: .top) {
            if tab.url == nil { NewTabView() }
            else if let error = tab.loadError {
                SurfaceState(symbol: "exclamationmark.shield", title: error.contains("crashed") ? "This page crashed" : "This page couldn’t load", detail: error) {
                    Button("Try again") { tab.reload() }.buttonStyle(.bordered)
                        .accessibilityIdentifier("page.retry").accessibilityLabel("Try again").accessibilityAddTraits(.isButton)
                }
            } else { WebContainer(tab: tab) }
            if tab.signInBlocked, let url = tab.url {
                HStack { Text("This site rejects embedded browser sign-in."); Button("Open in default browser") { app.openInSystemBrowser(url) } }
                    .font(ShellType.secondary).padding(ShellLayout.sectionGap).background(app.pal.elev).foregroundStyle(app.pal.ink)
            }
        }
    }
}

private struct NewTabView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button { app.openCommandBar(newTab: true) } label: {
                        HStack(spacing: ShellLayout.sectionGap) {
                            Image(systemName: "magnifyingglass").font(ShellType.glyph)
                            Text(app.layout == .topTabs ? "Search or ask" : "Search or enter a URL").font(ShellType.row)
                            Spacer()
                            Text("⌘T").font(ShellType.label).padding(.horizontal, ShellLayout.rowInsetLeading / 2).padding(.vertical, PageToolbarGeometry.controlGap)
                                .background(app.pal.rowHover, in: RoundedRectangle(cornerRadius: ShellLayout.chipRadius))
                        }.foregroundStyle(app.pal.ink3).padding(.horizontal, ShellLayout.sectionGap).frame(height: ShellLayout.commandRowHeight)
                            .background(app.pal.fill, in: RoundedRectangle(cornerRadius: ShellLayout.pageRadius))
                    }.buttonStyle(.plain).accessibilityIdentifier("newTab.search")
                        .accessibilityLabel("Search or enter a URL").accessibilityAddTraits(.isButton)

                    if !app.currentThreads.isEmpty {
                        HStack {
                            Text("Recent threads").font(ShellType.label)
                            Spacer()
                            Button("All threads") { app.show(.threads) }.font(ShellType.caption).buttonStyle(.plain)
                                .accessibilityIdentifier("newTab.threads").accessibilityLabel("All threads").accessibilityAddTraits(.isButton)
                        }.foregroundStyle(app.pal.ink3).padding(.top, ShellLayout.pageToolbarHeight).padding(.bottom, ShellLayout.sectionGap)
                        ForEach(app.currentThreads.prefix(3)) { thread in
                            Button { app.openThread(thread) } label: {
                                HStack(spacing: ShellLayout.rowInsetLeading) {
                                    Favicon(host: thread.hosts.first, size: ShellLayout.iconSize)
                                    Text(thread.title).font(ShellType.row).foregroundStyle(app.pal.ink2).lineLimit(1)
                                    Spacer()
                                    Text(thread.end, format: .relative(presentation: .named, unitsStyle: .abbreviated)).font(ShellType.caption).foregroundStyle(app.pal.ink3)
                                }.frame(height: ShellLayout.rowHeight).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("newTab.thread.\(thread.id)").accessibilityLabel(thread.title).accessibilityAddTraits(.isButton)
                        }
                    }
                }
                .frame(maxWidth: 400).padding(.horizontal, 40)
                .padding(.top, max(60, geometry.size.height * 0.34)).padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
        }.background(app.pal.pageBg)
    }
}


extension Notification.Name { static let focusOmnibox = Notification.Name("graphene.focusOmnibox") }

private struct FindBar: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    private var query: String { app.findQuery }
    @State private var found = true
    @State private var counter = FindCounter()
    @State private var requestID = UUID()
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: PageToolbarGeometry.controlGap) {
            Image(systemName: "magnifyingglass").font(ShellType.caption).foregroundStyle(app.pal.ink3).accessibilityHidden(true)
                .padding(.trailing, PageToolbarGeometry.controlGap * 2)
            TextField("Find in page", text: $app.findQuery).textFieldStyle(.plain).font(ShellType.secondary).focused($focused).onSubmit { find() }
                .accessibilityIdentifier("page.find").accessibilityLabel("Find in page")
            if !query.isEmpty { Text(found ? "\(counter.current) of \(counter.total)" : "No matches").font(ShellType.caption).foregroundStyle(app.pal.ink3).help("Matches in the main document; embedded frames are not searched.").accessibilityIdentifier("page.findCount") }
            ToolbarGlyphButton(title: "Previous match", system: "chevron.up", identifier: "page.findPrevious") { find(backwards: true) }
            ToolbarGlyphButton(title: "Next match", system: "chevron.down", identifier: "page.findNext") { find() }
            ToolbarGlyphButton(title: "Close find", system: "xmark", identifier: "page.findClose") { app.findPresented = false }
        }
        .padding(.leading, ShellLayout.sectionGap).padding(.trailing, ShellLayout.windowGap)
        .frame(height: ShellLayout.pageToolbarHeight)
        .background(app.pal.elev)
        .overlay(alignment: .bottom) { Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline) }
            .task { try? await Task.sleep(for: .milliseconds(100)); if !Task.isCancelled && !app.commandBarPresented { focused = true } }.onExitCommand { app.findPresented = false }
            .onChange(of: query) { find() }
            .onChange(of: app.findRequest) { _, _ in find(backwards: app.findBackwards) }
    }
    private func find(backwards: Bool = false) {
        let id = UUID(), text = query; requestID = id
        Task {
            let result = await tab.engine.evaluateJavaScript(FindCounter.script(query: text, backwards: backwards)) as? [String: Int] ?? [:]
            guard requestID == id else { return }
            let count = result["total"] ?? 0
            found = text.isEmpty || count > 0
            counter.select(query: text, current: result["current"] ?? 0, total: count)
        }
    }
}
