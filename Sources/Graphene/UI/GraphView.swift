import SwiftUI

/// History as threads of thought. Each card is one browsing session, laid out
/// chronologically as a timeline-tree. Read top-to-bottom (recent first),
/// left-to-right within a thread; click any page to reopen it.
struct GraphView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let threads = app.graph.threads()
        VStack(spacing: 0) {
            header
            if threads.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(threads) { thread in
                            ThreadCard(thread: thread) { url in
                                app.openTab(url: url, parent: nil, activate: true)
                                app.showGraph = false
                            }
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: 940)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Threads").font(.system(size: 14, weight: .semibold))
            Text("\(app.graph.nodeArray.count) pages").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button { app.showGraph = false } label: {
                Text("Done").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline(scheme)).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: 32, weight: .light)).foregroundStyle(.tertiary)
            Text("No threads yet").font(.system(size: 16, weight: .medium))
            Text("Browse a little — your sessions will appear here as threads of thought.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

struct ThreadCard: View {
    let thread: KnowledgeGraph.Thread
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    var onOpen: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        if thread.query != nil {
                            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Text(thread.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text(meta).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let last = thread.nodes.last, let url = URL(string: last.url) { onOpen(url) }
                } label: {
                    Text("Resume").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentSoft))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 6)

            ThreadTimeline(thread: thread, edges: app.graph.edges, onOpen: onOpen)
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(scheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline(scheme)))
    }

    private var meta: String {
        var parts = [relativeDay(thread.end)]
        parts.append("\(thread.nodes.count) page\(thread.nodes.count == 1 ? "" : "s")")
        if thread.noteCount > 0 { parts.append("\(thread.noteCount) note\(thread.noteCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) { f.dateFormat = "'Today' h:mm a" }
        else if cal.isDateInYesterday(date) { f.dateFormat = "'Yesterday' h:mm a" }
        else { f.dateFormat = "MMM d, h:mm a" }
        return f.string(from: date)
    }
}
