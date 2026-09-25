import SwiftUI

struct ChatView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
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
            Divider().overlay(app.pal.hairline)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        ForEach(controller.chat?.messages ?? []) { message in messageView(message) }
                        if search {
                            ForEach(results) { source in
                                Button { open(source) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(source.title).font(.system(size: 12, weight: .medium))
                                        Text(String(source.text.prefix(180))).font(.system(size: 11)).foregroundStyle(app.pal.ink2).lineLimit(3)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                                    .accessibilityIdentifier("chat.source.\(source.id)").accessibilityLabel(source.title).accessibilityAddTraits(.isButton)
                            }
                            if results.isEmpty { Text("No matching sources.").font(.system(size: 12)).foregroundStyle(app.pal.ink3) }
                        }
                        if let error = controller.error ?? store?.error { Text(error).font(.system(size: 12)).foregroundStyle(app.pal.ink2) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(16)
                }.onChange(of: controller.chat?.messages.last?.content) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            composer
        }.foregroundStyle(app.pal.ink).background(app.pal.ground).tint(app.pal.accentText)
            .frame(width: embedded ? nil : 680, height: embedded ? nil : 660)
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
            .onDisappear { controller.stop(); captureToken = UUID() }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {

                Text("Chat").font(.system(size: 13, weight: .medium))
                Spacer()
                IconButton("Past chats", system: "clock.arrow.circlepath", size: 16) { store?.reload(); history.toggle() }
                    .popover(isPresented: $history) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Chats in \(app.activeSpace.name)").font(.headline)
                            ScrollView {
                                ForEach((store?.chats ?? []).filter { $0.spaceID == app.activeSpaceID && $0.profileID == (app.activeSpace.profileID ?? Profile.defaultID) }) { chat in
                                    HStack {
                                        Button(chat.title) { controller.select(chat); attachments = chat.messages.last?.sources?.filter { app.aiSourceAllowed($0) } ?? []; history = false }.buttonStyle(.plain).lineLimit(2)
                                            .accessibilityIdentifier("chat.history.\(chat.id)").accessibilityLabel(chat.title).accessibilityAddTraits(.isButton)
                                        Spacer()
                                        Button { store?.delete(chat.id); history = false; if controller.chat?.id == chat.id { Task { await reset() } } } label: { Image(systemName: "trash") }.accessibilityLabel("Delete chat")
                                    }.padding(.vertical, 6)
                                }
                            }
                        }.padding(16).frame(width: 340, height: 300)
                    }
                IconButton("New chat", system: "square.and.pencil", size: 16) { Task { await reset() } }
                IconButton("Close chat", system: "xmark", size: 16) { if embedded { app.knowledgeSearchPresented = false } else { dismiss() } }
            }
        }.padding(.horizontal, 16).frame(height: 40)
            .help(registry.status + (registry.unavailableReason == nil ? " · Ready" : " · Unavailable"))
    }
    private var contextBar: some View {
        HStack(spacing: 6) {
            Button { contextDetails.toggle() } label: { Image(systemName: "slider.horizontal.3").frame(width: 24, height: 24) }
                .buttonStyle(ShellButtonStyle()).help("Context and source budget")
                .accessibilityIdentifier("chat.contextDetails").accessibilityLabel("Context and source budget").accessibilityAddTraits(.isButton)
                .popover(isPresented: $contextDetails) { contextOptions.frame(width: 320).padding(.top, 12).background(app.pal.elev) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(attachments) { source in
                        HStack(spacing: 5) {
                            Favicon(host: URL(string: source.url)?.host, size: 12)
                            Text(source.title).lineLimit(1).frame(maxWidth: 180)
                            Button { attachments.removeAll { $0.id == source.id } } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).accessibilityIdentifier("chat.remove.\(source.id)")
                                .accessibilityLabel("Remove \(source.title)").accessibilityAddTraits(.isButton)
                        }.font(.system(size: 10)).padding(.horizontal, 7).frame(height: 24).background(app.pal.hover, in: Capsule())
                    }
                    if attachments.isEmpty { Text("No sources").font(.system(size: 10)).foregroundStyle(app.pal.ink3) }
                }
            }
            if capturing { ProgressView().controlSize(.mini) }
        }.padding(.horizontal, 12).frame(height: 34)
            .overlay(alignment: .bottom) {
                if !budget.notices.isEmpty {
                    Button("\(budget.notices.count) source warnings") { contextDetails = true }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(app.pal.accentText)
                        .offset(y: 16).accessibilityIdentifier("chat.sourceWarnings")
                }
            }
            .padding(.bottom, budget.notices.isEmpty ? 0 : 20)
    }
    private var contextOptions: some View {
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach([ChatSkill.Context.currentTab, .thread, .vault, .history], id: \.self) { context in
                        Button(context.rawValue) {
                            if contexts.contains(context) { contexts.remove(context) } else { contexts.insert(context) }
                            Task { await collect() }
                        }.buttonStyle(.plain).font(.system(size: 10)).padding(7)
                            .background(contexts.contains(context) ? app.pal.accentSoft : app.pal.hover, in: Capsule())
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
            }.font(.system(size: 10)).foregroundStyle(app.pal.ink3)
            if !budget.notices.isEmpty {
                DisclosureGroup("\(budget.notices.count) trimmed or unreadable sources") {
                    ForEach(budget.notices, id: \.self) { Text($0).font(.system(size: 10)) }
                }.font(.system(size: 10)).foregroundStyle(app.pal.ink2)
            }
        }.padding(.horizontal, 16).padding(.bottom, 12)
    }
    private func messageView(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            if message.role == .user { Text(message.content).font(.system(size: 13)).textSelection(.enabled) }
            else {
                ChatMarkdownView(text: message.content, sources: message.sources ?? [])
                if controller.working, message.id == controller.chat?.messages.last?.id { ProgressView().controlSize(.small) }
                ForEach(Array((message.sources ?? []).enumerated()), id: \.element.id) { index, source in
                    Button("[\(index + 1)] \(source.title)") { open(source) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(app.pal.accentText).lineLimit(1)
                        .accessibilityIdentifier("chat.citation.\(message.id).\(source.id)").accessibilityLabel(source.title).accessibilityAddTraits(.isButton)
                }
                HStack {
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) }
                        .accessibilityIdentifier("chat.copy.\(message.id)").accessibilityLabel("Copy response").accessibilityAddTraits(.isButton)
                    if message.id == controller.chat?.messages.last?.id {
                        Button("Regenerate") { if let store { controller.send("", sources: attachments, app: app, store: store, regenerate: true) } }.disabled(controller.working || registry.unavailableReason != nil)
                            .accessibilityIdentifier("chat.regenerate").accessibilityLabel("Regenerate response").accessibilityAddTraits(.isButton)
                    }
                }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(app.pal.ink3)
            }
        }.padding(message.role == .user ? 12 : 0).frame(maxWidth: .infinity, alignment: .leading)
            .background(message.role == .user ? app.pal.hover : app.pal.ground, in: RoundedRectangle(cornerRadius: 10))
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
                }.font(.system(size: 12)).padding(10).background(app.pal.hover, in: RoundedRectangle(cornerRadius: 8))
            }
            if choosingSkill || (query.hasPrefix("/") && !query.contains(" ")) {
                ForEach(skills.filter { choosingSkill || $0.trigger.hasPrefix(query.lowercased()) }) { skill in
                    Button {
                        query = skill.trigger + " " + (choosingSkill ? query : "")
                        choosingSkill = false; contexts = Set(skill.contexts); Task { await collect() }
                    } label: {
                        HStack { Text(skill.trigger); Spacer(); Text(skill.contexts.map(\.rawValue).joined(separator: ", ")).foregroundStyle(app.pal.ink3) }
                    }.buttonStyle(.plain).font(.system(size: 11))
                        .accessibilityIdentifier("chat.skill.\(skill.trigger)").accessibilityLabel(skill.trigger).accessibilityAddTraits(.isButton)
                }
            }
            VStack(spacing: 8) {
                TextField("Ask a question about this page…", text: $query, axis: .vertical).textFieldStyle(.plain).lineLimit(2...5).font(.system(size: 13)).focused($focused).onSubmit { send() }.accessibilityLabel("Chat composer")
                    .accessibilityIdentifier("chat.composer")
                HStack {
                    Button { query += query.isEmpty || query.hasSuffix(" ") ? "@" : " @"; focused = true } label: {
                        Text("@").font(.system(size: 13)).frame(width: 24, height: 24)
                    }.buttonStyle(.plain).help("Attach tabs (@)").accessibilityLabel("Attach tabs")
                        .accessibilityIdentifier("chat.attach").accessibilityAddTraits(.isButton)
                    Button { choosingSkill.toggle(); focused = true } label: {
                        Text("/").font(.system(size: 15, weight: .medium)).frame(width: 24, height: 24)
                    }.buttonStyle(.plain).help("Choose a skill (/)").accessibilityLabel("Choose a skill")
                        .accessibilityIdentifier("chat.chooseSkill").accessibilityAddTraits(.isButton)
                    Button(search ? "Hide source search" : "Search sources") { search.toggle() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(app.pal.ink3)
                        .accessibilityIdentifier("chat.searchSources").accessibilityLabel(search ? "Hide source search" : "Search sources").accessibilityAddTraits(.isButton)
                    Spacer()
                    Button { query += query.isEmpty || query.hasSuffix(" ") ? "@" : " @"; focused = true } label: {
                        Image(systemName: "plus").font(.system(size: 16)).frame(width: 28, height: 28)
                    }.buttonStyle(.plain).help("Attach a tab")
                        .accessibilityIdentifier("chat.addAttachment").accessibilityLabel("Add attachment").accessibilityAddTraits(.isButton)
                    Button { if controller.working { controller.stop(); if let chat = controller.chat { store?.save(chat) } } else { send() } } label: {
                        Image(systemName: controller.working ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(app.pal.elev)
                            .frame(width: 28, height: 28).background(app.pal.accentText, in: Circle())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("chat.send").accessibilityLabel(controller.working ? "Stop" : "Send").accessibilityAddTraits(.isButton)
                        .disabled(!controller.working && (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || capturing || registry.unavailableReason != nil))
                }
            }.padding(12).background(app.pal.elev, in: RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(app.pal.hairline) }
            if let reason = registry.unavailableReason { Text(reason).font(.system(size: 10)).foregroundStyle(app.pal.ink3).fixedSize(horizontal: false, vertical: true) }
        }.padding(16)
            .dropDestination(for: String.self) { values, _ in
                let sources = app.noteDropSources(values)
                for source in sources { attachments.removeAll { $0.id == source.id }; attachments.append(source) }
                if !sources.isEmpty { focused = true }
                return !sources.isEmpty
            }
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
