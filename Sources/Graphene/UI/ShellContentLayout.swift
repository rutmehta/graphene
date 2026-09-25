import SwiftUI

/// Changes geometry, not view identity: the Ask draft and WKWebView survive resizing.
struct ShellContentLayout: Layout {
    var overlayAsk: Bool
    var showAsk: Bool
    var preferredAskWidth: CGFloat = 420
    var floating = true
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 800, height: 600))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let page = subviews.first else { return }
        let inset: CGFloat = floating ? 16 : 0
        let askWidth: CGFloat = showAsk && subviews.count > 1 ? min(preferredAskWidth, max(0, bounds.width - inset * 2)) : 0
        let pageWidth = bounds.width - (floating || overlayAsk || askWidth == 0 ? 0 : askWidth + 8)
        page.place(at: bounds.origin, proposal: ProposedViewSize(width: pageWidth, height: bounds.height))
        if subviews.count > 1 {
            subviews[1].place(at: CGPoint(x: bounds.maxX - askWidth - inset, y: bounds.minY + inset), proposal: ProposedViewSize(width: askWidth, height: max(0, bounds.height - inset * 2)))
        }
    }
}
