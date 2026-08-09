import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 232)
            Divider()
            ZStack {
                ContentArea()
                if app.showGraph {
                    GraphView().transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: app.showGraph)
        .overlay(alignment: .trailing) {
            if app.showAnnotations {
                AnnotationPanel()
                    .frame(width: 320)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.showAnnotations)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Graphene")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 44)
            .padding(.top, 24)   // clear the traffic lights

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(app.tabs) { tab in
                        TabRow(tab: tab, isActive: tab.id == app.activeTabID)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            Button {
                app.newTab()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("New Tab")
                    Spacer()
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            Divider()
            HStack(spacing: 4) {
                SidebarTool(system: "point.3.connected.trianglepath.dotted", label: "Graph", on: app.showGraph) {
                    app.showGraph.toggle()
                }
                SidebarTool(system: "highlighter", label: "Notes", on: app.showAnnotations) {
                    app.showAnnotations.toggle()
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
}

private struct TabRow: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    @EnvironmentObject var app: AppState
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if tab.isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: tab.url == nil ? "square.dashed" : "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 16)

            Text(tab.displayTitle)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

            Spacer(minLength: 0)

            if hovering {
                Button {
                    app.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.primary.opacity(0.08) : (hovering ? Color.primary.opacity(0.04) : .clear))
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
                Image(systemName: system).font(.system(size: 12))
                Text(label).font(.system(size: 12))
            }
            .foregroundStyle(on ? Theme.accent : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Color.primary.opacity(0.05) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Content area (toolbar + web / new tab)

private struct ContentArea: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let tab = app.activeTab {
                Toolbar(tab: tab)
                Divider()
                ZStack {
                    WebContainer(tab: tab)
                    if tab.url == nil {
                        NewTabView(tab: tab)
                    }
                }
            } else {
                Spacer()
            }
        }
    }
}

private struct Toolbar: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                navButton("chevron.left", enabled: tab.canGoBack) { app.goBack() }
                navButton("chevron.right", enabled: tab.canGoForward) { app.goForward() }
                navButton(tab.isLoading ? "xmark" : "arrow.clockwise", enabled: true) {
                    tab.isLoading ? app.stop() : app.reload()
                }
            }

            TextField("Search or enter address", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit {
                    app.submit(text)
                    focused = false
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Theme.accent.opacity(0.6) : Color.primary.opacity(0.08)))
                )
                .frame(maxWidth: 620)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .onAppear { syncText() }
        .onChange(of: tab.id) { syncText() }
        .onChange(of: tab.url) { if !focused { syncText() } }
    }

    private func syncText() {
        text = tab.url?.absoluteString ?? ""
    }

    private func navButton(_ system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary.opacity(0.75) : Color.primary.opacity(0.25))
        .disabled(!enabled)
    }
}

private struct NewTabView: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Text("Graphene")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("Search the web, or pick up a thread.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField("Search or enter address", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit { app.submit(text, on: tab) }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.1)))
                )
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { focused = true }
    }
}
