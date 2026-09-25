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

/// 1px noise at the palette's grain opacity.
struct ChromeGrain: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        let color = app.pal.chromeGrain
        Canvas { context, size in
            for index in 0..<2400 {
                let x = CGFloat((index * 73) % 997) / 997 * size.width
                let y = CGFloat((index * 193) % 991) / 991 * size.height
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(color))
            }
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
