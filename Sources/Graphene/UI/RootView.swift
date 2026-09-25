import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var windowState: WindowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.openSettings) private var openSettings
    @State private var peekTask: Task<Void, Never>?
    @State private var askResizeStart: Double?

    @State private var addressHovered = false
    @SceneStorage("shell.windowID") private var windowID = UUID().uuidString
    private var sidebarWidth: CGFloat { app.sidebarWidths[windowID].map { CGFloat($0) } ?? app.sidebarWidth }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if app.layout == .sidebar && !app.sidebarCollapsed {
                    Sidebar(width: sidebarWidth).frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    SidebarResizeHandle(width: Binding(get: { sidebarWidth }, set: { app.resizeSidebar($0, windowID: windowID) }))
                }
                ShellContentLayout(overlayAsk: geometry.size.width - (app.sidebarCollapsed || app.layout == .topTabs ? 0 : sidebarWidth + 4) - app.settings.askWidth - 24 < ShellLayout.minimumPageWidth, showAsk: app.knowledgeSearchPresented, preferredAskWidth: app.settings.askWidth, floating: app.settings.chatPanelMode == .floating) {
                    VStack(spacing: 0) {
                        if app.layout == .topTabs { TopTabBar(); TopBrowserToolbar().zIndex(10) }
                        else if app.sidebarCollapsed { WorkspaceToolbar() }
                        if let error = app.graph.errorText ?? app.sessionError {
                            Text(error).font(.system(size: 12)).foregroundStyle(app.pal.ink2)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Group {
                            switch app.activeSurface {
                            case .web:
                                SplitBrowserView()
                            case .threads: LedgerView()
                            case .vault: VaultView()
                            case .mail: MailView()
                            case .board: EaselView()
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(app.pal.ground)
                            .clipShape(RoundedRectangle(cornerRadius: ShellLayout.pageRadius))
                            .padding(app.layout == .topTabs && app.settings.pageGutter ? 6 : 0)
                            .overlay {
                                if app.layout == .topTabs && app.commandBarPresented {
                                    app.pal.scrim.opacity(0.25).contentShape(Rectangle())
                                        .onTapGesture { app.dismissCommandBar() }
                                }
                            }
                    }
                    .background(app.layout == .topTabs ? app.pal.chromeBg : app.pal.ground)
                    .clipShape(RoundedRectangle(cornerRadius: app.sidebarCollapsed ? 0 : 10))
                    .overlay(RoundedRectangle(cornerRadius: app.sidebarCollapsed ? 0 : 10).strokeBorder(app.pal.pageBorder, lineWidth: 0.5))
                    .shadow(color: app.pal.shadow, radius: 4, y: 1)

                    if app.knowledgeSearchPresented {
                        KnowledgeSearchView(scopedNodes: app.currentThreads.first(where: { $0.id == app.knowledgeThreadID })?.nodes,
                                            threadTitle: app.currentThreads.first(where: { $0.id == app.knowledgeThreadID })?.title, embedded: true)
                            .id(app.knowledgeThreadID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(app.pal.ground, in: RoundedRectangle(cornerRadius: 12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(app.pal.ink.opacity(0.07)))
                            .shadow(color: app.pal.shadow, radius: 16, x: -4, y: 6)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(app.pal.hairline).frame(width: 4).contentShape(Rectangle())
                                    .gesture(DragGesture().onChanged { value in
                                        if askResizeStart == nil { askResizeStart = app.settings.askWidth }
                                        app.settings.askWidth = (askResizeStart ?? 420) - value.translation.width
                                    }.onEnded { _ in askResizeStart = nil; app.persist() })
                                    .accessibilityLabel("Resize Ask panel")
                                    .accessibilityIdentifier("chat.resize")
                                    .accessibilityAdjustableAction { direction in
                                        app.settings.askWidth += direction == .increment ? 10 : -10; app.persist()
                                    }
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(app.layout == .topTabs || app.sidebarCollapsed || !app.settings.pageGutter ? 0 : 8).padding(.top, app.layout == .sidebar && app.sidebarCollapsed ? 6 : 0)
            }
            .background(app.pal.sidebarBg)
            .overlay(alignment: .leading) {
                if app.layout == .sidebar && app.sidebarCollapsed {
                    if app.sidebarPeek {
                        Sidebar(width: sidebarWidth).frame(width: sidebarWidth).background(app.pal.sidebarBg)
                            .clipShape(RoundedRectangle(cornerRadius: ShellLayout.pageRadius))
                            .shadow(color: app.pal.shadow, radius: 14, x: 6)
                            .onHover { inside in if !inside && !app.spaceEditorPresented { app.sidebarPeek = false } }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    } else {
                        Rectangle().fill(app.pal.ink.opacity(0.001)).frame(width: 4).onHover { inside in
                            peekTask?.cancel()
                            if inside { peekTask = Task { try? await Task.sleep(for: .milliseconds(200)); if !Task.isCancelled { app.sidebarPeek = true } } }
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if app.layout == .sidebar && app.sidebarCollapsed {
                    Button { app.focusAddress() } label: {
                        Text(app.activeTab?.url?.host ?? "Search or enter URL").font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 18).frame(height: 30)
                            .background(app.pal.elev, in: Capsule()).shadow(color: app.pal.shadow, radius: 8)
                    }.buttonStyle(.plain).help("Open location (⌘L)")
                        .accessibilityIdentifier("page.location").accessibilityLabel("Open location").accessibilityAddTraits(.isButton)
                        .opacity(addressHovered ? 1 : 0).onHover { addressHovered = $0 }.padding(.top, 7)
                }
            }
            .overlay {
                if app.commandBarPresented && app.layout == .sidebar {
                    ZStack(alignment: .top) {
                        app.pal.scrim.opacity(app.layout == .topTabs ? 0.25 : 1)
                            .contentShape(Rectangle()).onTapGesture { app.dismissCommandBar() }
                        CommandBar()
                            .frame(width: min(640, geometry.size.width - 64))
                            .padding(.top, max(70, geometry.size.height * 0.18))
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: app.layout == .topTabs ? .top : .center)))
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                ToastOverlay().padding(.bottom, 24)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: app.sidebarCollapsed)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: app.knowledgeSearchPresented)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: app.commandBarPresented)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: app.sidebarPeek)
        }
        .ignoresSafeArea()
        .background(WindowAccessor(onKeyWindow: { app.focusedWindowID = windowID }, state: windowState))
        .background(TabKeyboardMonitor(app: app))
        .overlay { if !app.switcherIDs.isEmpty { TabSwitcher() } }
        .overlay { if let tab = app.peekTab { PeekOverlay(tab: tab) } }
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
}


private struct WorkspaceToolbar: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack(spacing: 6) {
            if app.sidebarCollapsed {
                IconButton("Show sidebar", system: "sidebar.left") { app.toggleSidebar() }.padding(.leading, 70)
            }
            if app.activeSurface == .web, let tab = app.activeTab { BrowserToolbar(tab: tab) }
            else {
                Text(app.activeSurface.rawValue.capitalized).font(.system(size: 11, weight: .medium)).foregroundStyle(app.pal.ink2).padding(.leading, 6)
                Spacer()
                IconButton("Open location", system: "magnifyingglass") { app.openCommandBar(newTab: true) }
                IconButton("Ask Graphene", system: "sidebar.right") { app.toggleKnowledge() }
            }
        }.padding(.horizontal, 7).frame(height: ShellLayout.toolbarHeight)
            .background(app.pal.chromeBg)
    }
}

private struct BrowserToolbar: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    @State private var addressHovered = false
    var body: some View {
        HStack(spacing: 1) {
            IconButton("Back", system: "chevron.left") { tab.goBack() }.disabled(!tab.canGoBack)
            IconButton("Forward", system: "chevron.right") { tab.goForward() }.disabled(!tab.canGoForward)
            IconButton(tab.isLoading ? "Stop loading" : "Reload", system: tab.isLoading ? "xmark" : "arrow.clockwise") { tab.isLoading ? tab.stop() : tab.reload() }
        }
        Spacer(minLength: 4)
        Button { app.openCommandBar(newTab: false) } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.url?.scheme == "https" ? "lock" : "magnifyingglass").font(.system(size: 9))
                Text(tab.url?.host?.replacingOccurrences(of: "www.", with: "") ?? "Search or enter URL")
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
            }.foregroundStyle(app.pal.ink2).padding(.horizontal, 12).frame(height: 26)
                .background(addressHovered ? app.pal.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).onHover { addressHovered = $0 }.help(tab.url?.absoluteString ?? "Open location (⌘L)")
            .accessibilityLabel("Open location")
            .accessibilityIdentifier("collapsed.location").accessibilityAddTraits(.isButton)
            .contextMenu {
                CaptureSiteMenu(tab: tab)
                if let url = tab.url {
                    Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) }
                }
            }
        Spacer(minLength: 4)
        SiteControlsButton(tab: tab)
        IconButton("Save page or add a note", system: "bookmark") { app.noteComposerPresented = true }.disabled(tab.url == nil || app.isPrivate)
        IconButton("Ask Graphene", system: "sidebar.right") { app.toggleKnowledge() }
    }
}

struct IconButton: View {
    let title: String
    let system: String
    var size: CGFloat
    var action: () -> Void
    @EnvironmentObject var app: AppState
    @FocusState private var focused: Bool
    init(_ title: String, system: String, size: CGFloat = 14, action: @escaping () -> Void) { self.title = title; self.system = system; self.size = size; self.action = action }
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: size, weight: .medium)).frame(width: 26, height: 26)
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
                    .font(.system(size: 12)).padding(12).background(app.pal.elev).foregroundStyle(app.pal.ink)
            }
            if app.findPresented && tab.url != nil { FindBar(tab: tab).frame(maxWidth: .infinity, alignment: .trailing).padding(12) }
            if tab.isLoading {
                GeometryReader { geo in Rectangle().fill(app.pal.accent).frame(width: geo.size.width * max(0.05, tab.progress), height: 2) }.frame(height: 2)
            }
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
}

private struct NewTabView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button { app.openCommandBar(newTab: true) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").font(.system(size: 14))
                            Text(app.layout == .topTabs ? "Search or ask" : "Search or enter a URL").font(.system(size: 14))
                            Spacer()
                            Text("⌘T").font(.system(size: 12)).padding(5).background(app.pal.hover, in: RoundedRectangle(cornerRadius: 5))
                        }.foregroundStyle(app.pal.ink3).padding(.horizontal, 14).frame(height: 44)
                            .background(app.pal.hover.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityIdentifier("newTab.search")
                        .accessibilityLabel("Search or enter a URL").accessibilityAddTraits(.isButton)

                    if !app.currentThreads.isEmpty {
                        HStack {
                            Text("Recent threads").font(.system(size: 11, weight: .medium))
                            Spacer()
                            Button("All threads") { app.show(.threads) }.font(.system(size: 11)).buttonStyle(.plain)
                                .accessibilityIdentifier("newTab.threads").accessibilityLabel("All threads").accessibilityAddTraits(.isButton)
                        }.foregroundStyle(app.pal.ink3).padding(.top, 32).padding(.bottom, 13)
                        ForEach(app.currentThreads.prefix(3)) { thread in
                            Button { app.openThread(thread) } label: {
                                HStack(spacing: 11) {
                                    Favicon(host: thread.hosts.first, size: 14)
                                    Text(thread.title).font(.system(size: 13)).foregroundStyle(app.pal.ink2).lineLimit(1)
                                    Spacer()
                                    Text(thread.end, format: .relative(presentation: .named, unitsStyle: .abbreviated)).font(.system(size: 11)).foregroundStyle(app.pal.ink3)
                                }.frame(height: 32).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("newTab.thread.\(thread.id)").accessibilityLabel(thread.title).accessibilityAddTraits(.isButton)
                        }
                    }
                }
                .frame(maxWidth: 400).padding(.horizontal, 40)
                .padding(.top, max(60, geometry.size.height * 0.34)).padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
        }.background(app.pal.ground)
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
        HStack(spacing: 8) {
            TextField("Find in page", text: $app.findQuery).textFieldStyle(.plain).font(.system(size: 12)).focused($focused).frame(minWidth: 70, idealWidth: 180, maxWidth: 180).onSubmit { find() }
                .accessibilityIdentifier("page.find").accessibilityLabel("Find in page")
            if !query.isEmpty { Text(found ? "\(counter.current) of \(counter.total)" : "No matches").font(.system(size: 10)).foregroundStyle(app.pal.ink3).help("Matches in the main document; embedded frames are not searched.").accessibilityIdentifier("page.findCount") }
            IconButton("Previous match", system: "chevron.up") { find(backwards: true) }
            IconButton("Next match", system: "chevron.down") { find() }
            IconButton("Close find", system: "xmark") { app.findPresented = false }
        }.padding(8).background(app.pal.elev, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(app.pal.hairline))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
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
