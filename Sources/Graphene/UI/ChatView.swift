import SwiftUI

struct ChatView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scopedNodes: [GraphNode]?
    let threadTitle: String?
    let embedded: Bool
    @StateObject private var controller = ChatController()
    @State private var store: ChatStore?
    @State private var skills = ChatSkill.defaults
    @State private var query = ""
    @State private var attachments: [KnowledgeSource] = []
    @State private var contexts: Set<ChatSkill.Context> = [.currentTab]
    @State private var capturing = false
    @State private var history = false
    @State private var search = false
    @State private var choosingSkill = false
    @State private var contextDetails = false
    @State private var captureToken = UUID()
    @State private var scopeToken = UUID()
    @FocusState private var focused: Bool
    private var registry: ProviderRegistry { app.providerRegistry }
    private var limit: Int { registry.settings.provider == .onDevice ? 6000 : 24_000 }
    private var budget: PageContext.Budget { PageContext.budget(attachments.filter { app.aiSourceAllowed($0) }, limit: limit) }
    private var mention: String? {
        guard let last = query.split(separator: " ", omittingEmptySubsequences: false).last, last.hasPrefix("@") else { return nil }
        return String(last.dropFirst())
    }
    private var matchingTabs: [Tab] { app.tabs.filter { app.aiTabAllowed($0) && CommandMatch.matches(mention ?? "", title: $0.displayTitle) } }
    private var results: [KnowledgeSource] {
        KnowledgeAssistant.retrieve(query: query, nodes: app.graph.search("", spaceID: app.activeSpaceID, limit: 1000), annotations: app.vault.annotations).filter { app.aiSourceAllowed($0) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            contextBar
            Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if (controller.chat?.messages ?? []).isEmpty && !search {
                            Text(ChatGrounding.emptyState).font(ShellType.secondary).foregroundStyle(app.pal.ink3)
                                .accessibilityIdentifier("chat.emptyState")
                        }
                        ForEach(controller.chat?.messages ?? []) { message in messageView(message) }
                        if search {
                            ForEach(results) { source in
                                Button { open(source) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(source.title).font(ShellType.rowSelected)
                                        Text(String(source.text.prefix(180))).font(ShellType.caption).foregroundStyle(app.pal.ink2).lineLimit(3)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                                    .accessibilityIdentifier("chat.source.\(source.id)").accessibilityLabel(source.title).accessibilityAddTraits(.isButton)
                            }
                            if results.isEmpty { Text("No matching sources.").font(ShellType.secondary).foregroundStyle(app.pal.ink3) }
                        }
                        if let error = controller.error ?? store?.error { Text(error).font(ShellType.secondary).foregroundStyle(app.pal.ink2) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(ShellLayout.windowGap * 2)
                }.onChange(of: controller.chat?.messages.last?.content) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                    // A mark hovered in the page raises its chip; bring the chip into view by the least scroll.
                    .onReceive(app.citations.markRaised) { id in
                        guard !reduceMotion else { proxy.scrollTo(id); return }
                        withAnimation(Motion.hover.animation) { proxy.scrollTo(id) }
                    }
            }
            composer
        }.foregroundStyle(app.pal.ink).background(app.pal.elev).tint(app.pal.accentText)
            .frame(width: embedded ? nil : 680, height: embedded ? nil : 660)
            // The panel's frame over the page, so a scroll to a mark keeps it clear of the panel.
            .background {
                if embedded {
                    GeometryReader { geometry in
                        Color.clear.onAppear { app.citations.panelFrame = geometry.frame(in: .global) }
                            .onChange(of: geometry.frame(in: .global)) { _, frame in app.citations.panelFrame = frame }
                    }
                }
            }
            .task {
                store = ChatStore(root: app.dataDirectory); skills = SkillStore(root: app.dataDirectory).skills
                if let latest = store?.chats.first(where: { $0.spaceID == app.activeSpaceID && $0.profileID == (app.activeSpace.profileID ?? Profile.defaultID) }), app.askRequest == nil, scopedNodes == nil {
                    controller.select(latest); attachments = latest.messages.last?.sources?.filter { app.aiSourceAllowed($0) } ?? []
                } else { await reset() }
                focused = true
            }
            .task(id: app.askRequest?.id) {
                guard let request = app.askRequest else { return }
                query = request.query
                for id in request.tabIDs { if let tab = app.tabs.first(where: { $0.id == id }) { await attach(tab) } }
                attachments += app.attachedSources.filter { app.aiSourceAllowed($0) && !attachments.contains($0) }
                app.askRequest = nil; app.attachedSources = []
            }
            .onChange(of: app.activeSpaceID) { _, _ in controller.stop(); Task { await reset() } }
            .onChange(of: app.settings.ai) { _, _ in controller.stop() }
            .onChange(of: controller.arrived) { _, id in
                guard let id, let chat = controller.chat, let message = chat.messages.first(where: { $0.id == id }), let tab = app.activeTab else { return }
                Task { await ChatView.link(message, citations: chat.citations(for: message), in: tab, app: app) }
            }
            .onDisappear { controller.stop(); captureToken = UUID(); app.citations.clear(); if embedded { app.citations.panelFrame = nil } }
    }
    /// What the model can see, from the attached sources the space allows.
    private var grounding: ChatGrounding { ChatGrounding(sources: attachments.filter { app.aiSourceAllowed($0) }, activeTabID: app.activeTabID) }
    /// Marks an answer's passages in `tab`'s page and links the found chips (D6 §3.4). Private tabs never inject.
    @discardableResult
    static func link(_ message: ChatMessage, citations: [ChatCitation], in tab: Tab, app: AppState) async -> Set<String> {
        guard !app.isPrivate, !tab.isPrivate, app.aiTabAllowed(tab) else { return [] }
        return await app.citations.link(messageID: message.id, citations: citations, sources: message.sources ?? [], tabID: tab.id, url: tab.url, page: .engine(tab.engine))
    }
    private var header: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ask").font(ShellType.title)
                HStack(spacing: ShellLayout.statusDot) {
                    Circle().fill(grounding.grounded ? app.pal.accent : app.pal.ink3).frame(width: ShellLayout.statusDot, height: ShellLayout.statusDot)
                    Text(grounding.line).font(ShellType.caption).foregroundStyle(app.pal.ink3).lineLimit(1)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("chat.grounding")
            }
            Spacer()
            glyphButton("Past chats", system: "clock.arrow.circlepath") { store?.reload(); history.toggle() }
                .popover(isPresented: $history) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Chats in \(app.activeSpace.name)").font(ShellType.title)
                        ScrollView {
                            ForEach((store?.chats ?? []).filter { $0.spaceID == app.activeSpaceID && $0.profileID == (app.activeSpace.profileID ?? Profile.defaultID) }) { chat in
                                HStack {
                                    Button(chat.title) { controller.select(chat); attachments = chat.messages.last?.sources?.filter { app.aiSourceAllowed($0) } ?? []; history = false }.buttonStyle(.plain).lineLimit(2)
                                        .accessibilityIdentifier("chat.history.\(chat.id)").accessibilityLabel(chat.title).accessibilityAddTraits(.isButton)
                                    Spacer()
                                    Button { store?.delete(chat.id); history = false; if controller.chat?.id == chat.id { Task { await reset() } } } label: { Image(systemName: "trash") }.accessibilityLabel("Delete chat")
                                }.font(ShellType.row).padding(.vertical, 6)
                            }
                        }
                    }.padding(16).frame(width: 340, height: 300).background(app.pal.elev)
                }
            glyphButton("New chat", system: "square.and.pencil") { Task { await reset() } }
            glyphButton("Close chat", system: "xmark") { if embedded { app.knowledgeSearchPresented = false } else { dismiss() } }
        }.padding(.leading, ShellLayout.windowGap * 2).padding(.trailing, ShellLayout.windowGap)
            .frame(height: ShellLayout.chatHeaderHeight)
            .help(registry.status + (registry.unavailableReason == nil ? " · Ready" : " · Unavailable"))
    }
    /// Header and context glyphs: 15pt in `ink3`, the shell's quiet control style.
    private func glyphButton(_ title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(ShellType.glyph).foregroundStyle(app.pal.ink3)
                .frame(width: ShellLayout.controlSize, height: ShellLayout.controlSize).contentShape(Rectangle())
        }.buttonStyle(ShellButtonStyle())
            .help(title).accessibilityLabel(title).accessibilityIdentifier("icon.\(system).\(title)")
            .accessibilityAddTraits(.isButton)
    }
    private var contextBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sourcesStrip
            if !budget.notices.isEmpty {
                // A quiet note, not an alert: the budget details stay one click away.
                Button { contextDetails = true } label: {
                    Text(budget.notices.joined(separator: " · ")).font(ShellType.caption).foregroundStyle(app.pal.ink3)
                        .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .padding(.horizontal, ShellLayout.windowGap * 2).padding(.bottom, ShellLayout.windowGap)
                    .help(budget.notices.joined(separator: "\n"))
                    .accessibilityIdentifier("chat.sourceWarnings").accessibilityAddTraits(.isButton)
            }
        }
    }
    private var sourcesStrip: some View {
        HStack(spacing: 4) {
            glyphButton("Context and source budget", system: "slider.horizontal.3") { contextDetails.toggle() }
                .accessibilityIdentifier("chat.contextDetails")
                .popover(isPresented: $contextDetails) { contextOptions.frame(width: 320).padding(.top, 12).background(app.pal.elev) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(attachments) { source in
                        SourceChip(source: source) { attachments.removeAll { $0.id == source.id } }
                    }
                    Button { query += query.isEmpty || query.hasSuffix(" ") ? "@" : " @"; focused = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(ShellType.glyphMini).foregroundStyle(app.pal.ink3)
                            Text("Add")
                        }.font(ShellType.secondary).foregroundStyle(app.pal.ink2)
                            .padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.chipHeight)
                            .background(app.pal.elevFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Attach tabs (@)")
                        .accessibilityIdentifier("chat.addSource").accessibilityLabel("Add a source").accessibilityAddTraits(.isButton)
                }
            }
            if capturing { ProgressView().controlSize(.mini) }
            glyphButton(search ? "Hide source search" : "Search sources", system: "magnifyingglass") { search.toggle() }
                .accessibilityIdentifier("chat.searchSources")
        }.padding(.horizontal, ShellLayout.windowGap).frame(height: ShellLayout.chatHeaderHeight - ShellLayout.windowGap)
    }
    private var contextOptions: some View {
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach([ChatSkill.Context.currentTab, .thread, .vault, .history], id: \.self) { context in
                        Button(context.rawValue) {
                            if contexts.contains(context) { contexts.remove(context) } else { contexts.insert(context) }
                            Task { await collect() }
                        }.buttonStyle(.plain).font(ShellType.secondary)
                            .padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.chipHeight)
                            .background(contexts.contains(context) ? app.pal.accentSoft : app.pal.elevFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                            .accessibilityIdentifier("chat.context.\(context.rawValue)").accessibilityLabel(context.rawValue).accessibilityAddTraits(.isButton)
                            .accessibilityAddTraits(contexts.contains(context) ? [.isSelected] : [])
                            .disabled(context == .thread && scopedNodes == nil && app.activeTab?.currentThreadID == nil)
                    }
                }
            }

            HStack {
                if capturing { ProgressView().controlSize(.mini) }
                Text("\(budget.used) / \(limit) characters" + (registry.settings.provider == .onDevice ? " · on-device budget" : ""))
                Spacer()
                Button("Refresh") { Task { await collect() } }.buttonStyle(.plain)
                    .accessibilityIdentifier("chat.refresh").accessibilityLabel("Refresh context").accessibilityAddTraits(.isButton)
            }.font(ShellType.caption).foregroundStyle(app.pal.ink3)
            if !budget.notices.isEmpty {
                DisclosureGroup("\(budget.notices.count) trimmed or unreadable sources") {
                    ForEach(budget.notices, id: \.self) { Text($0).font(ShellType.caption) }
                }.font(ShellType.caption).foregroundStyle(app.pal.ink2)
            }
        }.padding(.horizontal, 16).padding(.bottom, 12)
    }
    private func messageView(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            if message.role == .user {
                Text(message.content).font(ShellType.row).lineSpacing(ShellType.rowLineSpacing)
                    .foregroundStyle(app.pal.ink2).textSelection(.enabled)
            }
            else {
                let citations = controller.chat?.citations(for: message) ?? []
                let streaming = controller.working && message.id == controller.chat?.messages.last?.id
                ChatMarkdownView(text: message.content, sources: message.sources ?? [], citations: citations) {
                    CitationChip(linker: app.citations, citation: $0, message: message, citations: citations)
                }
                    .foregroundStyle(app.pal.ink)
                if streaming { ProgressView().controlSize(.small) }
                if !citations.isEmpty {
                    // One entry per source, carrying the indices of each passage cited from it.
                    ChatFlow(lineSpacing: ShellLayout.iconBackingInset * 2) {
                        ForEach(ChatCitation.sourcesLine(citations), id: \.first?.citationID) { entry in
                            CitationChip(linker: app.citations, citation: entry[0], message: message, citations: citations, siblings: entry)
                                .padding(.trailing, ShellLayout.iconBackingInset * 2)
                                .background { ForEach(entry.dropFirst()) { Color.clear.frame(width: 0, height: 0).id($0.citationID) } }
                                .id(entry[0].citationID)
                        }
                    }.accessibilityIdentifier("chat.sourcesLine.\(message.id)")
                } else if !streaming, !message.content.isEmpty {
                    Text(ChatGrounding.noSources).font(ShellType.caption).foregroundStyle(app.pal.ink3)
                        .accessibilityIdentifier("chat.noSources.\(message.id)")
                }
                HStack {
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) }
                        .accessibilityIdentifier("chat.copy.\(message.id)").accessibilityLabel("Copy response").accessibilityAddTraits(.isButton)
                    if message.id == controller.chat?.messages.last?.id {
                        Button("Regenerate") { if let store { controller.send("", sources: attachments, app: app, store: store, regenerate: true) } }.disabled(controller.working || registry.unavailableReason != nil)
                            .accessibilityIdentifier("chat.regenerate").accessibilityLabel("Regenerate response").accessibilityAddTraits(.isButton)
                    }
                }.buttonStyle(.plain).font(ShellType.caption).foregroundStyle(app.pal.ink3)
            }
        }.padding(message.role == .user ? 12 : 0).frame(maxWidth: .infinity, alignment: .leading)
            .background(message.role == .user ? app.pal.elevFill : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.popoverRadius))
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let mention {
                VStack(alignment: .leading, spacing: 6) {
                    if "all".hasPrefix(mention.lowercased()) {
                        Button("@all · tabs in this space") { removeMention(); Task { for tab in app.tabs.filter({ $0.spaceID == app.activeSpaceID && app.aiTabAllowed($0) }) { await attach(tab) } } }.buttonStyle(.plain)
                            .accessibilityIdentifier("chat.mentionAll").accessibilityLabel("Attach all tabs in this space").accessibilityAddTraits(.isButton)
                    }
                    ForEach(matchingTabs.prefix(8)) { tab in
                        Button { removeMention(); Task { await attach(tab) } } label: {
                            HStack { Favicon(host: tab.url?.host, size: 14); Text(tab.displayTitle).lineLimit(1) }
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("chat.mention.\(tab.id)").accessibilityLabel("Attach \(tab.displayTitle)").accessibilityAddTraits(.isButton)
                    }
                }.font(ShellType.secondary).padding(10).background(app.pal.elevFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            }
            if choosingSkill || (query.hasPrefix("/") && !query.contains(" ")) {
                ForEach(skills.filter { choosingSkill || $0.trigger.hasPrefix(query.lowercased()) }) { skill in
                    Button {
                        query = skill.trigger + " " + (choosingSkill ? query : "")
                        choosingSkill = false; contexts = Set(skill.contexts); Task { await collect() }
                    } label: {
                        HStack { Text(skill.trigger); Spacer(); Text(skill.contexts.map(\.rawValue).joined(separator: ", ")).foregroundStyle(app.pal.ink3) }
                    }.buttonStyle(.plain).font(ShellType.caption)
                        .accessibilityIdentifier("chat.skill.\(skill.trigger)").accessibilityLabel(skill.trigger).accessibilityAddTraits(.isButton)
                }
            }
            if query.isEmpty && !choosingSkill {
                // Skills are offered only while the composer is empty; typing hides them.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(skills) { skill in
                            Button {
                                query = skill.trigger + " "; contexts = Set(skill.contexts); focused = true; Task { await collect() }
                            } label: {
                                Text(skill.trigger).font(ShellType.label).foregroundStyle(app.pal.ink2)
                                    .padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.chipHeight)
                                    .background(app.pal.elevFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                            }.buttonStyle(.plain).help(skill.name)
                                .accessibilityIdentifier("chat.skillChip.\(skill.trigger)").accessibilityLabel(skill.name).accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 2) {
                composerGlyph("@", font: ShellType.row, label: "Attach tabs", help: "Attach tabs (@)", id: "chat.attach") {
                    query += query.isEmpty || query.hasSuffix(" ") ? "@" : " @"; focused = true
                }
                composerGlyph("/", font: ShellType.glyph, label: "Choose a skill", help: "Choose a skill (/)", id: "chat.chooseSkill") {
                    choosingSkill.toggle(); focused = true
                }
                TextField(grounding.placeholder, text: $query, axis: .vertical).textFieldStyle(.plain).lineLimit(1...5)
                    .font(ShellType.row).focused($focused).onSubmit { send() }.accessibilityLabel("Chat composer")
                    .accessibilityIdentifier("chat.composer")
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                let sendDisabled = !controller.working && (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || capturing || registry.unavailableReason != nil)
                Button { if controller.working { controller.stop(); if let chat = controller.chat { store?.save(chat) } } else { send() } } label: {
                    Image(systemName: controller.working ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(ShellType.input).foregroundStyle(sendDisabled ? app.pal.inkDisabled : app.pal.accent)
                        .frame(width: ShellLayout.controlSize, height: ShellLayout.controlSize).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("chat.send").accessibilityLabel(controller.working ? "Stop" : "Send").accessibilityAddTraits(.isButton)
                    .disabled(sendDisabled)
            }.padding((ShellLayout.composerMinHeight - ShellLayout.controlSize) / 2)
                .frame(minHeight: ShellLayout.composerMinHeight)
                .background(app.pal.elevFill, in: RoundedRectangle(cornerRadius: ShellLayout.popoverRadius))
            if let reason = registry.unavailableReason { Text(reason).font(ShellType.caption).foregroundStyle(app.pal.ink3).fixedSize(horizontal: false, vertical: true) }
        }.padding(ShellLayout.windowGap * 1.5)
            .dropDestination(for: DroppedText.self) { drops, _ in
                let sources = app.noteDropSources(drops.map(\.value))
                for source in sources { attachments.removeAll { $0.id == source.id }; attachments.append(source) }
                if !sources.isEmpty { focused = true }
                return !sources.isEmpty
            }
    }
    /// The composer's leading `@` and `/` buttons.
    private func composerGlyph(_ glyph: String, font: Font, label: String, help: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(font).foregroundStyle(app.pal.ink3)
                .frame(width: ShellLayout.controlSize, height: ShellLayout.controlSize).contentShape(Rectangle())
        }.buttonStyle(ShellButtonStyle()).help(help).accessibilityLabel(label)
            .accessibilityIdentifier(id).accessibilityAddTraits(.isButton)
    }
    private func removeMention() { if let range = query.range(of: "@", options: .backwards) { query = String(query[..<range.lowerBound]) } }
    private func send() {
        guard !capturing, registry.unavailableReason == nil, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let store else { return }
        let text = query
        query = ""
        Task {
            if let invocation = ChatSkill.parse(text, skills: skills) {
                contexts = Set(invocation.skill.contexts); await collect()
            }
            controller.send(text, sources: attachments, app: app, store: store)
        }
    }
    private func reset() async {
        app.citations.clear()
        controller.select(ChatSession(spaceID: app.activeSpaceID, profileID: app.activeSpace.profileID ?? Profile.defaultID))
        scopeToken = UUID(); attachments = []; contexts = !app.attachedSources.isEmpty ? [] : (scopedNodes == nil ? [.currentTab] : [.thread])
        await collect()
    }
    private func attach(_ tab: Tab) async {
        guard app.aiTabAllowed(tab), let url = tab.url else { return }
        let token = scopeToken, space = app.activeSpaceID
        let text = await tab.engine.captureSnapshotText()
        guard !Task.isCancelled, token == scopeToken, space == app.activeSpaceID, tab.url == url, app.aiTabAllowed(tab) else { return }
        let source = KnowledgeSource(id: tab.id, title: tab.displayTitle, url: url.absoluteString, text: text, kind: "Tab")
        attachments.removeAll { $0.id == source.id }; attachments.append(source)
    }
    private func collect() async {
        let token = UUID(); captureToken = token; capturing = true
        attachments = []
        if contexts.contains(.currentTab), let tab = app.activeTab { await attach(tab) }
        if contexts.contains(.allTabs) { for tab in app.tabs.filter({ $0.spaceID == app.activeSpaceID }) { await attach(tab) } }
        guard captureToken == token else { return }
        var nodes: [GraphNode] = []
        if contexts.contains(.history) { nodes += app.graph.search("", spaceID: app.activeSpaceID, limit: 100) }
        if contexts.contains(.thread) {
            nodes += scopedNodes ?? app.graph.threads(spaceID: app.activeSpaceID).first { $0.id == app.activeTab?.currentThreadID }?.nodes ?? []
        }
        let notes = contexts.contains(.vault) ? app.vault.annotations.filter { $0.spaceID == app.activeSpaceID } : []
        attachments += KnowledgeAssistant.retrieve(query: "", nodes: nodes, annotations: notes, limit: 100).filter { app.aiSourceAllowed($0) }
        attachments += app.attachedSources.filter { app.aiSourceAllowed($0) }
        var seen = Set<UUID>(); attachments = attachments.filter { seen.insert($0.id).inserted }
        app.attachedSources = []; capturing = false
    }
    private func open(_ source: KnowledgeSource) { if let url = URL(string: source.url), ["http", "https"].contains(url.scheme ?? "") { app.openTab(url: url, parent: nil, activate: true) } }
}

/// One attached source in the strip: favicon (a quotation glyph for Vault notes) and a short
/// title on a 24pt `elevFill` chip; the remove `xmark` appears on hover. Hovering a note
/// shows its quote in a `NoteQuoteCard`.
private struct SourceChip: View {
    @EnvironmentObject var app: AppState
    let source: KnowledgeSource
    let remove: () -> Void
    @State private var hovering = false
    @State private var previewing = false
    var body: some View {
        HStack(spacing: 4) {
            if source.isNote {
                NoteGlyph()
            } else {
                Favicon(host: URL(string: source.url)?.host, size: ShellLayout.iconSize)
            }
            Text(source.title).lineLimit(1).frame(maxWidth: 180)
            // Space is kept for the glyph so the chip does not resize under the pointer.
            Button(action: remove) { Image(systemName: "xmark").font(ShellType.glyphMini).foregroundStyle(hovering ? app.pal.ink3 : Color.clear) }
                .buttonStyle(.plain).allowsHitTesting(hovering)
                .accessibilityIdentifier("chat.remove.\(source.id)")
                .accessibilityLabel("Remove \(source.title)").accessibilityAddTraits(.isButton)
        }.font(ShellType.secondary).foregroundStyle(app.pal.ink2)
            .padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.chipHeight)
            .background(app.pal.elevFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .onHover { hovering = $0; if source.isNote { previewing = $0 } }
            .popover(isPresented: $previewing, arrowEdge: .bottom) { NoteQuoteCard(title: source.title, quote: source.text).environmentObject(app) }
            .help(source.isNote ? "" : source.title)
    }
}

/// The 12pt quotation glyph that stands in for a favicon on Vault-note chips.
private struct NoteGlyph: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Image(systemName: "quote.opening").font(ShellType.glyphSmall).foregroundStyle(app.pal.ink3)
            .frame(width: ShellLayout.iconSize, height: ShellLayout.iconSize)
    }
}

/// A Vault note's quote on hover, laid out like `TabPreview`: the quoted text in the serif
/// `quote` face beside the `quoteRule`, the note's title under it in `caption` `ink3`.
struct NoteQuoteCard: View {
    @EnvironmentObject var app: AppState
    let title: String
    let quote: String
    /// Lines of the quote shown before it is cut.
    static let lineLimit = 8
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: ShellLayout.rowInsetLeading) {
                Rectangle().fill(app.pal.quoteRule).frame(width: ShellLayout.hairline)
                Text(quote.trimmingCharacters(in: .whitespacesAndNewlines)).font(ShellType.quote).lineSpacing(ShellType.rowLineSpacing)
                    .foregroundStyle(app.pal.ink).lineLimit(Self.lineLimit).fixedSize(horizontal: false, vertical: true)
            }.fixedSize(horizontal: false, vertical: true)
            Text(title).font(ShellType.caption).foregroundStyle(app.pal.ink3).lineLimit(2)
        }.padding(12).frame(width: 260, alignment: .leading).background(app.pal.elev)
            .accessibilityElement(children: .combine).accessibilityIdentifier("chat.noteQuote")
    }
}

/// A citation chip, inline in the answer (the index alone) or in the sources line under it
/// (the source's indices, favicon and title: one entry per source, `siblings` its citations).
/// Linked chips drive the page's marks; other-tab chips preview and switch; note chips show
/// their quote; the rest open their source.
struct CitationChip: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var linker: CitationLinker
    let citation: ChatCitation
    let message: ChatMessage
    let citations: [ChatCitation]
    /// The sources-line entry's citations; empty for an inline chip.
    var siblings: [ChatCitation] = []
    @State private var previewing = false
    private var full: Bool { !siblings.isEmpty }
    private var source: KnowledgeSource? {
        let sources = message.sources ?? []
        return sources.indices.contains(citation.sourceNumber - 1) ? sources[citation.sourceNumber - 1] : nil
    }
    private func link(_ citation: ChatCitation) -> CitationChipLink {
        CitationLinker.chipLink(citation, source: source, linkedIDs: linker.messageID == message.id ? linker.linkedIDs : [], linkedTabID: linker.tabID,
                                activeTab: app.activeTab.map { ($0.id, $0.url) }, openTabIDs: Set(app.tabs.map(\.id)))
    }
    private func active(_ citation: ChatCitation) -> Bool { linker.messageID == message.id && linker.activeID == citation.citationID }
    var body: some View {
        let link = link(citation)
        Button { click(link) } label: {
            if full {
                HStack(spacing: 4) {
                    HStack(spacing: 0) {
                        ForEach(siblings) { sibling in CitationIndexLabel(index: sibling.index, active: active(sibling), linked: self.link(sibling) != .unlinkedPage) }
                    }
                    if source?.isNote == true { NoteGlyph() }
                    else { Favicon(host: source.flatMap { URL(string: $0.url)?.host }, size: ShellLayout.iconSize) }
                    Text(source?.title ?? "Source").lineLimit(1).frame(maxWidth: 160, alignment: .leading)
                }.font(ShellType.secondary).foregroundStyle(app.pal.ink2)
                    .padding(.trailing, ShellLayout.rowInsetLeading).frame(height: ShellLayout.chipHeight)
                    .background(siblings.contains(where: active) ? app.pal.accentSoft : app.pal.elevFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                    .contentShape(Rectangle())
            } else {
                CitationIndexLabel(index: citation.index, active: active(citation), linked: link != .unlinkedPage).contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
            .onHover { hover($0, link) }
            .popover(isPresented: $previewing, arrowEdge: .bottom) {
                if case .tab(let id) = link, let tab = app.tabs.first(where: { $0.id == id }) { TabPreview(tab: tab).environmentObject(app) }
                else if let source, source.isNote { NoteQuoteCard(title: source.title, quote: citation.passage ?? source.text).environmentObject(app) }
            }
            .help(help(link))
            .accessibilityIdentifier("chat.citation.\(message.id).\(citation.index)\(full ? ".source" : "")")
            .accessibilityLabel(full ? "Source \(siblings.map { String($0.index) }.joined(separator: ", ")): \(source?.title ?? "unknown")" : "Source \(citation.index): \(source?.title ?? "unknown")")
            .accessibilityAddTraits(.isButton)
    }
    private func help(_ link: CitationChipLink) -> String {
        link.help(title: source?.title, note: source?.isNote == true, behind: linker.messageID == message.id && linker.behindIDs.contains(citation.citationID))
    }
    private func hover(_ hovering: Bool, _ link: CitationChipLink) {
        switch link {
        case .page: linker.hoverChip(hovering ? citation.citationID : nil)
        case .tab: previewing = hovering
        case .source: if source?.isNote == true { previewing = hovering }
        case .unlinkedPage: break
        }
    }
    private func click(_ link: CitationChipLink) {
        switch link {
        case .page: Task { await linker.focus(citation.citationID) }
        case .unlinkedPage: break
        case .tab(let id):
            previewing = false
            app.activate(id)
            guard let tab = app.tabs.first(where: { $0.id == id }) else { return }
            let message = message, citations = citations, target = citation.citationID
            Task {
                let found = await ChatView.link(message, citations: citations, in: tab, app: app)
                if found.contains(target) { await app.citations.focus(target) }
            }
        case .source:
            previewing = false
            if let source, let url = URL(string: source.url), ["http", "https"].contains(url.scheme ?? "") { app.openTab(url: url, parent: nil, activate: true) }
        }
    }
}
