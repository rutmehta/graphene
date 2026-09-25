import SwiftUI
import AppKit

struct LedgerView: View {
    @EnvironmentObject var app: AppState
    @State private var filter = ""
    /// Map (the tree) or List (scanning); graphene-language.md §5.2. Threads opens on the Map.
    @State private var map = true
    @StateObject private var summary = ThreadSummaryModel()
    private var threads: [KnowledgeGraph.Thread] {
        app.currentThreads.filter { filter.isEmpty || ($0.title + " " + $0.hosts.joined(separator: " ") + " " + $0.nodes.map(\.snippet).joined(separator: " ")).localizedCaseInsensitiveContains(filter) }
    }
    /// The thread the list selected; nil shows every thread in the space (All threads).
    private var selected: KnowledgeGraph.Thread? { threads.first { $0.id == app.selectedThreadID } }
    var body: some View {
        VStack(spacing: 0) {
            LibraryBar(title: "Threads", detail: app.currentThreads.isEmpty ? nil : "\(app.currentThreads.count)") {
                if !app.currentThreads.isEmpty {
                    LibraryBarButton("List", system: "list.bullet.indent", selected: !map, showsTitle: true) { map = false }
                    LibraryBarButton("Map", system: "point.3.connected.trianglepath.dotted", selected: map, showsTitle: true) { map = true }
                }
                if let selected {
                    LibraryBarButton(summary.working ? "Stop summary" : "Summarize thread", system: summary.working ? "stop.circle" : "text.append") {
                        summary.toggle(selected, app: app)
                    }
                    LibraryBarButton("Ask this thread", system: "sparkle") { app.askThread(selected) }
                    LibraryBarButton("Export thread as Markdown", system: "square.and.arrow.up") { ThreadDetail.export(selected, app: app) }
                }
            }
            content
        }.foregroundStyle(app.pal.ink).background(app.pal.pageBg)
            .onChange(of: selected?.id, initial: true) { _, _ in summary.load(selected, app: app) }
            .onChange(of: app.settings.ai) { _, _ in summary.stop() }
            .onDisappear { summary.stop() }
    }
    @ViewBuilder private var content: some View {
        if let error = app.graph.errorText, app.currentThreads.isEmpty {
            SurfaceState(symbol: "exclamationmark.triangle", title: "Threads unavailable", detail: error) {
                Button("Browse") { app.show(.web) }.buttonStyle(.bordered)
            }
        } else if app.currentThreads.isEmpty {
            SurfaceState(line: "Open a page and Graphene will keep the thread.", symbol: "point.3.connected.trianglepath.dotted")
        } else {
            // Panes are separated by `sectionGap` and the shared page background, never a rule.
            HStack(spacing: ShellLayout.sectionGap) {
                VStack(alignment: .leading, spacing: 0) {
                    FilterField(placeholder: "Search threads", text: $filter).padding(ShellLayout.windowGap)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            AllThreadsRow(count: threads.count, selected: selected == nil) { app.selectedThreadID = nil }
                            ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                                if index == 0 || !Calendar.current.isDate(thread.start, inSameDayAs: threads[index - 1].start) {
                                    Text(thread.start.formatted(date: .abbreviated, time: .omitted)).font(ShellType.label).foregroundStyle(app.pal.ink3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, ShellLayout.rowInsetLeading).padding(.top, ShellLayout.sectionGap).padding(.bottom, ShellLayout.iconBackingInset * 2)
                                }
                                ThreadRow(thread: thread, selected: selected?.id == thread.id) { app.selectedThreadID = thread.id }
                            }
                            if threads.isEmpty { Text("No matching threads").font(ShellType.secondary).foregroundStyle(app.pal.ink3).padding(ShellLayout.newTabGap) }
                        }.padding(.horizontal, ShellLayout.windowGap)
                    }
                    Label("Saved on this Mac", systemImage: "internaldrive").font(ShellType.caption).foregroundStyle(app.pal.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ShellLayout.windowGap + ShellLayout.rowInsetLeading).frame(height: ShellLayout.footerHeight)
                }.frame(width: ThreadPanes.listWidth)
                    .focusable()
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.return) { if let selected { app.resumeThread(selected) }; return .handled }
                if let selected { ThreadDetail(thread: selected, map: map, summary: summary).id(selected.id) }
                else { ForestDetail(threads: threads, map: map) }
            }
        }
    }
}

extension LedgerView {
    /// Up and down move through All threads (nil) and then each thread in the list.
    private func moveSelection(_ direction: Int) {
        let order: [UUID?] = [nil] + threads.map(\.id)
        let index = order.firstIndex { $0 == selected?.id } ?? 0
        app.selectedThreadID = order[min(order.count - 1, max(0, index + direction))]
    }
}

/// The top of the thread list: every thread in the space on one map (graphene-language.md §5.2).
private struct AllThreadsRow: View {
    let count: Int
    let selected: Bool
    let action: () -> Void
    @EnvironmentObject var app: AppState
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: ShellLayout.iconGap) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(ShellType.glyphSmall).foregroundStyle(app.pal.ink3)
                    .frame(width: ShellLayout.iconSize)
                Text("All threads").font(selected ? ShellType.rowSelected : ShellType.row).foregroundStyle(app.pal.ink)
                Spacer(minLength: ShellLayout.iconBackingInset * 2)
                Text("\(count)").font(ShellType.caption).monospacedDigit().foregroundStyle(app.pal.ink3)
            }
            .padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.rowHeight).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected || hovering ? app.pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .accessibilityIdentifier("threads.all")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// One thread in the list: `row` title (`rowSelected` when selected), `caption` metadata.
private struct ThreadRow: View {
    let thread: KnowledgeGraph.Thread
    let selected: Bool
    let action: () -> Void
    @EnvironmentObject var app: AppState
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ShellLayout.iconBackingInset * 2) {
                Text(thread.title).font(selected ? ShellType.rowSelected : ShellType.row).foregroundStyle(app.pal.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: ThreadLayout.hostGap) {
                    HStack(spacing: -3) { ForEach(Array(thread.hosts.prefix(4)), id: \.self) { Favicon(host: $0, size: ShellLayout.iconSize) } }
                    Text(thread.hosts.prefix(2).joined(separator: " · ")).foregroundStyle(app.pal.ink2).lineLimit(1)
                    Spacer(minLength: ShellLayout.iconBackingInset * 2)
                    Text("\(thread.nodes.count) \(thread.nodes.count == 1 ? "page" : "pages") · \(max(1, Int(thread.end.timeIntervalSince(thread.start) / 60))) min")
                        .foregroundStyle(app.pal.ink3).lineLimit(1)
                }.font(ShellType.caption)
            }
            .padding(.horizontal, ShellLayout.rowInsetLeading).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected || hovering ? app.pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The selected thread's one-line header strip, `threadHeaderHeight` tall directly under the
/// library bar: the title in `title`, "4 pages · 1 site · 2 notes" in `secondary` `ink2`, and
/// Continue browsing at the trailing edge.
struct ThreadHeaderStrip: View {
    let thread: KnowledgeGraph.Thread
    let notes: Int
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack(spacing: ShellLayout.sectionGap) {
            Text(thread.title).font(ShellType.title).foregroundStyle(app.pal.ink).lineLimit(1).layoutPriority(1)
            Text(ThreadPanes.counts(pages: thread.nodes.count, sites: thread.hosts.count, notes: notes))
                .font(ShellType.secondary).foregroundStyle(app.pal.ink2).lineLimit(1)
            Spacer(minLength: 0)
            Button { app.resumeThread(thread) } label: { Label("Continue browsing", systemImage: "arrow.up.right") }
                .buttonStyle(.bordered).controlSize(.small).font(ShellType.secondary).fixedSize()
        }
        .padding(.horizontal, ShellLayout.newTabGap)
        .frame(height: ThreadPanes.headerHeight)
        .accessibilityElement(children: .contain).accessibilityIdentifier("thread.header")
    }
}

/// The selected thread: the header strip, the map (or the list) under it with the whole width,
/// and the streamed summary in a `summaryWidth` column on the right once there is one
/// (graphene-language.md §5.2).
private struct ThreadDetail: View {
    let thread: KnowledgeGraph.Thread
    let map: Bool
    @ObservedObject var summary: ThreadSummaryModel
    @EnvironmentObject var app: AppState
    /// The node a summary citation chip is hovering.
    @State private var citedID: UUID?
    private var notes: [Annotation] { Self.notes(for: thread, app: app) }
    static func notes(for thread: KnowledgeGraph.Thread, app: AppState) -> [Annotation] {
        let urls = Set(thread.nodes.map { KnowledgeGraph.canonicalURL($0.url) })
        return app.vault.annotations.filter { urls.contains(KnowledgeGraph.canonicalURL($0.url)) }
    }
    var body: some View {
        let layout = app.threadLayout(thread)
        let notes = notes
        let noted = Set(notes.map { KnowledgeGraph.canonicalURL($0.url) })
        let current = app.activeTab?.currentNodeID.flatMap { layout.node($0) == nil ? nil : $0 }
        let picked = app.selectedThreadNodeID.flatMap { layout.node($0) == nil ? nil : $0 }
        let state = ThreadNodeState(layout: layout, current: current, selected: picked ?? current, cited: citedID, noted: noted)
        VStack(alignment: .leading, spacing: 0) {
            ThreadHeaderStrip(thread: thread, notes: notes.count)
            HStack(alignment: .top, spacing: ShellLayout.sectionGap) {
                Group {
                    if map {
                        ThreadMap(thread: thread, state: state)
                    } else {
                        ThreadList(thread: thread, state: state, notes: notes)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.return) { app.openSelectedThreadNode(in: thread) ? .handled : .ignored }
                if summary.showsColumn {
                    ScrollView {
                        ThreadSummaryView(model: summary, thread: thread, nodeIDs: Set(layout.nodes.map(\.id)), citedNodeID: $citedID)
                            .padding(.horizontal, ShellLayout.newTabGap).padding(.bottom, ShellLayout.newTabGap)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(width: ThreadLayout.summaryWidth)
                    .transition(.opacity)
                }
            }
        }
    }
    static func export(_ thread: KnowledgeGraph.Thread, app: AppState) {
        let notes = notes(for: thread, app: app)
        var markdown = "# \(thread.title)\n\n\(thread.start.formatted(date: .long, time: .shortened))\n\n"
        for node in thread.nodes {
            markdown += "## [\(node.title)](\(node.url))\n\n\(node.snippet)\n\n"
            for note in notes where KnowledgeGraph.canonicalURL(note.url) == KnowledgeGraph.canonicalURL(node.url) {
                markdown += "> \(note.text)\n\n\(note.note)\n\n"
            }
        }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Graphene thread.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try markdown.write(to: url, atomically: true, encoding: .utf8); app.notify("Thread exported") }
        catch { app.notify("Couldn’t export: \(error.localizedDescription)") }
    }
}

/// The node tooltip: what a click, a double-click and ⌘-double-click do.
private enum ThreadNodeHelp {
    static let text = "Click to select · double-click to open · ⌘-double-click to open as a child tab"
}

/// What the map and the list need to draw a node.
private struct ThreadNodeState {
    let layout: ThreadLayout
    /// The current tab's node, if it is in this thread.
    let current: UUID?
    /// The node whose ancestor path is active: the clicked node, else the current one.
    let selected: UUID?
    /// The node a summary citation is pointing at.
    let cited: UUID?
    /// Canonical URLs of pages with a Vault note.
    let noted: Set<String>
    @MainActor func hasNote(_ page: GraphNode) -> Bool { noted.contains(KnowledgeGraph.canonicalURL(page.url)) }
}

/// A click on a node: one click selects it, a double-click opens it in the current tab, a
/// ⌘-double-click opens it as a child of the current tab (`ThreadNodeClick`). Only mouse
/// events carry a click count; anything else (an accessibility press) is a single click.
@MainActor private func clickNode(_ id: UUID, in thread: KnowledgeGraph.Thread, app: AppState) {
    let event = NSApp.currentEvent
    let mouse: Set<NSEvent.EventType> = [.leftMouseDown, .leftMouseUp]
    let clicks = event.map { mouse.contains($0.type) ? $0.clickCount : 1 } ?? 1
    app.clickThreadNode(id, in: thread, clickCount: clicks, command: event?.modifierFlags.contains(.command) == true)
}

/// The same actions as the hover card, for keyboard and pointer users alike.
private struct ThreadNodeMenu: View {
    let id: UUID
    let thread: KnowledgeGraph.Thread
    @EnvironmentObject var app: AppState
    var body: some View {
        Button("Open") { app.openThreadNode(id, in: thread, asChild: false) }
        Button("Open as Child Tab") { app.openThreadNode(id, in: thread, asChild: true) }.disabled(app.activeTab == nil)
        Button("Resume from Here") { app.resumeThread(from: id, in: thread) }
        Button("Note") { app.openThreadNote(id, in: thread) }
    }
}

/// A node: favicon 16 in a `threadNodeSize` slot (with the accent dot when the page has a Vault
/// note), the title in `row` `ink2` truncated at 26 characters, the host in `caption` `ink3`.
/// The selected node (the clicked one, else the current tab's) has a filled background and its
/// title in `ink`, with no outline: `rowSelected` is translucent white, which vanishes on the
/// white page card, so it is `tileFill`. Hover and a cited node are `rowHover`.
private struct ThreadNodeLabel: View {
    let page: GraphNode
    let selected: Bool
    let highlighted: Bool
    let noted: Bool
    @EnvironmentObject var app: AppState
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellLayout.rowRadius)
        HStack(spacing: 0) {
            Favicon(host: page.host, size: ShellLayout.iconSize, url: URL(string: page.url))
                .overlay(alignment: .bottomTrailing) {
                    if noted {
                        Circle().fill(app.pal.accent).frame(width: ShellLayout.statusDot, height: ShellLayout.statusDot)
                            .offset(x: ShellLayout.statusDot / 2, y: ShellLayout.statusDot / 2)
                    }
                }
                .frame(width: ShellLayout.threadNodeSize, height: ShellLayout.threadNodeSize)
            Text(ThreadLayout.truncatedTitle(page.title.isEmpty ? page.host : page.title)).font(ShellType.row)
                .foregroundStyle(selected ? app.pal.ink : app.pal.ink2).lineLimit(1).fixedSize()
                .padding(.leading, ShellLayout.iconGap)
            Text(page.host).font(ShellType.caption).foregroundStyle(app.pal.ink3).lineLimit(1).fixedSize()
                .padding(.leading, ThreadLayout.hostGap)
        }
        .padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.rowHeight)
        .background(selected ? app.pal.tileFill : (highlighted ? app.pal.rowHover : .clear), in: shape)
        .contentShape(shape)
    }
}

/// A connector path drawn from parent to child: `progress` trims it from its start.
private struct ThreadConnectorShape: Shape {
    let path: Path
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path { path.trimmedPath(from: 0, to: progress) }
}

/// The tree (graphene-language.md §5.2): starts directly under the header strip, scrolls in
/// both axes inside its column and never zooms. Content smaller than the column is pinned to the
/// top leading corner rather than centred.
private struct ThreadMap: View {
    let thread: KnowledgeGraph.Thread
    let state: ThreadNodeState
    var body: some View {
        GeometryReader { viewport in
            ScrollView([.horizontal, .vertical]) {
                ThreadTree(thread: thread, state: state, bottomRoom: ThreadTree.cardRoom)
                    .padding(.horizontal, ThreadTree.inset).padding(.bottom, ThreadTree.inset)
                    .frame(minWidth: viewport.size.width, minHeight: viewport.size.height, alignment: .topLeading)
            }
            .defaultScrollAnchor(.topLeading)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Thread map")
    }
}

/// One thread's tree, drawn at its layout's size: connectors, the start and query labels, the
/// nodes and the hover card. The Thread map shows one; the space-wide map stacks one per thread.
private struct ThreadTree: View {
    let thread: KnowledgeGraph.Thread
    let state: ThreadNodeState
    /// Room below the last row; the hover card may draw past it (over the next tree).
    var bottomRoom: CGFloat = 0
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var hoveredID: UUID?
    @State private var cardID: UUID?
    @State private var cardHovered = false

    /// Room around the grid, and to the right of the deepest column for its labels.
    static let inset = ShellLayout.newTabGap
    static let labelRoom = ShellLayout.threadColumn * 2
    /// Below the last row of a single map, so the last node's hover card is not clipped.
    static let cardRoom = ShellLayout.threadRowPitch * 4
    /// How long the card stays after the pointer leaves the node, so it can move onto the card.
    private static let cardGrace: Duration = .milliseconds(250)

    var body: some View {
        let layout = state.layout
        let pages = Dictionary(thread.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let active = layout.activeChildren(selected: state.selected)
        ZStack(alignment: .topLeading) {
            ForEach(layout.connectors) { connector in
                if !reduceMotion || appeared {
                    ThreadConnectorShape(path: Path(connector.path()), progress: reduceMotion || appeared ? 1 : 0)
                        .stroke(app.pal.threadLine, lineWidth: ShellLayout.hairline)
                        .animation(reduceMotion ? nil : .easeOut(duration: ThreadLayout.connectorDraw)
                            .delay(ThreadLayout.fadeDelay(column: connector.parentColumn)), value: appeared)
                        .transition(fade(column: 0))
                }
            }
            ForEach(layout.connectors) { connector in
                if appeared, let child = active[connector.parentID] {
                    ThreadConnectorShape(path: Path(connector.path(to: [child])), progress: 1)
                        .stroke(app.pal.threadLineActive, lineWidth: ShellLayout.hairline)
                        .transition(.opacity.animation(.easeOut(duration: ThreadLayout.recolour)))
                        .id("\(connector.parentID)-\(child)")
                }
            }
            ForEach(layout.headers) { header in
                if appeared {
                    HStack(spacing: ThreadLayout.hostGap) {
                        if let start = header.start { Text(ThreadLayout.startLabel(start)).font(ShellType.caption).foregroundStyle(app.pal.ink3) }
                        if let query = header.query { Text("“\(query)”").font(ShellType.label).foregroundStyle(app.pal.ink3).lineLimit(1) }
                    }
                    .fixedSize()
                    .frame(height: ShellLayout.threadRowPitch, alignment: .leading)
                    .offset(y: CGFloat(header.row) * ShellLayout.threadRowPitch)
                    .transition(fade(column: 0))
                }
            }
            ForEach(layout.nodes) { node in
                if appeared, let page = pages[node.id] {
                    Button { clickNode(node.id, in: thread, app: app) } label: {
                        ThreadNodeLabel(page: page, selected: state.selected == node.id,
                                        highlighted: hoveredID == node.id || state.cited == node.id, noted: state.hasNote(page))
                    }
                    .buttonStyle(.plain)
                    .onHover { hover(node.id, $0) }
                    .contextMenu { ThreadNodeMenu(id: node.id, thread: thread) }
                    .help(ThreadNodeHelp.text)
                    .accessibilityAction(named: "Open") { app.openThreadNode(node.id, in: thread, asChild: false) }
                    .accessibilityLabel("\(page.title), \(page.host)")
                    .accessibilityIdentifier("thread.node.\(node.id)")
                    .accessibilityAddTraits(state.selected == node.id ? [.isSelected] : [])
                    .offset(x: node.origin.x - ShellLayout.rowInsetLeading,
                            y: node.origin.y + (ShellLayout.threadRowPitch - ShellLayout.rowHeight) / 2)
                    .transition(fade(column: node.column))
                }
            }
            if let id = cardID, let node = layout.node(id), let page = pages[id] {
                ThreadHoverCard(page: page, thread: thread) { cardHovered = $0; if !$0 { scheduleHide(id) } }
                    .offset(x: node.origin.x - ShellLayout.rowInsetLeading,
                            y: node.origin.y + (ShellLayout.threadRowPitch + ShellLayout.rowHeight) / 2 + ShellLayout.iconBackingInset)
                    .transition(.opacity.animation(Motion.hover.reduced(reduceMotion)))
                    .zIndex(1)
            }
        }
        .frame(width: layout.size.width + Self.labelRoom, height: layout.size.height + bottomRoom, alignment: .topLeading)
        .onAppear { appeared = true }
    }

    /// Nodes fade in by depth: 40ms per column, at most 200ms; Reduce Motion drops the stagger.
    private func fade(column: Int) -> AnyTransition {
        let delay = reduceMotion ? 0 : ThreadLayout.fadeDelay(column: column)
        return .opacity.animation(.easeOut(duration: ThreadLayout.fadeDuration).delay(delay))
    }
    private func hover(_ id: UUID, _ inside: Bool) {
        if inside { hoveredID = id; cardID = id; return }
        if hoveredID == id { hoveredID = nil }
        scheduleHide(id)
    }
    private func scheduleHide(_ id: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: Self.cardGrace)
            if hoveredID != id, !cardHovered, cardID == id { cardID = nil }
        }
    }
}

/// Every thread in the space (graphene-language.md §5.2), shown when the list selects All
/// threads: a header strip, then one tree per thread (or its list rows) stacked with
/// `sectionGap`, newest first like the list, each under its title and with its start label.
/// Clicking a title narrows the map to that thread.
private struct ForestDetail: View {
    let threads: [KnowledgeGraph.Thread]
    let map: Bool
    @EnvironmentObject var app: AppState
    var body: some View {
        let forest = ThreadForest(threads: threads, visits: app.graph.visits)
        let noted = Set(app.vault.annotations.map { KnowledgeGraph.canonicalURL($0.url) })
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ShellLayout.sectionGap) {
                Text("All threads").font(ShellType.title).foregroundStyle(app.pal.ink).lineLimit(1)
                Text(ThreadPanes.forestCounts(threads: forest.trees.count, pages: forest.pageCount))
                    .font(ShellType.secondary).foregroundStyle(app.pal.ink2).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ShellLayout.newTabGap)
            .frame(height: ThreadPanes.headerHeight)
            .accessibilityElement(children: .contain).accessibilityIdentifier("threads.all.header")
            GeometryReader { viewport in
                ScrollView(map ? [.horizontal, .vertical] : [.vertical]) {
                    VStack(alignment: .leading, spacing: ShellLayout.sectionGap) {
                        ForEach(Array(forest.trees.enumerated()), id: \.element.id) { index, tree in
                            VStack(alignment: .leading, spacing: 0) {
                                ForestTitle(thread: tree.thread)
                                if map { ThreadTree(thread: tree.thread, state: state(for: tree.layout, noted: noted)) }
                                else { ThreadListRows(thread: tree.thread, state: state(for: tree.layout, noted: noted)) }
                            }
                            // An earlier tree's hover card draws over the tree below it.
                            .zIndex(Double(forest.trees.count - index))
                        }
                    }
                    .padding(.horizontal, map ? ThreadTree.inset : ShellLayout.newTabGap - ShellLayout.rowInsetLeading)
                    .padding(.bottom, ThreadTree.cardRoom)
                    .frame(minWidth: viewport.size.width, minHeight: viewport.size.height, alignment: .topLeading)
                }
                .defaultScrollAnchor(.topLeading)
            }
            .accessibilityElement(children: .contain).accessibilityLabel(map ? "All threads map" : "All threads list")
        }
    }
    private func state(for layout: ThreadLayout, noted: Set<String>) -> ThreadNodeState {
        let current = app.activeTab?.currentNodeID.flatMap { layout.node($0) == nil ? nil : $0 }
        let picked = app.selectedThreadNodeID.flatMap { layout.node($0) == nil ? nil : $0 }
        return ThreadNodeState(layout: layout, current: current, selected: picked ?? current, cited: nil, noted: noted)
    }
}

/// A thread's title over its tree in the space-wide map; a click narrows the map to the thread.
private struct ForestTitle: View {
    let thread: KnowledgeGraph.Thread
    @EnvironmentObject var app: AppState
    @State private var hovering = false
    var body: some View {
        Button { app.selectedThreadID = thread.id } label: {
            Text(thread.title).font(ShellType.rowSelected).foregroundStyle(hovering ? app.pal.ink : app.pal.ink2).lineLimit(1)
                .frame(height: ShellLayout.rowHeight).contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .help("Show this thread")
        .accessibilityIdentifier("threads.forest.\(thread.id)")
    }
}

/// The node hover card: `elev`, `popoverRadius`, hairline, `pageShadow`, 320 wide, with the page
/// snippet in `quoteSmall` and "Open · Resume from here · Note" in `label`.
private struct ThreadHoverCard: View {
    let page: GraphNode
    let thread: KnowledgeGraph.Thread
    let hovering: (Bool) -> Void
    @EnvironmentObject var app: AppState
    private static let snippetLength = 420
    private var snippet: String {
        String(page.snippet.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(Self.snippetLength))
    }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellLayout.popoverRadius)
        VStack(alignment: .leading, spacing: ShellLayout.sectionGap) {
            if snippet.isEmpty {
                Text(page.url).font(ShellType.caption).foregroundStyle(app.pal.ink3).lineLimit(2)
            } else {
                Text(snippet).font(ShellType.quoteSmall).foregroundStyle(app.pal.ink)
                    .lineSpacing(ShellType.lineSpacing(size: ShellType.quoteSmallSize, lineHeight: ShellType.quoteLineHeight))
                    .lineLimit(6).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: ThreadLayout.hostGap) {
                Button("Open") { app.openThreadNode(page.id, in: thread, asChild: false) }
                Text("·").foregroundStyle(app.pal.ink3)
                Button("Resume from here") { app.resumeThread(from: page.id, in: thread) }
                Text("·").foregroundStyle(app.pal.ink3)
                Button("Note") { app.openThreadNote(page.id, in: thread) }
            }.buttonStyle(.plain).font(ShellType.label).foregroundStyle(app.pal.ink2)
        }
        .padding(ShellLayout.sectionGap)
        .frame(width: ThreadLayout.hoverCardWidth, alignment: .leading)
        .background(app.pal.elev, in: shape)
        .overlay(shape.strokeBorder(app.pal.hairline, lineWidth: ShellLayout.hairline))
        .shadow(color: app.pal.pageShadow, radius: app.pal.pageShadowRadius, y: app.pal.pageShadowY)
        .onHover(perform: hovering)
        .accessibilityElement(children: .contain).accessibilityLabel("\(page.title) preview")
    }
}

/// List mode, for scanning: rows of `rowHeight` with the map's node treatment, indented by depth.
private struct ThreadList: View {
    let thread: KnowledgeGraph.Thread
    let state: ThreadNodeState
    let notes: [Annotation]
    @EnvironmentObject var app: AppState
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ThreadListRows(thread: thread, state: state)
                if !notes.isEmpty {
                    Text("Saved notes").font(ShellType.label).foregroundStyle(app.pal.ink3).padding(.top, ShellLayout.newTabGap).padding(.bottom, 6)
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(note.text.isEmpty ? note.title : note.text).font(ShellType.quote)
                                .lineSpacing(ShellType.quoteLineSpacing).textSelection(.enabled)
                            if !note.note.isEmpty { Text(note.note).font(ShellType.secondary).foregroundStyle(app.pal.ink2) }
                            Text(URL(string: note.url)?.host ?? "Saved note").font(ShellType.caption).foregroundStyle(app.pal.ink3)
                        }.padding(.vertical, 14)
                    }
                }
            }.padding(.horizontal, ShellLayout.newTabGap - ShellLayout.rowInsetLeading).padding(.bottom, ShellLayout.newTabGap)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A thread's pages as list rows, indented by depth: the List view of one thread or of each
/// thread under All threads.
private struct ThreadListRows: View {
    let thread: KnowledgeGraph.Thread
    let state: ThreadNodeState
    @EnvironmentObject var app: AppState
    @State private var hoveredID: UUID?
    var body: some View {
        let pages = Dictionary(thread.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        ForEach(state.layout.nodes) { node in
            if let page = pages[node.id] {
                Button { clickNode(node.id, in: thread, app: app) } label: {
                    ThreadNodeLabel(page: page, selected: state.selected == node.id,
                                    highlighted: hoveredID == node.id || state.cited == node.id, noted: state.hasNote(page))
                }
                .buttonStyle(.plain)
                .onHover { inside in if inside { hoveredID = node.id } else if hoveredID == node.id { hoveredID = nil } }
                .contextMenu { ThreadNodeMenu(id: node.id, thread: thread) }
                .help(page.url + "\n" + ThreadNodeHelp.text)
                .accessibilityAction(named: "Open") { app.openThreadNode(node.id, in: thread, asChild: false) }
                .accessibilityAddTraits(state.selected == node.id ? [.isSelected] : [])
                .padding(.leading, CGFloat(node.column) * ShellLayout.threadIndent)
                .frame(height: ShellLayout.rowHeight)
                .accessibilityLabel("Branch level \(node.column + 1): \(page.title)")
                .accessibilityIdentifier("thread.branch.\(node.id)")
            }
        }
    }
}

struct FilterField: View {
    @EnvironmentObject var app: AppState
    let placeholder: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: ShellLayout.rowInsetLeading) {
            Image(systemName: "magnifyingglass").font(ShellType.glyphSmall).foregroundStyle(app.pal.ink3)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(ShellType.row)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(ShellType.glyphSmall) }
                    .buttonStyle(.plain).foregroundStyle(app.pal.ink3).accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.controlSize)
            .background(app.pal.tileFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
    }
}

/// The 32pt top bar of a library surface (arc-look.md §3.7). Same geometry as the page
/// toolbar: `pageToolbarHeight` tall on `pageBg` with a bottom hairline, the view title in
/// `title` at the left and the view's own actions as `controlSize` glyphs in `ink3` at the
/// right. With the sidebar collapsed it keeps the traffic lights' reservation clear.
struct LibraryBar<Actions: View>: View {
    @EnvironmentObject var app: AppState
    let title: String
    var detail: String? = nil
    /// Library views in the page card paint `pageBg`; the archive sits on the chrome plane.
    var onCard = true
    @ViewBuilder var actions: () -> Actions
    private var leading: CGFloat {
        onCard && app.layout == .sidebar && app.sidebarCollapsed ? ShellLayout.trafficReserve : ShellLayout.windowGap + ShellLayout.rowInsetLeading
    }
    var body: some View {
        HStack(spacing: 2) {
            Text(title).font(ShellType.title).foregroundStyle(app.pal.ink).lineLimit(1)
            if let detail { Text(detail).font(ShellType.caption).monospacedDigit().foregroundStyle(app.pal.ink3).padding(.leading, 6) }
            Spacer(minLength: ShellLayout.windowGap)
            actions()
        }
        .padding(.leading, leading).padding(.trailing, ShellLayout.windowGap)
        .frame(height: ShellLayout.pageToolbarHeight)
        .background(onCard ? app.pal.pageBg : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline) }
        .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

/// A library bar action: 15pt medium glyph in `ink3` on a `controlSize` target, 25% when disabled.
/// `selected` marks the active one of a pair of mode glyphs (Threads' List and Map): `ink` on `rowHover`;
/// those two also show their titles.
struct LibraryBarButton: View {
    let title: String
    let system: String
    var selected = false
    /// Shows the title in `label` after the glyph (Threads' List and Map), not only as help.
    var showsTitle = false
    let action: () -> Void
    init(_ title: String, system: String, selected: Bool = false, showsTitle: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.system = system; self.selected = selected; self.showsTitle = showsTitle; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: system).font(ShellType.glyph).frame(width: ShellLayout.controlSize, height: ShellLayout.controlSize)
                if showsTitle { Text(title).font(ShellType.label).lineLimit(1).fixedSize().padding(.trailing, ShellLayout.rowInsetLeading) }
            }.contentShape(Rectangle())
        }.buttonStyle(LibraryGlyphStyle(selected: selected))
            .help(title).accessibilityLabel(title).accessibilityIdentifier("library.\(system).\(title)").accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// `ink3` glyph (`inkDisabled` when disabled) with `rowHover` behind it on hover or press;
/// a selected glyph is `ink` on `rowHover`.
struct LibraryGlyphStyle: ButtonStyle {
    var selected = false
    @EnvironmentObject var app: AppState
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(enabled ? (selected ? app.pal.ink : app.pal.ink3) : app.pal.inkDisabled)
            .background(enabled && (selected || hovered || configuration.isPressed) ? app.pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovered)
    }
}
