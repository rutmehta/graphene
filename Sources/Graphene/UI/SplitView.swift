import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The web surface. In the sidebar layout every pane is its own page card with its own
/// toolbar; split panes sit `windowGap` apart and the focused one carries `focusBorder`.
struct SplitBrowserView: View {
    @EnvironmentObject var app: AppState
    /// The first pane's toolbar keeps clear of the traffic lights (collapsed sidebar).
    var reservesTrafficLights = false
    var cardOriginX: CGFloat = ShellLayout.windowGap
    @State private var dropTarget = false
    var body: some View {
        Group {
            if let group = app.activeSplit {
                SplitBranch(group: group, tabs: app.splitTabs, index: 0, paneCount: app.splitTabs.count,
                            reservesTrafficLights: reservesTrafficLights, cardOriginX: cardOriginX)
            } else if let tab = app.activeTab {
                if app.layout == .sidebar {
                    VStack(spacing: 0) {
                        WebPageToolbar(tab: tab, reservesTrafficLights: reservesTrafficLights, cardOriginX: cardOriginX)
                        BrowserPage(tab: tab)
                    }.id(tab.id).pageCard()
                } else { BrowserPage(tab: tab).overlay(alignment: .top) { PageProgressBar(tab: tab) }.id(tab.id) }
            }
        }.overlay(alignment: .trailing) {
            Rectangle().fill(dropTarget ? app.pal.accentSoft : app.pal.hitTarget).frame(width: ShellLayout.controlSize)
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
    let paneCount: Int
    var reservesTrafficLights: Bool
    var cardOriginX: CGFloat
    var body: some View {
        if let first = tabs.first {
            if tabs.count == 1 { pane(first) }
            else {
                GeometryReader { geo in
                    let length = group.vertical ? geo.size.height : geo.size.width
                    let fraction = group.fractions[safe: index] ?? 0.5
                    let firstLength = SplitCardGeometry.firstPaneLength(available: length, fraction: fraction)
                    let layout = group.vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                    layout {
                        pane(first).frame(width: group.vertical ? nil : firstLength, height: group.vertical ? firstLength : nil)
                        app.pal.hitTarget
                            .frame(width: group.vertical ? nil : SplitCardGeometry.gap, height: group.vertical ? SplitCardGeometry.gap : nil)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside { (group.vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push() } else { NSCursor.pop() }
                            }
                            .gesture(DragGesture(coordinateSpace: .named(group.id.uuidString + String(index))).onChanged { value in
                                let position = group.vertical ? value.location.y : value.location.x
                                app.setSplitFraction(group.id, index: index, fraction: position / max(1, length))
                            })
                            .accessibilityLabel("Resize split divider")
                            .accessibilityAdjustableAction { direction in app.setSplitFraction(group.id, index: index, fraction: fraction + (direction == .increment ? 0.05 : -0.05)) }
                        // Only the first pane shares the card's top-left corner with the traffic lights.
                        AnyView(SplitBranch(group: group, tabs: Array(tabs.dropFirst()), index: index + 1, paneCount: paneCount,
                                            reservesTrafficLights: false, cardOriginX: cardOriginX))
                    }.coordinateSpace(name: group.id.uuidString + String(index))
                }
            }
        }
    }
    private func pane(_ tab: Tab) -> some View {
        VStack(spacing: 0) {
            WebPageToolbar(tab: tab, reservesTrafficLights: reservesTrafficLights, cardOriginX: cardOriginX, paneCount: paneCount)
            BrowserPage(tab: tab)
        }
        .pageCard(focused: app.activeTabID == tab.id)
    }
}
