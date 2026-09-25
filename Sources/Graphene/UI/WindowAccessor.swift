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
    /// A transparent, full-size titlebar with no separator. AppKit draws the titlebar
    /// separator across the whole window width at the titlebar's bottom edge once a scroll
    /// view (the sidebar list, the page) sits under it; that was the rule through the top band.
    static func flattenTitlebar(_ window: NSWindow) {
        // Each assignment is guarded: this runs after every shell update, and setting the
        // style mask (even to its current value) makes AppKit re-lay out the window frame.
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
        if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
    }
    /// The window number last written to `window.txt`.
    @MainActor private static var writtenWindowNumber: Int?

    /// Diagnostic: prints the theme frame's view tree (class, frame, hidden, layer border/background) to stderr.
    static func dump(_ view: NSView, depth: Int) {
        let pad = String(repeating: "  ", count: depth)
        let layer = view.layer.map { "bw=\($0.borderWidth) bg=\($0.backgroundColor != nil) op=\($0.opacity)" } ?? "nolayer"
        FileHandle.standardError.write("\(pad)\(type(of: view)) \(view.frame) hidden=\(view.isHidden) \(layer)\n".data(using: .utf8)!)
        if depth < 4 { view.subviews.forEach { dump($0, depth: depth + 1) } }
    }

    private func write(_ window: NSWindow?) {
        guard let window, window.windowNumber > 0 else { return }
        state?.attach(window)
        if window.isKeyWindow { onKeyWindow() }
        Self.flattenTitlebar(window)
        if window.isMovableByWindowBackground { window.isMovableByWindowBackground = false }
        if ProcessInfo.processInfo.environment["GRAPHENE_DUMP_WINDOW"] == "1", let frame = window.contentView?.superview {
            Self.dump(frame, depth: 0)
            if let pal = state?.app.pal {
                func hex(_ c: Color) -> String { let n = NSColor(c).usingColorSpace(.sRGB) ?? .black; return String(format: "%d,%d,%d", Int(n.redComponent * 255), Int(n.greenComponent * 255), Int(n.blueComponent * 255)) }
                FileHandle.standardError.write("palette chromeTop=\(hex(pal.chromeTop)) chromeBottom=\(hex(pal.chromeBottom)) sat=\(pal.chromeSaturation)\n".data(using: .utf8)!)
            }
        }
        if !window.styleMask.contains(.fullScreen) {
            for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let button = window.standardWindowButton(kind), let container = button.superview else { continue }
                let centerY = state?.app.layout == .topTabs ? ShellLayout.topTabHeight / 2 : ShellLayout.trafficLightCenterY
                let centerX = ShellLayout.trafficLightLeading + CGFloat(index) * ShellLayout.trafficLightSpacing
                let origin = NSPoint(x: centerX - button.frame.width / 2, y: container.bounds.height - centerY - button.frame.height / 2)
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }
        guard state?.app.isPrivate != true else { return }
        // Written when the number changes, not on every shell update (it was an atomic file
        // write on the main thread each time any window state changed).
        let n = window.windowNumber
        guard Self.writtenWindowNumber != n else { return }
        Self.writtenWindowNumber = n
        try? "\(n)".write(to: Paths.root.appendingPathComponent("window.txt"), atomically: true, encoding: .utf8)
    }
}
