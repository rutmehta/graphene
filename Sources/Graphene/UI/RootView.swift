import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 244)
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
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline(scheme)).frame(width: 1) }
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
        }
        .background(Color(nsColor: .textBackgroundColor))
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
        .onAppear { text = urlString }
        .onChange(of: tab.id) { _, _ in text = urlString }
        .onChange(of: tab.url) { _, _ in if !focused { text = urlString } }
        .onChange(of: focused) { _, f in if !f { text = urlString } }
    }

    private var urlString: String { tab.url?.absoluteString ?? "" }

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

private struct NewTabView: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            // a single, restrained warm wash — the brand's warmth, not a neon glow
            RadialGradient(colors: [Theme.accent.opacity(0.10), .clear],
                           center: .init(x: 0.5, y: 0.34), startRadius: 0, endRadius: 460)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()
                Text("Graphene")
                    .font(.system(size: 40, weight: .semibold))
                    .tracking(-0.5)
                Text("Search the web, or pick up a thread.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)

                HStack(spacing: 11) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(.secondary)
                    TextField("Search or enter address", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .focused($focused)
                        .onSubmit { app.submit(text, on: tab) }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.22), radius: 22, y: 8)
                )
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(focused ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.08)))
                .frame(maxWidth: 520)
                .padding(.top, 30)

                Recents(tab: tab).padding(.top, 40)

                Spacer()
                Spacer()
            }
            .padding(40)
        }
        .onAppear { focused = true }
    }
}

private struct Recents: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState

    var body: some View {
        let top = app.graph.topNodes(limit: 5)
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 12).padding(.bottom, 4)
                ForEach(top) { n in RecentRow(node: n, tab: tab) }
            }
            .frame(maxWidth: 520)
        }
    }
}

private struct RecentRow: View {
    let node: GraphNode
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: node.url) { app.submit(url.absoluteString, on: tab) }
        } label: {
            HStack(spacing: 11) {
                Favicon(host: URL(string: node.url)?.host, size: 16)
                Text(node.title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 12)
                Text(URL(string: node.url)?.host ?? "")
                    .font(.system(size: 12)).foregroundStyle(.tertiary).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
