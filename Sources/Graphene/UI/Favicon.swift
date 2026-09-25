import SwiftUI
import AppKit

/// What a row asks `Favicon` for when it shows a saved page: the page's host and, for a web
/// page, its URL, so the cache is looked up by the page's origin (the icon the page declared,
/// as the sidebar shows it) and fetched when missing, rather than matched by host alone.
struct FaviconRequest: Equatable {
    let host: String?
    let url: URL?
    init(page: String) {
        let parsed = URL(string: page)
        host = parsed?.host
        url = parsed.flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil ? $0 : nil }
    }
}

/// Live tabs fetch from their own origin. Library rows only reuse cached icons.
struct Favicon: View {
    let host: String?
    var size: CGFloat = 16
    var url: URL? = nil
    init(host: String?, size: CGFloat = 16, url: URL? = nil) { self.host = host; self.size = size; self.url = url }
    init(_ request: FaviconRequest, size: CGFloat = 16) { self.init(host: request.host, size: size, url: request.url) }
    @EnvironmentObject private var app: AppState
    @Environment(\.pageIsDark) private var pageIsDark
    @ObservedObject private var store = FaviconStore.shared
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
                // A quiet monogram: neutral fill and secondary ink, so placeholders never outshine real marks.
                Text(String(host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
                    .font(.system(size: size * 0.6, weight: .medium))
                    .foregroundStyle(app.pal.page(dark: pageIsDark).ink3)
                    .frame(width: size, height: size)
                    .background(app.pal.page(dark: pageIsDark).fill, in: RoundedRectangle(cornerRadius: ShellLayout.iconBackingRadius))
            } else {
                Image(systemName: "globe").font(.system(size: size * 0.85)).foregroundStyle(app.pal.page(dark: pageIsDark).ink3)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
            .task(id: url) { if !app.isPrivate, let url { await store.fetch(url) } }
    }
}


