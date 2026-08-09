import SwiftUI
import AppKit

/// Writes the main window's number to a file so a dev screenshot script can
/// capture *only* this window (never the full screen). Debug tooling.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { write(v.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { write(nsView.window) }
    }
    private func write(_ window: NSWindow?) {
        guard let n = window?.windowNumber, n > 0 else { return }
        try? "\(n)".write(to: Paths.root.appendingPathComponent("window.txt"), atomically: true, encoding: .utf8)
    }
}
