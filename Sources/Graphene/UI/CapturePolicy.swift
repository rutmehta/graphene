import SwiftUI
import AppKit

extension AppState {
    func captureAllowed(_ tab: Tab, url: URL? = nil) -> Bool {
        guard !isPrivate, !pausedSpaces.contains(tab.spaceID ?? activeSpaceID) else { return false }
        guard let host = (url ?? tab.url)?.host?.lowercased() else { return false }
        return !excludedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    func siteCaptureCount(_ host: String) -> Int {
        graph.nodeArray.filter { $0.host.lowercased() == host.lowercased() || $0.host.lowercased().hasSuffix("." + host.lowercased()) }.count
    }
    func forgetSite(_ host: String) {
        excludedHosts.insert(host.lowercased())
        graph.forget(host: host)
        for tab in tabs where tab.url?.host?.lowercased() == host.lowercased() || tab.url?.host?.lowercased().hasSuffix("." + host.lowercased()) == true {
            tab.currentNodeID = nil; tab.currentThreadID = nil; tab.resumeThreadID = nil
        }
        graph.save(); persist()
    }
    func confirmForgetSite(_ host: String) {
        let alert = NSAlert()
        alert.messageText = "Forget \(host)?"
        alert.informativeText = "Remove \(siteCaptureCount(host)) captured pages, their text and visits, including subdomains. Future capture will be disabled. Saved Vault notes are kept."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Forget Site")
        if alert.runModal() == .alertSecondButtonReturn { forgetSite(host) }
    }
}

struct CaptureSiteMenu: View {
    @EnvironmentObject var app: AppState
    let tab: Tab
    var body: some View {
        if let host = tab.url?.host?.lowercased(), !app.isPrivate {
            Toggle("Don’t capture this site", isOn: Binding(get: { app.excludedHosts.contains(host) }, set: { excluded in
                if excluded { app.excludedHosts.insert(host) } else { app.excludedHosts.remove(host) }
                app.persist()
            }))
            Toggle("Pause capture in this space", isOn: Binding(get: { app.pausedSpaces.contains(app.activeSpaceID) }, set: { paused in
                if paused { app.pausedSpaces.insert(app.activeSpaceID) } else { app.pausedSpaces.remove(app.activeSpaceID) }
                app.persist()
            }))
            Button("Forget this site…") { app.confirmForgetSite(host) }
        }
    }
}
