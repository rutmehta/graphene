import SwiftUI
import AppKit

/// Native drag destinations at the scroll viewport edges. A cancelled drag never
/// changes model order; only the final row/section drop mutates tabs.
struct DragAutoScrollEdge: NSViewRepresentable {
    var direction: CGFloat
    func makeNSView(context: Context) -> EdgeView {
        let view = EdgeView(); view.direction = direction
        view.registerForDraggedTypes([.string]); return view
    }
    func updateNSView(_ view: EdgeView, context: Context) { view.direction = direction }
    final class EdgeView: NSView {
        var direction: CGFloat = 1
        private var timer: Timer?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard sender.draggingPasteboard.string(forType: .string)?.hasPrefix("tab:") == true else { return [] }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.scroll() }
            }
            return .move
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .move }
        override func draggingExited(_ sender: NSDraggingInfo?) { timer?.invalidate(); timer = nil }
        override func draggingEnded(_ sender: NSDraggingInfo) { timer?.invalidate(); timer = nil }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { timer?.invalidate(); timer = nil; return false }
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
