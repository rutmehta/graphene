import SwiftUI

struct ToastOverlay: View {
    @EnvironmentObject var app: AppState
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    var body: some View {
        Group {
            if let toast = app.toasts.items.first {
                HStack(spacing: 10) {
                    Image(systemName: toast.icon).foregroundStyle(app.pal.accentText)
                    Text(toast.title).lineLimit(2)
                    if let title = toast.actionTitle {
                        Button(title) { toast.action?(); app.toasts.dismiss(toast.id) }.buttonStyle(.borderless)
                    }
                    Button { app.toasts.dismiss(toast.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss notification")
                }.font(.system(size: 13)).padding(12).frame(maxWidth: 460)
                    .background(app.pal.elev, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(app.pal.hairline))
                    .shadow(color: app.pal.shadow, radius: 8, y: 3)
                    .onHover { app.toasts.isPaused = $0 }
                    .id(toast.id)
            }
        }.onReceive(timer) { _ in app.tickToasts(seconds: 0.25) }
    }
}
