import SwiftUI

/// The thread's streamed summary, in the Thread map's right-hand column (graphene-language.md
/// §5.2): `row` text with the chat panel's numbered index chips; hovering a chip highlights the
/// cited node in the map through `citedNodeID`.
struct ThreadSummaryView: View {
    @EnvironmentObject var app: AppState
    let thread: KnowledgeGraph.Thread
    /// The map's nodes; a citation of any other source highlights nothing.
    var nodeIDs: Set<UUID> = []
    @Binding var citedNodeID: UUID?
    @State private var text = ""
    @State private var sources: [KnowledgeSource] = []
    @State private var error: String?
    @State private var working = false
    @State private var task: Task<Void, Never>?
    @State private var token = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(working ? "Stop summary" : "Summarize thread") { if working { stop() } else { summarize() } }.buttonStyle(.bordered).controlSize(.small)
                if working { ProgressView().controlSize(.small) }
            }
            if !text.isEmpty {
                let sources = sources
                ChatMarkdownView(text: text, sources: sources, citations: Self.citations(text, sources: sources, threadID: thread.id)) { citation in
                    SummaryCitationChip(citation: citation, node: ThreadLayout.nodeID(for: citation, sources: sources, in: nodeIDs),
                                        title: sources.indices.contains(citation.sourceNumber - 1) ? sources[citation.sourceNumber - 1].title : "",
                                        thread: thread, citedNodeID: $citedNodeID)
                }.font(ShellType.row)
            }
            if let issue = error ?? app.providerRegistry.unavailableReason { Text(issue).font(ShellType.secondary).foregroundStyle(app.pal.ink3) }
        }.onAppear {
            if let cached = app.graph.summaries[thread.id.uuidString], cached.profileID == (app.activeSpace.profileID ?? Profile.defaultID), cached.sources.allSatisfy({ app.aiSourceAllowed($0) }) { text = cached.text; sources = cached.sources }
        }.onDisappear { stop() }.onChange(of: app.settings.ai) { _, _ in stop() }
    }
    /// The model's `[n]` markers as chips numbered by the source they cite.
    static func citations(_ text: String, sources: [KnowledgeSource], threadID: UUID) -> [ChatCitation] {
        ChatCitation.assign(answer: text, sources: sources, messageID: threadID, passages: false).map { citation in
            var numbered = citation; numbered.index = citation.sourceNumber; return numbered
        }
    }
    private func stop() { task?.cancel(); token = UUID(); working = false }
    private func summarize() {
        stop(); error = nil
        let registry = app.providerRegistry
        if let reason = registry.unavailableReason { error = reason; return }
        let input = thread.nodes.map { KnowledgeSource(id: $0.id, title: $0.title, url: $0.url, text: $0.snippet, kind: "Thread") }.filter { app.aiSourceAllowed($0) }
        sources = PageContext.budget(input, limit: registry.settings.provider == .onDevice ? 6000 : 24_000).sources
        guard !sources.isEmpty else { error = "No readable, permitted sources in this thread."; return }
        text = ""; working = true; let id = token, profile = app.activeSpace.profileID ?? Profile.defaultID
        task = Task {
            do {
                let provider = try registry.provider()
                for try await delta in provider.stream(messages: [ChatMessage(role: .system, content: PageContext.instructions), ChatMessage(role: .user, content: "Summarize this thread, citing [n].\n" + PageContext.prompt(sources))]) {
                    guard token == id, !Task.isCancelled, sources.allSatisfy({ app.aiSourceAllowed($0) }) else { return }; text += delta
                }
                guard token == id, !Task.isCancelled else { return }
                app.graph.cacheSummary(ThreadSummary(text: text, sources: sources, profileID: profile), threadID: thread.id)
                app.graph.save(); working = false
            } catch { guard token == id, !Task.isCancelled else { return }; self.error = error.localizedDescription; working = false }
        }
    }
}

/// A summary citation: the chat panel's index chip (`elevFill`, 16pt, `chipRadius`). Hovering it
/// highlights the cited node; a click opens that page like a click on the node.
private struct SummaryCitationChip: View {
    @EnvironmentObject var app: AppState
    let citation: ChatCitation
    let node: UUID?
    let title: String
    let thread: KnowledgeGraph.Thread
    @Binding var citedNodeID: UUID?
    var body: some View {
        Button {
            if let node { app.openThreadNode(node, in: thread, asChild: false) }
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
