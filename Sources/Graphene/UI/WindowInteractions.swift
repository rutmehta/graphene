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

/// The sidebar's two-finger horizontal swipe between spaces, decided per gesture.
///
/// The old filter judged every event on its own and swallowed any with |dx| > |dy|. A
/// vertical trackpad scroll routinely carries frames where the horizontal jitter wins, often
/// the `began` frame itself; swallowing those starved the sidebar's scroll view of the
/// gesture's start, so vertical scrolling stalled or never began. Now the gesture's axis is
/// locked once it has travelled a few points: a vertical gesture passes through untouched,
/// as do the frames before the lock, `mayBegin`/`began`/`ended`/`cancelled`, momentum and
/// non-trackpad wheels; only the moving frames of a horizontal gesture are consumed.
struct SidebarSwipeFilter {
    enum Decision: Equatable {
        case pass
        case consume
        /// Consume, and switch space by this step.
        case switchSpace(Int)
    }
    /// Horizontal travel that switches space once per gesture.
    static let threshold: CGFloat = 65
    /// Travel (|dx| + |dy|) after which the gesture's axis is decided; frames before it pass.
    static let lockDistance: CGFloat = 6
    /// A gesture is horizontal only when its sideways travel clearly dominates.
    static let horizontalBias: CGFloat = 1.5
    private(set) var axis: Axis?
    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0
    private var distance: CGFloat = 0
    private var switched = false

    mutating func decide(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, dx: CGFloat, dy: CGFloat, precise: Bool) -> Decision {
        guard precise, momentumPhase.isEmpty else { return .pass }
        if phase.contains(.mayBegin) || phase.contains(.began) { reset() }
        if phase.contains(.ended) || phase.contains(.cancelled) { reset(); return .pass }
        guard phase.contains(.changed) || phase.contains(.began) else { return .pass }
        distance += dx
        if axis == nil {
            travelX += abs(dx); travelY += abs(dy)
            if travelX + travelY >= Self.lockDistance { axis = travelX > travelY * Self.horizontalBias ? .horizontal : .vertical }
        }
        // `began` always reaches the scroll view, whichever way the gesture turns out.
        guard axis == .horizontal, !phase.contains(.began) else { return .pass }
        if abs(distance) > Self.threshold && !switched { switched = true; return .switchSpace(distance < 0 ? 1 : -1) }
        return .consume
    }
    private mutating func reset() { axis = nil; travelX = 0; travelY = 0; distance = 0; switched = false }
}

struct SidebarSwipe: NSViewRepresentable {
    var switchSpace: (Int) -> Void
    func makeNSView(context: Context) -> SwipeView { let view = SwipeView(); view.switchSpace = switchSpace; return view }
    func updateNSView(_ view: SwipeView, context: Context) { view.switchSpace = switchSpace }
    final class SwipeView: NSView {
        var switchSpace: (Int) -> Void = { _ in }
        private var monitor: Any?
        private var filter = SidebarSwipeFilter()
        /// A full-height background under the sidebar: never the target of clicks, drags or
        /// scroll-wheel events, which belong to the rows and the scroll view above it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window, self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                switch self.filter.decide(phase: event.phase, momentumPhase: event.momentumPhase, dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas) {
                case .pass: return event
                case .consume: return nil
                case .switchSpace(let step): self.switchSpace(step); return nil
                }
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

struct SidebarResizeHandle: View {
    @EnvironmentObject var app: AppState
    @Binding var width: CGFloat
    @State private var origin: CGFloat?
    var body: some View {
        Rectangle().fill(app.pal.hitTarget).frame(width: ShellLayout.resizeStrip)
            .contentShape(Rectangle()).onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
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

/// Pure trigger rules for the collapsed sidebar's edge peek, in window-local points
/// (x from the window's left edge). Kept free of AppKit so they are unit-testable.
enum SidebarPeekRule {
    /// Pointer within this many points of the window's left edge arms the peek.
    static let edgeZone: CGFloat = 8
    /// Dwell before the peek appears; long enough to ignore a pointer passing through.
    static let dwell: Duration = .milliseconds(120)
    /// The peek hides once the pointer is this far past the panel's trailing edge.
    static let hideSlack: CGFloat = 16
    static func shouldArm(x: CGFloat, y: CGFloat, windowHeight: CGFloat) -> Bool {
        x >= -edgeZone && x <= edgeZone && y >= 0 && y <= windowHeight
    }
    static func shouldHide(x: CGFloat, y: CGFloat, windowHeight: CGFloat, sidebarWidth: CGFloat) -> Bool {
        x > sidebarWidth + ShellLayout.windowGap + hideSlack || y < 0 || y > windowHeight
    }
}

/// Watches the pointer against the window's left edge while the sidebar is collapsed, the way Arc does:
/// a global and a local NSEvent monitor, so overshooting past the window or resting on the screen edge
/// still counts. Replaces the old 4pt hover strip that only fired when the pointer stopped inside it.
struct SidebarPeekEdgeMonitor: NSViewRepresentable {
    var peeking: Bool
    var sidebarWidth: CGFloat
    var setPeek: (Bool) -> Void
    func makeNSView(context: Context) -> MonitorView { let view = MonitorView(); update(view); return view }
    func updateNSView(_ view: MonitorView, context: Context) { update(view) }
    private func update(_ view: MonitorView) { view.peeking = peeking; view.sidebarWidth = sidebarWidth; view.setPeek = setPeek }
    final class MonitorView: NSView {
        var peeking = false
        var sidebarWidth: CGFloat = ShellLayout.sidebarDefault
        var setPeek: (Bool) -> Void = { _ in }
        private var monitors: [Any] = []
        private var armTask: Task<Void, Never>?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            monitors.forEach { NSEvent.removeMonitor($0) }; monitors = []
            guard window != nil else { return }
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in self?.track(); return event }) { monitors.append(local) }
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.track() }) { monitors.append(global) }
        }
        private func track() {
            guard let window, window.isVisible, !window.isMiniaturized else { return }
            let p = NSEvent.mouseLocation, f = window.frame
            let x = p.x - f.minX, y = f.maxY - p.y
            if peeking {
                if SidebarPeekRule.shouldHide(x: x, y: y, windowHeight: f.height, sidebarWidth: sidebarWidth) { armTask?.cancel(); setPeek(false) }
            } else if SidebarPeekRule.shouldArm(x: x, y: y, windowHeight: f.height) {
                guard armTask == nil else { return }
                armTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: SidebarPeekRule.dwell)
                    guard let self, !Task.isCancelled else { return }
                    let q = NSEvent.mouseLocation, g = self.window?.frame ?? f
                    if SidebarPeekRule.shouldArm(x: q.x - g.minX, y: g.maxY - q.y, windowHeight: g.height) { self.setPeek(true) }
                    self.armTask = nil
                }
            } else { armTask?.cancel(); armTask = nil }
        }
        deinit { monitors.forEach { NSEvent.removeMonitor($0) }; armTask?.cancel() }
    }
}
