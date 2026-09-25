import SwiftUI
import AppKit

/// Writes the main window's number to a file so a dev screenshot script can
/// capture *only* this window (never the full screen). Debug tooling.
struct WindowAccessor: NSViewRepresentable {
    var onKeyWindow: () -> Void = {}
    var state: WindowState?
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { write(v.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { write(nsView.window) }
    }
    private func write(_ window: NSWindow?) {
        guard let window, window.windowNumber > 0 else { return }
        state?.attach(window)
        if window.isKeyWindow { onKeyWindow() }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        if !window.styleMask.contains(.fullScreen) {
            for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let button = window.standardWindowButton(kind), let container = button.superview else { continue }
                let centerY = state?.app.layout == .topTabs ? ShellLayout.topTabHeight / 2 : ShellLayout.trafficLightCenterY
                let centerX = ShellLayout.trafficLightLeading + CGFloat(index) * ShellLayout.trafficLightSpacing
                button.setFrameOrigin(NSPoint(x: centerX - button.frame.width / 2, y: container.bounds.height - centerY - button.frame.height / 2))
            }
        }
        guard state?.app.isPrivate != true else { return }
        let n = window.windowNumber
        try? "\(n)".write(to: Paths.root.appendingPathComponent("window.txt"), atomically: true, encoding: .utf8)
    }
}
