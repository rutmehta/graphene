import SwiftUI

/// A link previewed over the page card: a scrim over the card and an elevated card at most
/// `peekMaxWidth` wide, `peekInset` from the page card's edges (arc-look.md §3.6).
struct PeekOverlay: View {
    @EnvironmentObject var app: AppState
    let tab: Tab
    var body: some View {
        GeometryReader { geo in
            let frame = PeekGeometry.cardSize(in: geo.size)
            ZStack {
                app.pal.scrim.clipShape(RoundedRectangle(cornerRadius: ShellLayout.pageRadius))
                    .contentShape(Rectangle()).onTapGesture { app.closePeek() }
                TransientBrowser(tab: tab, close: { app.closePeek() })
                    .background(app.pal.elev)
                    .clipShape(RoundedRectangle(cornerRadius: ShellLayout.popoverRadius))
                    .overlay(RoundedRectangle(cornerRadius: ShellLayout.popoverRadius).strokeBorder(app.pal.hairline, lineWidth: ShellLayout.hairline).allowsHitTesting(false))
                    .shadow(color: app.pal.pageShadow, radius: app.pal.pageShadowRadius, y: app.pal.pageShadowY)
                    .frame(width: frame.width, height: frame.height)
            }
        }
    }
}

enum PeekGeometry {
    /// The Peek card inside a page card of `size`: centred, capped at `peekMaxWidth`, inset `peekInset`.
    static func cardSize(in size: CGSize) -> CGSize {
        CGSize(width: max(0, min(ShellLayout.peekMaxWidth, size.width - 2 * ShellLayout.peekInset)),
               height: max(0, size.height - 2 * ShellLayout.peekInset))
    }
}

extension AppState {
    func openExternalURL(_ url: URL) {
        switch ExternalLinkPolicy.destination(url, littleEnabled: littleEnabled) {
        case .little: LittleArcWindow.open(url, app: self)
        case .tab: openTab(url: url, parent: nil, activate: true)
        case nil: break
        }
    }
    func showPeek(_ url: URL) {
        guard ExternalLinkPolicy.destination(url, littleEnabled: false) != nil else { return }
        peekTab?.stop()
        let tab = Tab(engine: WKWebEngine(privateMode: isPrivate), privateMode: isPrivate)
        (tab.engine as? WKWebEngine)?.downloads = downloads
        tab.load(url); peekTab = tab
    }
    func closePeek() { peekTab?.stop(); peekTab = nil }
}
