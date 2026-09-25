import SwiftUI

/// The flooded window plane: the space's chrome gradient with a fine grain on top.
/// Reduce Transparency drops the grain only.
struct ChromeBackground: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            app.pal.sidebarGradient
            if !reduceTransparency { ChromeGrain().allowsHitTesting(false) }
        }.accessibilityHidden(true)
    }
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
        Rectangle().strokeBorder(app.pal.windowOutline, lineWidth: ShellLayout.windowOutline)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
