import SwiftUI
import UniformTypeIdentifiers

struct SplitBrowserView: View {
    @EnvironmentObject var app: AppState
    @State private var dropTarget = false
    var body: some View {
        Group {
            if let group = app.activeSplit {
                SplitBranch(group: group, tabs: app.splitTabs, index: 0)
            } else if let tab = app.activeTab { BrowserPage(tab: tab).id(tab.id) }
        }.overlay(alignment: .trailing) {
            Rectangle().fill(dropTarget ? app.pal.accent.opacity(0.2) : app.pal.ink.opacity(0.001)).frame(width: 24)
                .onDrop(of: [.utf8PlainText], isTargeted: $dropTarget) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadObject(ofClass: NSString.self) { value, _ in
                        guard let payload = value as? String, payload.hasPrefix("tab:"), let id = UUID(uuidString: String(payload.dropFirst(4))) else { return }
                        Task { @MainActor in app.openSplit(id) }
                    }
                    return true
                }
        }
    }
}

private struct SplitBranch: View {
    @EnvironmentObject var app: AppState
    let group: TabSplit
    let tabs: [Tab]
    let index: Int
    var body: some View {
        if let first = tabs.first {
            if tabs.count == 1 { pane(first) }
            else {
                GeometryReader { geo in
                    let length = group.vertical ? geo.size.height : geo.size.width
                    let fraction = group.fractions[safe: index] ?? 0.5
                    let layout = group.vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                    layout {
                        pane(first).frame(width: group.vertical ? nil : max(0, (length - 6) * fraction), height: group.vertical ? max(0, (length - 6) * fraction) : nil)
                        Rectangle().fill(app.pal.hairline)
                            .frame(width: group.vertical ? nil : 6, height: group.vertical ? 6 : nil)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(coordinateSpace: .named(group.id.uuidString + String(index))).onChanged { value in
                                let position = group.vertical ? value.location.y : value.location.x
                                app.setSplitFraction(group.id, index: index, fraction: position / max(1, length))
                            })
                            .accessibilityLabel("Resize split divider")
                            .accessibilityAdjustableAction { direction in app.setSplitFraction(group.id, index: index, fraction: fraction + (direction == .increment ? 0.05 : -0.05)) }
                        AnyView(SplitBranch(group: group, tabs: Array(tabs.dropFirst()), index: index + 1))
                    }.coordinateSpace(name: group.id.uuidString + String(index))
                }
            }
        }
    }
    private func pane(_ tab: Tab) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { app.activate(tab.id) } label: {
                    HStack {
                        Favicon(host: tab.url?.host, size: 14)
                        Text(tab.displayTitle).lineLimit(1)
                        Spacer()
                    }.font(.system(size: 11)).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("split.focus.\(tab.id)")
                    .accessibilityLabel("Focus \(tab.displayTitle)").accessibilityAddTraits(.isButton)
                IconButton("Close pane: \(tab.displayTitle)", system: "xmark") { app.requestCloseTab(tab.id) }
            }.padding(.horizontal, 10).frame(height: 28).foregroundStyle(app.pal.ink2)
                .background(app.activeTabID == tab.id ? app.pal.selection : app.pal.hover)
            BrowserPage(tab: tab)
        }.clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(app.activeTabID == tab.id ? app.pal.accentText.opacity(0.35) : app.pal.hairline, lineWidth: 1))
    }
}
