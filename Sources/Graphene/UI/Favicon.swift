import SwiftUI
import AppKit

/// Live tabs fetch from their own origin. Library rows only reuse cached icons.
struct Favicon: View {
    let host: String?
    var size: CGFloat = 16
    var url: URL? = nil
    @EnvironmentObject private var app: AppState
    @Environment(\.pageIsDark) private var pageIsDark
    @ObservedObject private var store = FaviconStore.shared
    private var color: Color {
        let value = (host ?? "").utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % 360 }
        return Color(hue: Double(value) / 360, saturation: 0.35, brightness: 0.65)
    }
    var body: some View {
        Group {
            if let icon = store.image(page: url, host: host) {
                // A dark mark on dark chrome (or a white one on light chrome) sits on a contrast backing.
                if let backing = app.pal.page(dark: pageIsDark).iconBacking(for: store.tone(page: url, host: host)) {
                    Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                        .padding(ShellLayout.iconBackingInset)
                        .background(backing, in: RoundedRectangle(cornerRadius: ShellLayout.iconBackingRadius))
                } else {
                    Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                }
            } else if let host, !host.isEmpty {
                Text(String(host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
                    .font(.system(size: size * 0.65, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: size, height: size)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.24))
            } else {
                Image(systemName: "globe").font(.system(size: size * 0.85)).foregroundStyle(.secondary)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
            .task(id: url) { if !app.isPrivate, let url { await store.fetch(url) } }
    }
}


