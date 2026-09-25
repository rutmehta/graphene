import Foundation

/// Stand-in for G3's `openSource(url:passage:)` (App/AppState+Sources.swift): opens the
/// source in the current tab without highlighting. Deleted when G3 merges.
extension AppState {
    func openSource(url: URL, passage: String?) {
        if let tab = activeTab {
            tab.load(url)
            activeSurface = .web
        } else {
            openTab(url: url, parent: nil, activate: true)
        }
    }
}
