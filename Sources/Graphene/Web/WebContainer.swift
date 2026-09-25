import SwiftUI
import AppKit

/// Hosts the active tab's long-lived web view. Each tab owns its WKWebView
/// (retained by the Tab model), so swapping which one is on screen never
/// destroys or reloads the others — background tabs keep running.
struct WebContainer: NSViewRepresentable {
    var tab: Tab
    @EnvironmentObject var app: AppState

    func makeNSView(context: Context) -> NSView {
        let container = FlippedView()
        install(tab.engine.hostView, in: container)
        let host = tab.engine.hostView
        DispatchQueue.main.async {
            guard !app.commandBarPresented, !app.noteComposerPresented, app.activeSplit == nil || app.activeTabID == tab.id else { return }
            container.window?.makeFirstResponder(host)
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let host = tab.engine.hostView
        guard nsView.subviews.first !== host else { return }
        nsView.subviews.forEach { $0.removeFromSuperview() }
        install(host, in: nsView)
        // Focus must follow the swap or keyboard/scroll route to the wrong view.
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(host) }
    }

    private func install(_ host: NSView, in container: NSView) {
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
