import SwiftUI

/// Bottom-centre of the page card: one line of `row` text, an optional action in
/// `accent`, on the shared elevated card. Rises 8pt and fades in (arc-look.md §3.6).
struct ToastOverlay: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .bottom) {
            if let toast = app.toasts.items.first {
                HStack(spacing: 10) {
                    Image(systemName: toast.icon).font(ShellType.glyphSmall).foregroundStyle(app.pal.ink3)
                    Text(toast.title).font(ShellType.row).lineLimit(1).truncationMode(.middle).help(toast.title)
                    if let title = toast.actionTitle {
                        Button(title) { toast.action?(); app.toasts.dismiss(toast.id) }
                            .buttonStyle(.plain).font(ShellType.label).foregroundStyle(app.pal.accent)
                    }
                    Button { app.toasts.dismiss(toast.id) } label: {
                        Image(systemName: "xmark").font(ShellType.glyphMini).foregroundStyle(app.pal.ink3)
                    }.buttonStyle(.plain).accessibilityLabel("Dismiss notification")
                }
                .padding(.horizontal, ShellLayout.windowGap * 2)
                .frame(height: ShellLayout.toastHeight)
                .background(app.pal.elev, in: RoundedRectangle(cornerRadius: ShellLayout.popoverRadius))
                .overlay(RoundedRectangle(cornerRadius: ShellLayout.popoverRadius).strokeBorder(app.pal.hairline, lineWidth: ShellLayout.hairline))
                .shadow(color: app.pal.pageShadow, radius: app.pal.pageShadowRadius, y: app.pal.pageShadowY)
                // The card hugs its text; the frame only caps the width it may grow to.
                .frame(maxWidth: ShellLayout.toastMaxWidth)
                .onHover { app.toasts.isPaused = $0 }
                .id(toast.id)
                .transition(Motion.toast(reduced: reduceMotion))
            }
        }
        .padding(.bottom, ShellLayout.toastInset)
        .animation(Motion.toast.reduced(reduceMotion), value: app.toasts.items.first?.id)
        // The countdown is kept here, not ticked through AppState: a published tick every
        // 250 ms redrew every window (sidebar, toolbar, menus) for as long as a toast showed.
        .task(id: app.toasts.items.first?.id) {
            guard let toast = app.toasts.items.first else { return }
            var remaining = toast.remaining
            while remaining > 0 {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
                if !app.toasts.isPaused { remaining -= 0.25 }
            }
            if app.toasts.items.first?.id == toast.id { app.toasts.expire(toast.id) }
        }
    }
}
