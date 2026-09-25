import SwiftUI

/// Changes geometry, not view identity: the Ask draft and WKWebView survive resizing.
///
/// Floating (and whenever docking would squeeze the page below `minimumPageWidth`),
/// the chat card floats over the page card, inset `windowGap·2` from its top, right
/// and bottom. Docked, the page card gives up `chatWidth + windowGap` and the chat
/// card sits flush with its right edge across the full height (arc-look.md §3.5).
struct ShellContentLayout: Layout {
    var overlayAsk: Bool
    var showAsk: Bool
    var preferredAskWidth: CGFloat = ShellLayout.chatWidth
    var floating = true

    /// Whether the chat card floats over the page card rather than sharing the row with it.
    var floats: Bool { floating || overlayAsk }

    /// The page card's and the chat card's frames inside `bounds`.
    static func frames(in bounds: CGRect, showAsk: Bool, preferredAskWidth: CGFloat, floats: Bool) -> (page: CGRect, chat: CGRect) {
        let inset: CGFloat = floats ? ShellLayout.windowGap * 2 : 0
        let clamped = min(ShellLayout.chatWidthRange.upperBound, max(ShellLayout.chatWidthRange.lowerBound, preferredAskWidth))
        let askWidth: CGFloat = showAsk ? min(clamped, max(0, bounds.width - inset * 2)) : 0
        let pageWidth = bounds.width - (floats || askWidth == 0 ? 0 : askWidth + ShellLayout.windowGap)
        let page = CGRect(x: bounds.minX, y: bounds.minY, width: max(0, pageWidth), height: bounds.height)
        let chat = CGRect(x: bounds.maxX - askWidth - inset, y: bounds.minY + inset,
                          width: askWidth, height: max(0, bounds.height - inset * 2))
        return (page, chat)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 800, height: 600))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let page = subviews.first else { return }
        let frames = Self.frames(in: bounds, showAsk: showAsk && subviews.count > 1, preferredAskWidth: preferredAskWidth, floats: floats)
        page.place(at: frames.page.origin, proposal: ProposedViewSize(frames.page.size))
        if subviews.count > 1 {
            subviews[1].place(at: frames.chat.origin, proposal: ProposedViewSize(frames.chat.size))
        }
    }
}
