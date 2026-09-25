import SwiftUI

struct PeekOverlay: View {
    @EnvironmentObject var app: AppState
    let tab: Tab
    var body: some View {
        GeometryReader { geo in
            ZStack {
                app.pal.ink.opacity(0.18).onTapGesture { app.closePeek() }
                TransientBrowser(tab: tab, close: { app.closePeek() })
                    .frame(width: min(900, geo.size.width - 80), height: max(200, geo.size.height - 100))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(app.pal.hairline))
                    .shadow(color: app.pal.shadow, radius: 24)
            }
        }
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
