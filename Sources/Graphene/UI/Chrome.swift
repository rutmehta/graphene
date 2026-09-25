import SwiftUI

/// The flooded window plane: the space's chrome gradient with a fine grain on top.
/// Reduce Transparency drops the grain only.
///
/// The gradient is drawn as two plain colour fills, the bottom colour masked by a
/// clear-to-opaque ramp over the top colour, which composites to the same diagonal
/// gradient. Plain colour fills interpolate under animation (a `LinearGradient` swaps its
/// stops at once), so a space switch cross-fades the chrome over 240ms (arc-look.md §4);
/// Reduce Motion keeps a 120ms fade.
struct ChromeBackground: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let pal = app.pal
        ZStack {
            Rectangle().fill(pal.chromeTop)
            Rectangle().fill(pal.chromeBottom)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
            if !reduceTransparency { ChromeGrain().allowsHitTesting(false) }
        }
        .animation(Motion.gradient.reduced(reduceMotion), value: ChromeColors(pal))
        .ignoresSafeArea().accessibilityHidden(true)
    }
}

/// The two chrome colours the background animates between.
struct ChromeColors: Equatable {
    var top: Color
    var bottom: Color
    init(_ pal: Palette) { top = pal.chromeTop; bottom = pal.chromeBottom }
}

/// 1px noise at the palette's grain opacity. The 2,400 dots are rasterised once per window
/// size into a mask (`MaskRaster`) and filled with the grain colour, so chrome redraws and the
/// space-switch cross-fade composite an image instead of refilling every dot.
struct ChromeGrain: View {
    @EnvironmentObject var app: AppState
    static let dots = 2400
    static let rasterKind = "grain"
    /// Dot `index`'s rect in a plane of `size` points.
    static func dot(_ index: Int, in size: CGSize) -> CGRect {
        CGRect(x: CGFloat((index * 73) % 997) / 997 * size.width, y: CGFloat((index * 193) % 991) / 991 * size.height, width: 1, height: 1)
    }
    static func draw(_ context: CGContext, size: CGSize) {
        for index in 0..<dots { context.fill(dot(index, in: size)) }
    }
    /// The cached mask for a plane of `size` points at `scale`.
    static func mask(size: CGSize, scale: CGFloat) -> CGImage? {
        MaskRaster.shared.image(kind: rasterKind, size: size, scale: scale, draw: draw)
    }
    var body: some View {
        let color = app.pal.chromeGrain
        RasterMaskFill(kind: Self.rasterKind, color: color, draw: Self.draw) { context, size in
            for index in 0..<Self.dots { context.fill(Path(Self.dot(index, in: size)), with: .color(color)) }
        }.accessibilityHidden(true)
    }
}

/// The 1px inner outline drawn over the whole content view.
struct WindowOutline: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        // The hidden titlebar is still a 32pt safe area to SwiftUI; without ignoring it the top
        // stroke lands at y=32 and reads as a rule across the sidebar.
        Rectangle().strokeBorder(app.pal.windowOutline, lineWidth: ShellLayout.windowOutline)
            .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
