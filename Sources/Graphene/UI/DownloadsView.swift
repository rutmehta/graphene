import SwiftUI
import AppKit

struct DownloadsButton: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var store: DownloadStore
    var onlyWhenRecent = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if !onlyWhenRecent || app.downloadsPresented || store.hasRecentActivity(at: context.date) { downloadButton }
        }
    }
    private var downloadButton: some View {
        Button { app.downloadsPresented.toggle() } label: {
            Image(systemName: "arrow.down.circle").font(ShellType.glyph)
                .frame(width: ShellLayout.controlSize, height: ShellLayout.controlSize).contentShape(Rectangle())
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : store.completionCount)
        }.buttonStyle(ShellButtonStyle(muted: true)).help("Downloads").accessibilityLabel("Downloads")
            .accessibilityIdentifier("shell.downloads").accessibilityAddTraits(.isButton)
            .popover(isPresented: $app.downloadsPresented) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Downloads").font(ShellType.title); Spacer(); Button("Clear list") { store.clear() } }
                    if let error = store.errorText { Text(error).foregroundStyle(app.pal.ink3) }
                    if store.entries.isEmpty { Text("No downloads yet").foregroundStyle(app.pal.ink3).padding(.vertical, 24) }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(store.entries) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.destination.lastPathComponent).font(ShellType.secondary.weight(.medium)).lineLimit(1)
                                    if entry.status == .active { ProgressView(value: entry.progress) }
                                    HStack {
                                        Text(entry.error ?? entry.status.rawValue.capitalized).foregroundStyle(app.pal.ink3).lineLimit(2)
                                        Spacer()
                                        if entry.status == .finished {
                                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.destination]) }
                                            Button("Open") { NSWorkspace.shared.open(entry.destination) }
                                        }
                                    }.font(ShellType.caption)
                                }.padding(10).background(app.pal.rowHover, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                            }
                        }
                    }.frame(maxHeight: 350)
                }.font(ShellType.body).padding(16).frame(width: 400).foregroundStyle(app.pal.ink).background(app.pal.elev)
            }
    }
}
