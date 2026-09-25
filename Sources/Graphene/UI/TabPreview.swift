import SwiftUI

struct TabPreview: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var tab: Tab
    @ObservedObject private var cache = ThumbnailCache.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tab.isPrivate, let image = cache.images[tab.id] {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            }
            Text(tab.displayTitle).font(ShellType.secondary.weight(.medium)).lineLimit(2)
            Text(tab.url?.absoluteString ?? "New tab").font(ShellType.caption).foregroundStyle(app.pal.ink3).lineLimit(2)
            if tab.isDiscarded { Text("Sleeping · restores when selected").font(ShellType.caption).foregroundStyle(app.pal.ink3) }
        }.padding(12).frame(width: 260).background(app.pal.elev)
    }
}

/// Shown above the sidebar footer only while a tab owns media playback.
struct NowPlayingRow: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var tab: Tab
    var body: some View {
        HStack(spacing: ShellLayout.iconGap) {
            SidebarGlyphButton(tab.isPlayingAudio ? "Pause media" : "Play media", system: tab.isPlayingAudio ? "pause.fill" : "play.fill", identifier: "sidebar.media.toggle") { app.toggleMedia(tab) }
            VStack(alignment: .leading, spacing: 0) {
                Text("Now playing").font(ShellType.caption).foregroundStyle(app.pal.ink3)
                Text(tab.displayTitle).font(ShellType.caption).foregroundStyle(app.pal.ink2).lineLimit(1)
            }
            Spacer(minLength: 0)
            SidebarGlyphButton("Jump to playing tab", system: "arrow.up.right", identifier: "sidebar.media.jump") { app.activate(tab.id) }
        }.frame(height: ShellLayout.rowHeight)
            .background(app.pal.rowHover, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
    }
}
