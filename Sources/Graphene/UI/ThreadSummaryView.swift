import SwiftUI

/// The selected thread's streamed summary. Threads owns one: the library bar's "Summarize
/// thread" glyph starts and stops it, and the summary column appears only once it has text,
/// is streaming or has an error to show (`ThreadPanes.showsSummary`).
@MainActor
final class ThreadSummaryModel: ObservableObject {
    @Published private(set) var threadID: UUID?
    @Published private(set) var text = ""
    @Published private(set) var sources: [KnowledgeSource] = []
    @Published private(set) var error: String?
    @Published private(set) var working = false
    private var task: Task<Void, Never>?
    private var token = UUID()

    var showsColumn: Bool { ThreadPanes.showsSummary(text: text, working: working, error: error) }

    /// Shows `thread`'s cached summary (when this profile may still read its sources), else nothing.
    func load(_ thread: KnowledgeGraph.Thread?, app: AppState) {
        guard thread?.id != threadID else { return }
        stop()
        threadID = thread?.id; text = ""; sources = []; error = nil
        guard let thread, let cached = app.graph.summaries[thread.id.uuidString],
              cached.profileID == (app.activeSpace.profileID ?? Profile.defaultID),
              cached.sources.allSatisfy({ app.aiSourceAllowed($0) }) else { return }
        text = cached.text; sources = cached.sources
    }

    func stop() { task?.cancel(); token = UUID(); working = false }

    func toggle(_ thread: KnowledgeGraph.Thread, app: AppState) {
        if working { stop() } else { summarize(thread, app: app) }
    }

    func summarize(_ thread: KnowledgeGraph.Thread, app: AppState) {
        stop(); threadID = thread.id; error = nil
        let registry = app.providerRegistry
        if let reason = registry.unavailableReason { error = reason; return }
        let input = thread.nodes.map { KnowledgeSource(id: $0.id, title: $0.title, url: $0.url, text: $0.snippet, kind: "Thread") }.filter { app.aiSourceAllowed($0) }
        sources = PageContext.budget(input, limit: registry.settings.provider == .onDevice ? 6000 : 24_000).sources
        guard !sources.isEmpty else { error = "No readable, permitted sources in this thread."; return }
        text = ""; working = true
        let id = token, profile = app.activeSpace.profileID ?? Profile.defaultID
        task = Task {
            do {
                let provider = try registry.provider()
                for try await delta in provider.stream(messages: [ChatMessage(role: .system, content: PageContext.instructions), ChatMessage(role: .user, content: "Summarize this thread, citing [n].\n" + PageContext.prompt(sources))]) {
                    guard token == id, !Task.isCancelled, sources.allSatisfy({ app.aiSourceAllowed($0) }) else { return }
                    text += delta
                }
                guard token == id, !Task.isCancelled else { return }
                app.graph.cacheSummary(ThreadSummary(text: text, sources: sources, profileID: profile), threadID: thread.id)
                app.graph.save(); working = false
            } catch {
                guard token == id, !Task.isCancelled else { return }
                self.error = error.localizedDescription; working = false
            }
        }
    }
}

/// The summary column's content (graphene-language.md §5.2): `row` text with the chat panel's
/// numbered index chips; hovering a chip highlights the cited node in the map through `citedNodeID`.
struct ThreadSummaryView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var model: ThreadSummaryModel
    let thread: KnowledgeGraph.Thread
    /// The map's nodes; a citation of any other source highlights nothing.
    var nodeIDs: Set<UUID> = []
    @Binding var citedNodeID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: ShellLayout.sectionGap) {
            if model.working {
                HStack(spacing: ShellLayout.iconGap) {
                    ProgressView().controlSize(.small)
                    Text("Summarizing").font(ShellType.secondary).foregroundStyle(app.pal.ink3)
                }
            }
            if !model.text.isEmpty {
                let sources = model.sources
                ChatMarkdownView(text: model.text, sources: sources, citations: Self.citations(model.text, sources: sources, threadID: thread.id)) { citation in
                    SummaryCitationChip(citation: citation, node: ThreadLayout.nodeID(for: citation, sources: sources, in: nodeIDs),
                                        title: sources.indices.contains(citation.sourceNumber - 1) ? sources[citation.sourceNumber - 1].title : "",
                                        thread: thread, citedNodeID: $citedNodeID)
                }.font(ShellType.row)
            }
            if let issue = model.error { Text(issue).font(ShellType.secondary).foregroundStyle(app.pal.ink3) }
        }
    }
    /// The model's `[n]` markers as chips numbered by the source they cite.
    static func citations(_ text: String, sources: [KnowledgeSource], threadID: UUID) -> [ChatCitation] {
        ChatCitation.assign(answer: text, sources: sources, messageID: threadID, passages: false).map { citation in
            var numbered = citation; numbered.index = citation.sourceNumber; return numbered
        }
    }
}

/// A summary citation: the chat panel's index chip (`elevFill`, 16pt, `chipRadius`). Hovering it
/// highlights the cited node; a click selects that node in the map.
private struct SummaryCitationChip: View {
    @EnvironmentObject var app: AppState
    let citation: ChatCitation
    let node: UUID?
    let title: String
    let thread: KnowledgeGraph.Thread
    @Binding var citedNodeID: UUID?
    var body: some View {
        Button {
            if let node { app.selectedThreadNodeID = node }
        } label: {
            CitationIndexLabel(index: citation.index, active: node != nil && citedNodeID == node, linked: node != nil)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { citedNodeID = node } else if citedNodeID == node { citedNodeID = nil }
        }
        .help(title)
        .accessibilityLabel("Source \(citation.index)\(title.isEmpty ? "" : ": " + title)").accessibilityAddTraits(.isButton)
    }
}
