import SwiftUI
import AppKit

/// Hosts the active tab's long-lived web view. Each tab owns its WKWebView
/// (retained by the Tab model), so swapping which one is on screen never
/// destroys or reloads the others — background tabs keep running.
struct WebContainer: NSViewRepresentable {
    var tab: Tab

    func makeNSView(context: Context) -> NSView {
        let container = FlippedView()
        install(tab.engine.hostView, in: container)
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
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
    }

    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
