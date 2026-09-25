import SwiftUI
import AppKit

/// Pure geometry and state mapping for the page toolbar (arc-look.md §3.2), kept
/// separate from the views so it can be tested without a window.
enum PageToolbarGeometry {
    /// The address run never grows wider than this fraction of the card.
    static let addressMaxFraction: CGFloat = 0.6
    /// A just-started load still shows a sliver of progress.
    static let minimumProgress: Double = 0.05
    /// Progress width follows `estimatedProgress` with this ease-out.
    static let progressEase: Double = 0.15
    /// The bar fades out over this long once loading completes.
    static let progressFade: Double = 0.2
    /// Hover fills fade in over this long.
    static let hoverFade: Double = 0.1
    /// Gap between toolbar controls.
    static let controlGap: CGFloat = 2

    /// Leading inset of the left group inside the card. When the card sits under the
    /// traffic lights (collapsed sidebar, Little Arc) the group starts at `trafficReserve`
    /// measured from the window edge, so the lights never overlap a control.
    static func leadingInset(reservesTrafficLights: Bool, cardOriginX: CGFloat) -> CGFloat {
        reservesTrafficLights ? max(ShellLayout.windowGap, ShellLayout.trafficReserve - cardOriginX) : ShellLayout.windowGap
    }
    static func addressMaxWidth(cardWidth: CGFloat) -> CGFloat { max(0, cardWidth * addressMaxFraction) }
    /// Fraction of the toolbar width the progress bar covers; a finished load fills the bar before it fades.
    static func progressFraction(isLoading: Bool, progress: Double) -> Double {
        isLoading ? min(1, max(minimumProgress, progress)) : 1
    }
    static func progressOpacity(isLoading: Bool) -> Double { isLoading ? 1 : 0 }
}

/// The address as the toolbar shows it: host in `ink2`, the rest of the URL in `ink3`.
struct AddressParts: Equatable {
    var host: String
    var rest: String
    var secure: Bool
    init?(url: URL?) {
        guard let url else { return nil }
        secure = url.scheme?.lowercased() == "https"
        guard let rawHost = url.host, !rawHost.isEmpty else { host = url.absoluteString; rest = ""; return }
        host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        var tail = url.port.map { ":\($0)" } ?? ""
        let path = url.path
        if path != "/" { tail += path }
        if let query = url.query { tail += "?" + query }
        if let fragment = url.fragment { tail += "#" + fragment }
        rest = tail
    }
}

/// Split-pane lengths along the split axis. Panes are separate cards `windowGap` apart;
/// each fraction is the share the first remaining pane takes of what is left.
enum SplitCardGeometry {
    static let gap: CGFloat = ShellLayout.windowGap
    static func firstPaneLength(available: CGFloat, fraction: Double) -> CGFloat {
        max(0, (available - gap) * CGFloat(fraction))
    }
    static func paneLengths(total: CGFloat, fractions: [Double], count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        var lengths: [CGFloat] = []
        var remaining = total
        for index in 0..<(count - 1) {
            let first = firstPaneLength(available: remaining, fraction: fractions.indices.contains(index) ? fractions[index] : 0.5)
            lengths.append(first)
            remaining = max(0, remaining - first - gap)
        }
        return lengths + [remaining]
    }
}

private struct PageIsDarkKey: EnvironmentKey { static let defaultValue: Bool? = nil }
extension EnvironmentValues {
    /// Set on a web page card: whether its page is dark. `nil` (library views, no report yet)
    /// means the card follows the appearance.
    var pageIsDark: Bool? {
        get { self[PageIsDarkKey.self] }
        set { self[PageIsDarkKey.self] = newValue }
    }
}

/// Publishes a tab's `pageIsDark` to the card and toolbar drawn for it.
private struct FollowsPage: ViewModifier {
    @ObservedObject var tab: Tab
    func body(content: Content) -> some View { content.environment(\.pageIsDark, tab.pageIsDark) }
}

/// The page card treatment: `pageBg`, `pageRadius`, a hairline `pageBorder` (or
/// `focusBorder` for the focused split pane) and `pageShadow`. On a web card the fill
/// and border follow the page (`pageIsDark`), not the appearance.
struct PageCard: ViewModifier {
    @EnvironmentObject var app: AppState
    @Environment(\.pageIsDark) private var pageIsDark
    var focused = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: ShellLayout.pageRadius)
        let page = app.pal.page(dark: pageIsDark)
        content.background(app.pal.pageBg(dark: pageIsDark)).clipShape(shape)
            .overlay(shape.strokeBorder(focused ? app.pal.focusBorder : page.pageBorder, lineWidth: ShellLayout.hairline).allowsHitTesting(false))
            .shadow(color: app.pal.pageShadow, radius: app.pal.pageShadowRadius, y: app.pal.pageShadowY)
    }
}
extension View {
    func pageCard(focused: Bool = false) -> some View { modifier(PageCard(focused: focused)) }
    /// A web page card: `pageCard` whose fill, toolbar and glyphs follow `tab`'s page.
    func webPageCard(_ tab: Tab, focused: Bool = false) -> some View {
        modifier(PageCard(focused: focused)).modifier(FollowsPage(tab: tab))
    }
}

/// A monochrome `controlSize` glyph button: `ink3`, `accent` when on, `inkDisabled` when disabled.
struct ToolbarGlyphButton: View {
    let title: String
    let system: String
    var on = false
    var identifier: String? = nil
    var action: () -> Void
    @EnvironmentObject var app: AppState
    var body: some View {
        Button(action: action) { ToolbarGlyph(system: system, on: on) }
            .buttonStyle(ShellButtonStyle())
            .help(title).accessibilityLabel(title).accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier ?? "toolbar.\(system)")
    }
}
struct ToolbarGlyph: View {
    let system: String
    var on = false
    @EnvironmentObject var app: AppState
    @Environment(\.isEnabled) private var enabled
    @Environment(\.pageIsDark) private var pageIsDark
    var body: some View {
        let pal = app.pal.page(dark: pageIsDark)
        Image(systemName: system).font(ShellType.glyph)
            .foregroundStyle(!enabled ? pal.inkDisabled : on ? pal.accent : app.pal.pageToolbarInk(dark: pageIsDark))
            .frame(width: ShellLayout.controlSize, height: ShellLayout.controlSize).contentShape(Rectangle())
    }
}

/// The 32pt strip at the top of a page card: nav at the left, the address centred,
/// `trailing` controls at the right, and the loading bar along its bottom edge.
struct PageToolbar<Trailing: View>: View {
    @ObservedObject var tab: Tab
    var reservesTrafficLights = false
    var cardOriginX: CGFloat = ShellLayout.windowGap
    /// The collapsed sidebar's toggle leads the nav group, at the band's x = 84.
    var showsSidebarToggle = false
    var showsAddress = true
    /// Clicking the address; `nil` shows it as selectable text instead.
    var addressAction: (() -> Void)? = nil
    /// A click on empty toolbar space; `nil` makes empty space a window drag region.
    var backgroundTap: (() -> Void)? = nil
    /// Strip fill; `nil` is `pageBg`.
    var fill: Color? = nil
    @ViewBuilder var trailing: () -> Trailing
    @EnvironmentObject var app: AppState
    @Environment(\.pageIsDark) private var pageIsDark
    var body: some View {
        let fill = fill ?? app.pal.pageBg(dark: pageIsDark)
        GeometryReader { geometry in
            HStack(spacing: PageToolbarGeometry.controlGap) {
                if showsSidebarToggle { SidebarToggleButton() }
                ToolbarGlyphButton(title: "Back", system: "chevron.left", identifier: "toolbar.back") { tab.goBack() }.disabled(!tab.canGoBack)
                ToolbarGlyphButton(title: "Forward", system: "chevron.right", identifier: "toolbar.forward") { tab.goForward() }.disabled(!tab.canGoForward)
                ToolbarGlyphButton(title: tab.isLoading ? "Stop loading" : "Reload", system: tab.isLoading ? "xmark" : "arrow.clockwise", identifier: "toolbar.reload") {
                    tab.isLoading ? tab.stop() : tab.reload()
                }.disabled(tab.url == nil)
                Group {
                    if showsAddress {
                        PageAddress(tab: tab, action: addressAction)
                            .frame(maxWidth: PageToolbarGeometry.addressMaxWidth(cardWidth: geometry.size.width))
                    }
                }.frame(maxWidth: .infinity)
                HStack(spacing: PageToolbarGeometry.controlGap) { trailing() }
            }
            .padding(.leading, PageToolbarGeometry.leadingInset(reservesTrafficLights: reservesTrafficLights, cardOriginX: cardOriginX))
            .padding(.trailing, ShellLayout.windowGap)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: ShellLayout.pageToolbarHeight)
        .background {
            if let backgroundTap { fill.contentShape(Rectangle()).onTapGesture(perform: backgroundTap) }
            else { fill.overlay(WindowDragRegion()) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(app.pal.page(dark: pageIsDark).hairline).frame(height: ShellLayout.hairline).allowsHitTesting(false)
                .overlay(alignment: .leading) { PageProgressBar(tab: tab) }
        }
    }
}

/// 2pt `accent` bar tracking `estimatedProgress` (ease-out 150ms), fading out 200ms at completion.
struct PageProgressBar: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    @Environment(\.pageIsDark) private var pageIsDark
    private static var height: CGFloat { ShellLayout.hairline * 2 }
    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(app.pal.page(dark: pageIsDark).accent)
                .frame(width: geometry.size.width * PageToolbarGeometry.progressFraction(isLoading: tab.isLoading, progress: tab.progress), height: Self.height)
                .animation(.easeOut(duration: PageToolbarGeometry.progressEase), value: tab.progress)
                .opacity(PageToolbarGeometry.progressOpacity(isLoading: tab.isLoading))
                .animation(.easeOut(duration: PageToolbarGeometry.progressFade), value: tab.isLoading)
        }
        .frame(height: Self.height).allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The flat address run: lock when secure, host in `ink2`, the rest in `ink3`, middle-truncated.
struct PageAddress: View {
    @ObservedObject var tab: Tab
    var action: (() -> Void)?
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageIsDark) private var pageIsDark
    @State private var hovered = false
    private var parts: AddressParts? { AddressParts(url: tab.url) }
    private var ink2: Color { app.pal.pageToolbarInkStrong(dark: pageIsDark) }
    private var ink3: Color { app.pal.pageToolbarInk(dark: pageIsDark) }
    var body: some View {
        Group {
            if let action {
                Button(action: action) { run }.buttonStyle(.plain)
                    .background(hovered ? app.pal.page(dark: pageIsDark).rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                    .onHover { hovered = $0 }
                    .animation(reduceMotion ? nil : .easeOut(duration: PageToolbarGeometry.hoverFade), value: hovered)
                    .help("Open location (⌘L)")
                    .accessibilityLabel(tab.url?.absoluteString ?? "Open location")
                    .accessibilityIdentifier("page.location").accessibilityAddTraits(.isButton)
            } else {
                run.textSelection(.enabled).accessibilityIdentifier("page.url")
            }
        }
        .contextMenu {
            if action != nil { CaptureSiteMenu(tab: tab) }
            if let url = tab.url {
                Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) }
            }
        }
    }
    private var run: some View {
        HStack(spacing: PageToolbarGeometry.controlGap * 2) {
            if parts?.secure == true {
                Image(systemName: "lock.fill").font(ShellType.caption).foregroundStyle(ink3).accessibilityHidden(true)
            }
            if let parts {
                Text("\(Text(parts.host).foregroundStyle(ink2))\(Text(parts.rest).foregroundStyle(ink3))")
                    .font(ShellType.caption).lineLimit(1).truncationMode(.middle)
            } else {
                Text("Search or enter URL").font(ShellType.caption).foregroundStyle(ink3).lineLimit(1)
            }
        }
        .padding(.horizontal, ShellLayout.rowInsetLeading)
        .frame(height: ShellLayout.controlSize)
        .contentShape(Rectangle())
    }
}

/// The web surface's toolbar: page nav and address plus site controls, chat and split,
/// and a close-pane glyph when the card is one of several split panes.
struct WebPageToolbar: View {
    @ObservedObject var tab: Tab
    var reservesTrafficLights = false
    var cardOriginX: CGFloat = ShellLayout.windowGap
    var paneCount = 1
    @EnvironmentObject var app: AppState
    private var canSplit: Bool { (app.activeSplit?.tabIDs.count ?? 1) < 4 }
    var body: some View {
        PageToolbar(tab: tab, reservesTrafficLights: reservesTrafficLights, cardOriginX: cardOriginX,
                    showsSidebarToggle: reservesTrafficLights && app.layout == .sidebar,
                    showsAddress: app.settings.addressPlacement == .onPage,
                    addressAction: { app.activate(tab.id); app.focusAddress() },
                    backgroundTap: paneCount > 1 ? { app.activate(tab.id) } : nil) {
            SiteControlsButton(tab: tab)
            ToolbarGlyphButton(title: "Ask Graphene (⌘K)", system: "sparkle", on: app.knowledgeSearchPresented, identifier: "toolbar.chat") {
                app.toggleKnowledge()
            }.disabled(app.isPrivate)
            ToolbarGlyphButton(title: "Split view", system: "rectangle.split.2x1", identifier: "toolbar.split") {
                app.activate(tab.id); app.commandActions.first { $0.id == "split" }?.run()
            }.disabled(tab.url == nil || !canSplit)
            if paneCount > 1 {
                ToolbarGlyphButton(title: "Close pane: \(tab.displayTitle)", system: "xmark", identifier: "split.close.\(tab.id)") {
                    app.requestCloseTab(tab.id)
                }
            }
        }
    }
}

struct SidebarToggleButton: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ToolbarGlyphButton(title: "Show sidebar (⌘S)", system: "sidebar.left", identifier: "toolbar.sidebar") { app.toggleSidebar() }
    }
}
