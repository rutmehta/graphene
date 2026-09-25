import SwiftUI

struct TabPreview: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var tab: Tab
    @ObservedObject private var cache = ThumbnailCache.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tab.isPrivate, let image = cache.images[tab.id] {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(tab.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(2)
            Text(tab.url?.absoluteString ?? "New tab").font(.system(size: 11)).foregroundStyle(app.pal.ink3).lineLimit(2)
            if tab.isDiscarded { Text("Sleeping · restores when selected").font(.system(size: 10)).foregroundStyle(app.pal.ink3) }
        }.padding(12).frame(width: 260).background(app.pal.elev)
    }
}

struct NowPlayingRow: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var tab: Tab
    var body: some View {
        HStack(spacing: 6) {
            IconButton(tab.isPlayingAudio ? "Pause media" : "Play media", system: tab.isPlayingAudio ? "pause.fill" : "play.fill") { app.toggleMedia(tab) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Now playing").font(.system(size: 10)).foregroundStyle(app.pal.ink3)
                Text(tab.displayTitle).font(.system(size: 11)).lineLimit(1)
            }
            Spacer(minLength: 0)
            IconButton("Jump to playing tab", system: "arrow.up.right") { app.activate(tab.id) }
        }.padding(6).background(app.pal.hover, in: RoundedRectangle(cornerRadius: 10))
    }
}
