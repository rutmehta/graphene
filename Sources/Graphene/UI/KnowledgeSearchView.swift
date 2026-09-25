import SwiftUI

/// Captured page context stays put while the user follows links and citations.
struct KnowledgeSearchView: View {
    var scopedNodes: [GraphNode]? = nil
    var threadTitle: String? = nil
    var embedded = false
    var body: some View { ChatView(scopedNodes: scopedNodes, threadTitle: threadTitle, embedded: embedded) }
}

private struct LegacySourceSearchView: View {
    var scopedNodes: [GraphNode]? = nil
    var threadTitle: String? = nil
    var embedded = false
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var assistant = KnowledgeAssistant()
    @State private var query = ""
    @State private var askedQuestion = ""
    @State private var askedScope = ""
    @State private var scope: Scope = .knowledge
    @State private var knowledgeSpaceID: UUID?
    @State private var knowledgeSpaceName = ""
    @State private var pageSource: KnowledgeSource?
    @State private var pageNotes: [Annotation] = []
    @State private var pageCaptureID = UUID()
    @State private var capturingPage = false
    @State private var initialized = false
    @State private var sourcesExpanded = true
    @FocusState private var focused: Bool

    private enum Scope { case page, knowledge, thread }
    private var nodes: [GraphNode] {
        if scope == .thread { return scopedNodes ?? [] }
        return app.graph.search("", spaceID: knowledgeSpaceID ?? app.activeSpaceID, limit: 10000)
    }
    private var notes: [Annotation] {
        if scope == .page { return pageNotes }
        let urls = Set(nodes.map { KnowledgeGraph.canonicalURL($0.url) })
        return app.vault.annotations.filter { note in
            if let spaceID = note.spaceID, scope == .knowledge { return spaceID == (knowledgeSpaceID ?? app.activeSpaceID) }
            return urls.contains(KnowledgeGraph.canonicalURL(note.url))
        }
    }
    private var results: [KnowledgeSource] {
        if !app.attachedSources.isEmpty { return app.attachedSources }
        if scope == .page {
            return (pageSource.map { [$0] } ?? []) + KnowledgeAssistant.retrieve(query: "", nodes: [], annotations: notes)
        }
        return KnowledgeAssistant.retrieve(query: query, nodes: nodes, annotations: notes)
    }
    private var answerContext: [KnowledgeSource] {
        let matches = results.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !matches.isEmpty || scope != .thread { return matches }
        return KnowledgeAssistant.retrieve(query: "", nodes: nodes, annotations: notes).filter { !$0.text.isEmpty }
    }
    private var scopeLabel: String {
        switch scope {
        case .page: return "This page"
        case .knowledge: return knowledgeSpaceName.isEmpty ? app.activeSpace.name : knowledgeSpaceName
        case .thread: return "This thread"
        }
    }
    private var pageHasChanged: Bool {
        guard scope == .page, let url = app.activeTab?.url?.absoluteString else { return false }
        return pageSource.map { KnowledgeGraph.canonicalURL($0.url) != KnowledgeGraph.canonicalURL(url) } ?? true
    }
    private var canAsk: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !answerContext.isEmpty && !capturingPage && assistant.unavailableReason == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            contextPicker
            Rectangle().fill(app.pal.hairline.opacity(0.65)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if askedQuestion.isEmpty { introduction }
                    else { response }
                    if let error = assistant.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 12)).foregroundStyle(app.pal.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    sources
                }.padding(.horizontal, 20).padding(.vertical, 24)
            }
            composer
        }
        .frame(width: embedded ? nil : 680, height: embedded ? nil : 660)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(app.pal.ground).foregroundStyle(app.pal.ink)
        .task {
            guard !initialized else { return }
            initialized = true
            knowledgeSpaceID = app.activeSpaceID
            knowledgeSpaceName = app.activeSpace.name
            if scopedNodes != nil { scope = .thread }
            else if embedded, app.activeSurface == .web, app.activeTab?.url != nil {
                scope = .page
                await capturePage()
            }
            try? await Task.sleep(for: .milliseconds(100))
            if !Task.isCancelled && !app.commandBarPresented { focused = true }
        }
        .onDisappear { assistant.cancel(); pageCaptureID = UUID() }
        .task(id: app.askRequest?.id) {
            guard let request = app.askRequest else { return }
            query = request.query
            if app.attachedSources.isEmpty {
                for id in request.tabIDs {
                    guard let tab = app.tabs.first(where: { $0.id == id }), let url = tab.url, app.captureAllowed(tab) else { continue }
                    let text = await tab.engine.captureSnapshotText()
                    guard !Task.isCancelled, tab.url == url else { continue }
                    app.attachedSources.append(KnowledgeSource(id: tab.currentNodeID ?? tab.id, title: tab.displayTitle, url: url.absoluteString, text: text, kind: "Page"))
                }
            }
            app.askRequest = nil
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle").font(.system(size: 14, weight: .medium)).foregroundStyle(app.pal.accentText)
            Text("Ask Graphene").font(.system(size: 13, weight: .semibold))
            Circle().fill(assistant.unavailableReason == nil ? app.pal.accentText : app.pal.ink3).frame(width: 6, height: 6).help(assistant.unavailableReason ?? "On-device model ready")
            Spacer()
            if !askedQuestion.isEmpty {
                IconButton("New question", system: "square.and.pencil") { resetConversation() }
            }
            IconButton("Close companion", system: "xmark") { close() }
        }.padding(.leading, 20).padding(.trailing, 12).frame(height: 48)
    }

    private var contextPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(app.attachedSources) { source in
                HStack {
                    Label(source.title, systemImage: "paperclip").lineLimit(1)
                    Spacer()
                    Button { app.attachedSources.removeAll { $0.id == source.id } } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Remove \(source.title)")
                }.font(.system(size: 11)).padding(6).background(app.pal.hover, in: Capsule())
            }
            HStack(spacing: 7) {
                scopeButton("This page", symbol: "doc", value: .page)
                    .disabled(app.activeTab?.url == nil && pageSource == nil)
                scopeButton(knowledgeSpaceName.isEmpty ? app.activeSpace.name : knowledgeSpaceName, symbol: "square.stack", value: .knowledge)
                if scopedNodes != nil { scopeButton("Thread", symbol: "point.3.connected.trianglepath.dotted", value: .thread) }
                Spacer(minLength: 0)
            }
            if scope == .page {
                HStack(spacing: 7) {
                    if capturingPage { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "link").font(.system(size: 10)) }
                    Text(pageSource?.title ?? "Reading page…").font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 0)
                }.foregroundStyle(app.pal.ink2)
                if pageHasChanged {
                    Button { Task { await capturePage() } } label: {
                        Label("Use current tab", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 11, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(app.pal.accentText)
                }
            } else {
                Text(scope == .thread ? (threadTitle ?? "Pages and notes in this thread") : "Pages and saved notes in \(scopeLabel)")
                    .font(.system(size: 11)).foregroundStyle(app.pal.ink2).lineLimit(1)
                if scope == .knowledge, knowledgeSpaceID != app.activeSpaceID {
                    Button {
                        knowledgeSpaceID = app.activeSpaceID
                        knowledgeSpaceName = app.activeSpace.name
                        resetConversation()
                    } label: {
                        Label("Use \(app.activeSpace.name)", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 11, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(app.pal.accentText)
                }
            }
        }.padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 16)
    }

    private func scopeButton(_ label: String, symbol: String, value: Scope) -> some View {
        Button {
            guard scope != value || !app.attachedSources.isEmpty else { return }
            app.attachedSources = []
            scope = value
            resetConversation()
            if value == .page, pageSource == nil { Task { await capturePage() } }
        } label: {
            Label(label, systemImage: symbol)
                .font(.system(size: 11, weight: scope == value ? .semibold : .medium)).lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(scope == value ? app.pal.accentSoft : app.pal.hover, in: Capsule())
                .foregroundStyle(scope == value ? app.pal.accentText : app.pal.ink2)
        }.buttonStyle(.plain)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(scope == .page ? "Understand this page" : "Search your sources")
                .font(.system(size: 19, weight: .semibold)).tracking(-0.4)
            Text(scope == .page ? "Ask about this page while you keep reading." : "Find something you read, or ask what your sources say.")
                .font(.system(size: 13)).foregroundStyle(app.pal.ink2).lineSpacing(4)
            if scope != .knowledge, !answerContext.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    suggestion(scope == .page ? "Summarize this page" : "Summarize this thread")
                    suggestion("What are the key ideas?")
                }.padding(.top, 2)
            }
        }
    }

    private func suggestion(_ text: String) -> some View {
        Button { query = text; if canAsk { ask() } else { focused = true } } label: {
            HStack(spacing: 8) {
                Text(text).font(.system(size: 12))
                Spacer()
                Image(systemName: "arrow.up.left").font(.system(size: 10))
            }.foregroundStyle(app.pal.ink2).padding(.horizontal, 11).padding(.vertical, 10)
                .background(app.pal.hover, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }

    private var response: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Spacer(minLength: 24)
                Text(askedQuestion).font(.system(size: 13)).lineSpacing(3)
                    .padding(.horizontal, 13).padding(.vertical, 11)
                    .background(app.pal.hover, in: RoundedRectangle(cornerRadius: 13))
            }
            HStack(spacing: 6) {
                Image(systemName: "sparkle").foregroundStyle(app.pal.accentText)
                Text("Graphene").fontWeight(.semibold)
                Spacer()
                Text(askedScope).foregroundStyle(app.pal.ink3).lineLimit(1)
            }.font(.system(size: 11))
            if assistant.isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the sources…").font(.system(size: 12)).foregroundStyle(app.pal.ink2)
                }
            }
            if !assistant.answer.isEmpty {
                Text(.init(assistant.answer)).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
            } else if !assistant.isWorking, assistant.error == nil {
                Text("Answer stopped. Ask again below to retry.").font(.system(size: 12)).foregroundStyle(app.pal.ink2)
            }
            if !assistant.answerSources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(assistant.answerSources.enumerated()), id: \.element.id) { index, source in
                        Button { open(source) } label: {
                            HStack(spacing: 7) {
                                Text("\(index + 1)").font(.system(size: 9, weight: .semibold))
                                    .frame(width: 17, height: 17).background(app.pal.hover, in: RoundedRectangle(cornerRadius: 4))
                                Text(source.title).font(.system(size: 11)).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").font(.system(size: 9))
                            }.foregroundStyle(app.pal.ink2).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var sources: some View {
        DisclosureGroup(isExpanded: $sourcesExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(results) { source in
                    Button { open(source) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Favicon(host: URL(string: source.url)?.host, size: 16)
                                Text(source.title).font(.system(size: 12, weight: .medium)).foregroundStyle(app.pal.ink).lineLimit(2)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(app.pal.ink3)
                            }
                            Text(URL(string: source.url)?.host ?? source.url).font(.system(size: 10)).foregroundStyle(app.pal.ink3).lineLimit(1)
                            if !source.text.isEmpty {
                                Text(excerpt(source.text)).font(.system(size: 11)).foregroundStyle(app.pal.ink2).lineLimit(3).lineSpacing(3)
                            }
                        }.multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Rectangle().fill(app.pal.hairline.opacity(0.6)).frame(height: 1)
                }
                if results.isEmpty {
                    Text(query.isEmpty ? "Your browsed pages and saved notes will appear here." : "No matching sources. Try a topic, website, or a phrase you remember.")
                        .font(.system(size: 12)).foregroundStyle(app.pal.ink2).lineSpacing(3).padding(.vertical, 14)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(query.isEmpty || scope == .page ? "Sources" : "Matching sources").font(.system(size: 11, weight: .semibold))
                Text("\(results.count)").font(.system(size: 10)).foregroundStyle(app.pal.ink3)
            }
        }.tint(app.pal.ink3)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 10) {
                TextField(scope == .page ? "Ask about this page…" : "Find a source or ask a question…", text: $query, axis: .vertical)
                    .font(.system(size: 13)).lineLimit(2...5).textFieldStyle(.plain).focused($focused)
                    .onSubmit { ask() }.accessibilityLabel("Ask Graphene")
                HStack {
                    Label("On-device", systemImage: "internaldrive").font(.system(size: 10)).foregroundStyle(app.pal.ink3)
                    Spacer()
                    Button {
                        if assistant.isWorking { assistant.cancel() } else { ask() }
                    } label: {
                        Image(systemName: assistant.isWorking ? "stop.fill" : "arrow.up")
                            .font(.system(size: 12, weight: .semibold)).frame(width: 27, height: 27)
                            .foregroundStyle(canAsk || assistant.isWorking ? Color.white : app.pal.ink3)
                            .background(canAsk || assistant.isWorking ? app.pal.accent : app.pal.hover, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).disabled(!canAsk && !assistant.isWorking)
                        .help(assistant.isWorking ? "Stop answering" : "Ask Graphene")
                        .accessibilityLabel(assistant.isWorking ? "Stop answering" : "Send question")
                }
            }.padding(12)
                .dropDestination(for: String.self) { strings, _ in
                    guard !app.isPrivate, let value = strings.first, let id = payloadID(value, prefix: "note:"),
                          let note = app.vault.annotations.first(where: { $0.id == id }) else { return false }
                    if !app.attachedSources.contains(where: { $0.id == id }) {
                        app.attachedSources.append(KnowledgeSource(id: id, title: note.title, url: note.url, text: note.text + "\n" + note.note, kind: "Vault note"))
                    }
                    return true
                }
                .background(app.pal.elev, in: RoundedRectangle(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(focused ? app.pal.accent.opacity(0.45) : app.pal.hairline, lineWidth: 1) }
            Text(assistant.unavailableReason ?? "Answers use the sources shown above.")
                .font(.system(size: 10)).foregroundStyle(app.pal.ink3).lineSpacing(2)
        }.padding(14)
    }

    private func resetConversation() {
        assistant.reset()
        askedQuestion = ""
        askedScope = ""
        sourcesExpanded = true
        focused = true
    }
    private func ask() {
        guard canAsk else { return }
        askedQuestion = query.trimmingCharacters(in: .whitespacesAndNewlines)
        askedScope = scope == .page ? (URL(string: pageSource?.url ?? "")?.host ?? scopeLabel) : scopeLabel
        assistant.ask(askedQuestion, sources: answerContext)
        query = ""
        sourcesExpanded = false
    }
    @MainActor private func capturePage() async {
        guard let tab = app.activeTab, let url = tab.url else { return }
        let captureID = UUID()
        pageCaptureID = captureID
        let title = tab.displayTitle
        let sourceID = tab.currentNodeID ?? UUID()
        let fallback = tab.currentNodeID.flatMap { app.graph.nodes[$0]?.snippet } ?? ""
        pageSource = KnowledgeSource(id: sourceID, title: title, url: url.absoluteString, text: fallback, kind: "Page excerpt")
        pageNotes = app.vault.annotations(forURL: url.absoluteString)
        capturingPage = true
        let text = await tab.engine.captureSnapshotText()
        guard pageCaptureID == captureID else { return }
        capturingPage = false
        // Never attach a subsequent page's text to the page being captured.
        guard tab.url == url else { return }
        pageSource = KnowledgeSource(id: sourceID, title: title, url: url.absoluteString, text: text.isEmpty ? fallback : text, kind: "Page excerpt")
    }
    private func close() {
        if embedded { app.knowledgeSearchPresented = false }
        else { dismiss() }
    }
    private func open(_ source: KnowledgeSource) {
        guard let url = URL(string: source.url) else { return }
        if !embedded { dismiss() }
        app.openTab(url: url, parent: nil, activate: true)
    }
    private func excerpt(_ text: String) -> String {
        for term in query.split(separator: " ").filter({ $0.count > 3 }) {
            if let range = text.range(of: String(term), options: .caseInsensitive) {
                let start = text.index(range.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
                return (start == text.startIndex ? "" : "…") + String(text[start...].prefix(240))
            }
        }
        return String(text.prefix(240))
    }
}
