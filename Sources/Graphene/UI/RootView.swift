import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: app.sidebarWidth)
            ResizeHandle(width: $app.sidebarWidth)
            ZStack {
                if let tab = app.activeTab {
                    ContentArea(tab: tab)
                }
                if app.showGraph {
                    GraphView().transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: app.showGraph)
        .overlay(alignment: .trailing) {
            if app.showAnnotations {
                AnnotationPanel()
                    .frame(width: 340)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: app.showAnnotations)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowAccessor())
    }
}

// MARK: - resizable sidebar divider

private struct ResizeHandle: View {
    @Binding var width: CGFloat
    @Environment(\.colorScheme) private var scheme
    @State private var base: CGFloat?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? Theme.accent.opacity(0.5) : Theme.hairline(scheme))
            .frame(width: hovering ? 2 : 1)
            .frame(width: 10)          // wide invisible hit area, thin visible line
            .contentShape(Rectangle())
            .onHover { h in
                hovering = h
                if h { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if base == nil { base = width }
                        width = min(400, max(210, (base ?? width) + v.translation.width))
                    }
                    .onEnded { _ in base = nil }
            )
    }
}

// MARK: - favicon

private func faviconURL(for host: String?) -> URL? {
    guard let host, !host.isEmpty else { return nil }
    return URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)")
}

private struct Favicon: View {
    let host: String?
    var size: CGFloat = 16
    var body: some View {
        AsyncImage(url: faviconURL(for: host)) { phase in
            switch phase {
            case .success(let img):
                img.resizable().interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            default:
                Image(systemName: "globe").resizable().fontWeight(.light)
                    .foregroundStyle(.tertiary).padding(1)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 15, height: 15)
                Text("Graphene")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.2)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 40)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(app.tabs) { tab in
                        TabRow(tab: tab, isActive: tab.id == app.activeTabID)
                    }
                }
                .padding(.horizontal, 12)
            }

            NewTabButton()

            HStack(spacing: 2) {
                SidebarTool(system: "circle.hexagongrid", label: "Graph", on: app.showGraph) { app.showGraph.toggle() }
                SidebarTool(system: "highlighter", label: "Notes", on: app.showAnnotations) { app.showAnnotations.toggle() }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline(scheme)).frame(height: 1) }
        }
        .background(.regularMaterial)
    }
}

private struct NewTabButton: View {
    @EnvironmentObject var app: AppState
    @State private var hovering = false
    var body: some View {
        Button { app.newTab() } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                Text("New Tab").font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundStyle(hovering ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .onHover { hovering = $0 }
    }
}

private struct TabRow: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    @EnvironmentObject var app: AppState
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if tab.isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.62)
                } else if tab.url == nil {
                    Image(systemName: "sparkle").font(.system(size: 11)).foregroundStyle(Theme.accent)
                } else {
                    Favicon(host: tab.url?.host, size: 16)
                }
            }
            .frame(width: 16, height: 16)

            Text(tab.displayTitle)
                .font(.system(size: 13, weight: isActive ? .medium : .regular))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

            Spacer(minLength: 0)

            if hovering {
                Button { app.closeTab(tab.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isActive ? 0.10 : (hovering ? 0.05 : 0)))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { app.activate(tab.id) }
    }
}

private struct SidebarTool: View {
    let system: String
    let label: String
    let on: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 12, weight: .medium))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(on ? Theme.accent : (hovering ? .primary : .secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(on ? Theme.accentSoft : (hovering ? Color.primary.opacity(0.05) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Content area (toolbar + web / new tab)

private struct ContentArea: View {
    @ObservedObject var tab: Tab
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(tab: tab)
            Rectangle().fill(Theme.hairline(scheme)).frame(height: 1)
            ZStack {
                WebContainer(tab: tab)
                if tab.url == nil {
                    NewTabView(tab: tab)
                }
            }
            .overlay(alignment: .top) { LoadBar(tab: tab) }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct LoadBar: View {
    @ObservedObject var tab: Tab
    var body: some View {
        GeometryReader { geo in
            if tab.isLoading && tab.progress > 0.01 && tab.progress < 1 {
                Rectangle()
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.7), Theme.accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * tab.progress, height: 2.5)
                    .animation(.easeOut(duration: 0.2), value: tab.progress)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 3)
            }
        }
        .frame(height: 2.5)
        .allowsHitTesting(false)
    }
}

private struct Toolbar: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                navButton("chevron.left", enabled: tab.canGoBack) { app.goBack() }
                navButton("chevron.right", enabled: tab.canGoForward) { app.goForward() }
                navButton(tab.isLoading ? "xmark" : "arrow.clockwise", enabled: true) {
                    tab.isLoading ? app.stop() : app.reload()
                }
            }

            HStack(spacing: 9) {
                if let url = tab.url {
                    Image(systemName: url.scheme == "https" ? "lock.fill" : "globe")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                TextField("Search or enter address", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { app.submit(text); focused = false }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(focused ? 0.07 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(focused ? Theme.accent.opacity(0.5) : Theme.hairline(scheme), lineWidth: 1)
            )
            .frame(maxWidth: 640)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.bar)
        // tab.url only changes on an actual navigation (never mid-typing), so an
        // unconditional sync tracks the page without clobbering what you type.
        .onAppear { text = tab.url?.absoluteString ?? "" }
        .onChange(of: tab.url) { _, u in text = u?.absoluteString ?? "" }
        .onChange(of: tab.id) { _, _ in text = tab.url?.absoluteString ?? "" }
    }

    private func navButton(_ system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        NavButton(system: system, enabled: enabled, action: action)
    }
}

private struct NavButton: View {
    let system: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering && enabled ? Color.primary.opacity(0.06) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary.opacity(0.82) : Color.primary.opacity(0.22))
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

/// The homepage: where your work lives. A prominent search, then your recent
/// threads of thought to pick back up — not a generic search screen.
private struct NewTabView: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let threads = app.graph.threads(limit: 6)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // hero
                VStack(spacing: 16) {
                    Text("Graphene")
                        .font(.system(size: 34, weight: .semibold)).tracking(-0.4)
                        .padding(.top, threads.isEmpty ? 120 : 64)
                    HStack(spacing: 11) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(.secondary)
                        TextField("Search the web, or type a URL", text: $text)
                            .textFieldStyle(.plain).font(.system(size: 16))
                            .focused($focused)
                            .onSubmit { app.submit(text, on: tab) }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 6))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(focused ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.08)))
                    .frame(maxWidth: 560)
                }
                .frame(maxWidth: .infinity)

                if !threads.isEmpty {
                    HStack {
                        Text("Pick up a thread")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button { app.showGraph = true } label: {
                            Text("All threads").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                        }.buttonStyle(.plain)
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48).padding(.bottom, 12)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(threads) { t in
                            HomeThreadCard(thread: t) { url in app.submit(url.absoluteString, on: tab) }
                        }
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 60)
                }
            }
            .padding(.horizontal, 40)
        }
        .background(
            ZStack {
                Color(nsColor: .textBackgroundColor)
                RadialGradient(colors: [Theme.accent.opacity(0.08), .clear],
                               center: .init(x: 0.5, y: 0.12), startRadius: 0, endRadius: 520)
                    .blendMode(.plusLighter).allowsHitTesting(false)
            }
        )
        .onAppear { focused = true }
    }
}

/// A compact thread on the homepage: title, the pages as a favicon trail, meta.
private struct HomeThreadCard: View {
    let thread: KnowledgeGraph.Thread
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    var onOpen: (URL) -> Void

    var body: some View {
        Button {
            if let last = thread.nodes.last, let url = URL(string: last.url) { onOpen(url) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    if thread.query != nil {
                        Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(thread.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                }
                // favicon trail
                HStack(spacing: 6) {
                    ForEach(Array(thread.nodes.prefix(7).enumerated()), id: \.offset) { _, n in
                        FaviconImg(host: URL(string: n.url)?.host, size: 17)
                    }
                    if thread.nodes.count > 7 {
                        Text("+\(thread.nodes.count - 7)").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                Text(meta).font(.system(size: 11.5)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(hovering ? 0.06 : 0.03)
                                      : Color.black.opacity(hovering ? 0.04 : 0.02)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(hovering ? Theme.accent.opacity(0.4) : Theme.hairline(scheme)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var meta: String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(thread.end) { f.dateFormat = "'Today' h:mm a" }
        else if Calendar.current.isDateInYesterday(thread.end) { f.dateFormat = "'Yesterday' h:mm a" }
        else { f.dateFormat = "MMM d" }
        var s = "\(f.string(from: thread.end)) · \(thread.nodes.count) pages"
        if thread.noteCount > 0 { s += " · \(thread.noteCount) notes" }
        return s
    }
}
