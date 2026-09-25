import SwiftUI
import AppKit

/// Explicit blank drag regions never cover rows, controls, or text fields.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

struct SidebarSwipe: NSViewRepresentable {
    var switchSpace: (Int) -> Void
    func makeNSView(context: Context) -> SwipeView { let view = SwipeView(); view.switchSpace = switchSpace; return view }
    func updateNSView(_ view: SwipeView, context: Context) { view.switchSpace = switchSpace }
    final class SwipeView: NSView {
        var switchSpace: (Int) -> Void = { _ in }
        private var monitor: Any?
        private var distance: CGFloat = 0
        private var switched = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window, self.bounds.contains(self.convert(event.locationInWindow, from: nil)), event.hasPreciseScrollingDeltas else { return event }
                if event.phase.contains(.began) { self.distance = 0; self.switched = false }
                guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
                self.distance += event.scrollingDeltaX
                if abs(self.distance) > 65 && !self.switched { self.switchSpace(self.distance < 0 ? 1 : -1); self.switched = true }
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

struct SidebarResizeHandle: View {
    @EnvironmentObject var app: AppState
    @Binding var width: CGFloat
    @State private var origin: CGFloat?
    @State private var hovered = false
    var body: some View {
        Rectangle().fill(hovered ? app.pal.hairline : app.pal.hitTarget).frame(width: 4)
            .contentShape(Rectangle()).onHover { hovered = $0; if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if origin == nil { origin = width }
                width = ShellLayout.clampedSidebarWidth((origin ?? width) + value.translation.width)
            }.onEnded { value in
                if (origin ?? width) + value.translation.width < ShellLayout.collapseThreshold { app.toggleSidebar() }
                origin = nil
            })
            .accessibilityLabel("Sidebar width").accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in width = ShellLayout.clampedSidebarWidth(width + (direction == .increment ? 16 : -16)) }
    }
}
