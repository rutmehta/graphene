import SwiftUI
import AppKit

/// Auto-scroll bands at the sidebar scroll view's top and bottom edges. While a sidebar tab
/// drag is `active`, a pointer resting in a band scrolls the list toward it.
///
/// The band is deliberately not a drag destination and never hit-tests: it only polls the
/// pointer. An AppKit drag destination here sat on top of the first and last rows (and the
/// favorites grid) and took their drops, refusing them in `performDragOperation`. A
/// cancelled drag never changes model order; only the final row or section drop mutates tabs.
struct DragAutoScrollEdge: NSViewRepresentable {
    var direction: CGFloat
    var active: Bool
    func makeNSView(context: Context) -> EdgeView {
        let view = EdgeView(); view.direction = direction; view.active = active; return view
    }
    func updateNSView(_ view: EdgeView, context: Context) { view.direction = direction; view.active = active }
    final class EdgeView: NSView {
        var direction: CGFloat = 1
        var active = false {
            didSet { if active != oldValue { active ? start() : stop() } }
        }
        private var timer: Timer?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stop() } else if active { start() }
        }
        private func start() {
            guard timer == nil, window != nil else { return }
            // Common modes, so it also fires inside the drag session's tracking loop.
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        private func stop() { timer?.invalidate(); timer = nil }
        private func tick() {
            guard let window else { stop(); return }
            let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            guard bounds.contains(point) else { return }
            scroll()
        }
        private func scroll() {
            guard let root = window?.contentView else { return }
            let point = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: root)
            func search(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView, scroll.documentView != nil,
                   scroll.convert(scroll.bounds, to: root).insetBy(dx: -4, dy: -16).contains(point), scroll.bounds.width < 380 { return scroll }
                for child in view.subviews { if let found = search(child) { return found } }
                return nil
            }
            guard let scroll = search(root), let document = scroll.documentView else { return }
            let clip = scroll.contentView
            var origin = clip.bounds.origin
            let delta = direction * (document.isFlipped ? 1 : -1) * 10
            origin.y = min(max(0, document.bounds.height - clip.bounds.height), max(0, origin.y + delta))
            clip.scroll(to: origin); scroll.reflectScrolledClipView(clip)
        }
        deinit { timer?.invalidate() }
    }
}
