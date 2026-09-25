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
            Image(systemName: "arrow.down.circle").font(.system(size: 13)).frame(width: 26, height: 28)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : store.completionCount)
        }.buttonStyle(.plain).help("Downloads").accessibilityLabel("Downloads")
            .accessibilityIdentifier("shell.downloads").accessibilityAddTraits(.isButton)
            .popover(isPresented: $app.downloadsPresented) {
                VStack(alignment: .leading, spacing: ShellLayout.windowGap) {
                    HStack { Text("Downloads").font(ShellType.title); Spacer(); Button("Clear list") { store.clear() }.font(ShellType.secondary) }
                    if let error = store.errorText { Text(error).font(ShellType.secondary).foregroundStyle(app.pal.danger) }
                    if store.entries.isEmpty { Text("No downloads yet").font(ShellType.row).foregroundStyle(app.pal.ink3).padding(.vertical, 24) }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.entries) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.destination.lastPathComponent).font(ShellType.row).lineLimit(1)
                                    if entry.status == .active { ProgressView(value: entry.progress).tint(app.pal.accent) }
                                    HStack {
                                        Text(entry.error ?? entry.status.rawValue.capitalized).foregroundStyle(entry.error == nil ? app.pal.ink3 : app.pal.danger).lineLimit(2)
                                        Spacer()
                                        if entry.status == .finished {
                                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.destination]) }
                                            Button("Open") { NSWorkspace.shared.open(entry.destination) }
                                        }
                                    }.font(ShellType.caption)
                                }.padding(.horizontal, ShellLayout.rowInsetLeading).padding(.vertical, ShellLayout.windowGap)
                                Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline)
                            }
                        }
                    }.frame(maxHeight: 350)
                }.padding(16).frame(width: 400).foregroundStyle(app.pal.ink).background(app.pal.elev)
            }
    }
}
