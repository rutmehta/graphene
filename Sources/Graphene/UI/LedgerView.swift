import SwiftUI
import AppKit

struct LedgerView: View {
    @EnvironmentObject var app: AppState
    @State private var filter = ""
    private var threads: [KnowledgeGraph.Thread] {
        app.currentThreads.filter { filter.isEmpty || ($0.title + " " + $0.hosts.joined(separator: " ") + " " + $0.nodes.map(\.snippet).joined(separator: " ")).localizedCaseInsensitiveContains(filter) }
    }
    private var selected: KnowledgeGraph.Thread? { threads.first { $0.id == app.selectedThreadID } ?? threads.first }
    var body: some View {
        VStack(spacing: 0) {
            LibraryBar(title: "Threads", detail: app.currentThreads.isEmpty ? nil : "\(app.currentThreads.count)") {
                if let selected {
                    LibraryBarButton("Ask this thread", system: "text.bubble") { app.askThread(selected) }
                    LibraryBarButton("Export thread as Markdown", system: "square.and.arrow.up") { ThreadDetail.export(selected, app: app) }
                }
            }
            content
        }.foregroundStyle(app.pal.ink).background(app.pal.pageBg)
    }
    @ViewBuilder private var content: some View {
        if let error = app.graph.errorText, app.currentThreads.isEmpty {
            SurfaceState(symbol: "exclamationmark.triangle", title: "Threads unavailable", detail: error) {
                Button("Browse") { app.show(.web) }.buttonStyle(.bordered)
            }
        } else if app.currentThreads.isEmpty {
            SurfaceState(line: "Open a page and Graphene will keep the thread.", symbol: "point.3.connected.trianglepath.dotted")
        } else {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    FilterField(placeholder: "Search threads", text: $filter).padding(ShellLayout.windowGap)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                                if index == 0 || !Calendar.current.isDate(thread.start, inSameDayAs: threads[index - 1].start) {
                                    Text(thread.start.formatted(date: .abbreviated, time: .omitted)).font(ShellType.label).foregroundStyle(app.pal.ink3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, ShellLayout.rowInsetLeading).padding(.top, ShellLayout.sectionGap).padding(.bottom, 4)
                                }
                                ThreadRow(thread: thread, selected: selected?.id == thread.id) { app.selectedThreadID = thread.id }
                            }
                            if threads.isEmpty { Text("No matching threads").font(ShellType.secondary).foregroundStyle(app.pal.ink3).padding(24) }
                        }.padding(.horizontal, ShellLayout.windowGap)
                    }
                    Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline)
                    Label("Saved on this Mac", systemImage: "internaldrive").font(ShellType.caption).foregroundStyle(app.pal.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ShellLayout.windowGap + ShellLayout.rowInsetLeading).frame(height: ShellLayout.footerHeight)
                }.frame(width: 260)
                    .focusable()
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.return) { if let selected { app.resumeThread(selected) }; return .handled }
                Rectangle().fill(app.pal.hairline).frame(width: ShellLayout.hairline)
                if let selected { ThreadDetail(thread: selected).id(selected.id) }
                else { Color.clear }
            }
        }
    }
}

extension LedgerView {
    private func moveSelection(_ direction: Int) {
        guard !threads.isEmpty else { return }
        let index = threads.firstIndex { $0.id == selected?.id } ?? 0
        app.selectedThreadID = threads[min(threads.count - 1, max(0, index + direction))].id
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
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.title).font(selected ? ShellType.rowSelected : ShellType.row).foregroundStyle(app.pal.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    HStack(spacing: -3) { ForEach(Array(thread.hosts.prefix(4)), id: \.self) { Favicon(host: $0, size: ShellLayout.iconSize) } }
                    Text(thread.hosts.prefix(2).joined(separator: " · ")).foregroundStyle(app.pal.ink2).lineLimit(1)
                    Spacer(minLength: 4)
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

private struct ThreadDetail: View {
    let thread: KnowledgeGraph.Thread
    @EnvironmentObject var app: AppState
    @State private var map = false
    private var branches: [ThreadBranch] {
        var parents: [UUID: UUID] = [:], seen = Set<UUID>()
        for visit in app.graph.visits where visit.threadID == thread.id {
            if seen.insert(visit.nodeID).inserted, let parent = visit.parentNodeID { parents[visit.nodeID] = parent }
        }
        return ThreadBranch.rows(ids: thread.nodes.map(\.id), parents: parents)
    }
    private var notes: [Annotation] { Self.notes(for: thread, app: app) }
    static func notes(for thread: KnowledgeGraph.Thread, app: AppState) -> [Annotation] {
        let urls = Set(thread.nodes.map { KnowledgeGraph.canonicalURL($0.url) })
        return app.vault.annotations.filter { urls.contains(KnowledgeGraph.canonicalURL($0.url)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Label(thread.start.formatted(.dateTime.month(.wide).day().hour().minute()), systemImage: "clock")
                    .font(ShellType.caption).foregroundStyle(app.pal.ink3).padding(.bottom, 8)
                Text(thread.title).font(ShellType.title).fixedSize(horizontal: false, vertical: true)
                Text("\(thread.nodes.count) \(thread.nodes.count == 1 ? "page" : "pages") · \(thread.hosts.count) \(thread.hosts.count == 1 ? "site" : "sites") · \(notes.count) \(notes.count == 1 ? "note" : "notes")")
                    .font(ShellType.secondary).foregroundStyle(app.pal.ink2).padding(.top, 4)
                Button { resume() } label: { Label("Continue browsing", systemImage: "arrow.up.right") }
                    .buttonStyle(.bordered).controlSize(.small).font(ShellType.secondary).padding(.top, 14).padding(.bottom, 24)
                ThreadSummaryView(thread: thread).padding(.bottom, 18)
                HStack {
                    Text("Pages").font(ShellType.label).foregroundStyle(app.pal.ink3)
                    Spacer()
                    Picker("Display", selection: $map) { Text("List").tag(false); Text("Map").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 120)
                }.padding(.bottom, 8)
                if map {
                    ThreadMap(thread: thread).padding(.top, 12)
                } else {
                    ForEach(branches) { branch in
                        if let node = thread.nodes.first(where: { $0.id == branch.id }) {
                            HStack(alignment: .top, spacing: 8) {
                                if branch.depth > 0 {
                                    Image(systemName: "arrow.turn.down.right").font(ShellType.glyphSmall).foregroundStyle(app.pal.ink3).padding(.top, 16)
                                }
                                SourceEntry(node: node, threadID: thread.id)
                            }.padding(.leading, CGFloat(min(branch.depth, 6)) * 18)
                                .accessibilityElement(children: .contain).accessibilityLabel("Branch level \(branch.depth + 1): \(node.title)")
                                .accessibilityIdentifier("thread.branch.\(node.id)")
                        }
                    }
                }
                if !notes.isEmpty {
                    Text("Saved notes").font(ShellType.label).foregroundStyle(app.pal.ink3).padding(.top, 24).padding(.bottom, 6)
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(note.text.isEmpty ? note.title : note.text).font(ShellType.row).lineSpacing(3).textSelection(.enabled)
                            if !note.note.isEmpty { Text(note.note).font(ShellType.secondary).foregroundStyle(app.pal.ink2) }
                            Text(URL(string: note.url)?.host ?? "Saved note").font(ShellType.caption).foregroundStyle(app.pal.ink3)
                        }.padding(.vertical, 14)
                        Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline)
                    }
                }
            }.frame(maxWidth: 720, alignment: .leading).padding(24).frame(maxWidth: .infinity, alignment: .top)
        }
    }
    private func resume() {
        guard let node = thread.nodes.last, let url = URL(string: node.url) else { return }
        let tab = app.newTab()
        tab.currentNodeID = node.id; tab.currentThreadID = thread.id; tab.resumeThreadID = thread.id
        tab.load(url)
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

private struct SourceEntry: View {
    let node: GraphNode
    let threadID: UUID
    @EnvironmentObject var app: AppState
    @State private var expanded = false
    private var parent: GraphNode? {
        guard let id = app.graph.visits.first(where: { $0.threadID == threadID && $0.nodeID == node.id })?.parentNodeID,
              id != node.id else { return nil }
        return app.graph.nodes[id]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: ShellLayout.rowInsetLeading) {
                Favicon(host: node.host, size: ShellLayout.iconSize).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Button { if let url = URL(string: node.url) { app.openTab(url: url, parent: nil, activate: true) } } label: {
                        Text(node.title).font(ShellType.rowSelected).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain)
                    Text(node.host).font(ShellType.caption).foregroundStyle(app.pal.ink3)
                }
                Spacer(minLength: 0)
                Text(node.firstVisit.formatted(.dateTime.hour().minute())).font(ShellType.caption).foregroundStyle(app.pal.ink3)
            }
            if !node.snippet.isEmpty {
                Text(node.snippet.split(whereSeparator: \.isWhitespace).joined(separator: " ")).font(ShellType.secondary).foregroundStyle(app.pal.ink2)
                    .lineSpacing(3).lineLimit(expanded ? nil : 2).textSelection(.enabled)
                Button(expanded ? "Show less" : "Show more") { expanded.toggle() }.font(ShellType.caption).buttonStyle(.plain).foregroundStyle(app.pal.ink3)
            }
            if let parent {
                Label("Opened from \(parent.title)", systemImage: "arrow.turn.down.right").font(ShellType.caption).foregroundStyle(app.pal.ink3).lineLimit(1)
            }
        }.padding(.vertical, 14)
        Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline)
    }
}

private struct ThreadMap: View {
    let thread: KnowledgeGraph.Thread
    @EnvironmentObject var app: AppState

    private var firstParents: [UUID: UUID] {
        var parents: [UUID: UUID] = [:]
        var seen = Set<UUID>()
        let ids = Set(thread.nodes.map(\.id))
        for visit in app.graph.visits where visit.threadID == thread.id {
            guard seen.insert(visit.nodeID).inserted, let parent = visit.parentNodeID,
                  parent != visit.nodeID, ids.contains(parent) else { continue }
            parents[visit.nodeID] = parent
        }
        return parents
    }
    private var positions: [UUID: CGPoint] {
        let parents = firstParents
        var depths: [UUID: Int] = [:]
        for node in thread.nodes { depths[node.id] = parents[node.id].flatMap { depths[$0] }.map { $0 + 1 } ?? 0 }
        let columns = Dictionary(grouping: thread.nodes, by: { depths[$0.id] ?? 0 })
        let rows = columns.values.map(\.count).max() ?? 1
        var result: [UUID: CGPoint] = [:]
        for (column, nodes) in columns {
            for (row, node) in nodes.enumerated() {
                result[node.id] = CGPoint(x: 20 + CGFloat(column) * 195, y: 20 + CGFloat(row) * 112 + CGFloat(rows - nodes.count) * 56)
            }
        }
        return result
    }
    var body: some View {
        let positions = positions
        let width = (positions.values.map(\.x).max() ?? 20) + 170
        let height = (positions.values.map(\.y).max() ?? 20) + 100
        VStack(alignment: .leading, spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for (child, parent) in firstParents {
                            guard let origin = positions[parent], let target = positions[child] else { continue }
                            let a = CGPoint(x: origin.x + 150, y: origin.y + 40)
                            let b = CGPoint(x: target.x, y: target.y + 40)
                            var path = Path(); path.move(to: a)
                            path.addCurve(to: b, control1: CGPoint(x: a.x + 24, y: a.y), control2: CGPoint(x: b.x - 24, y: b.y))
                            context.stroke(path, with: .color(app.pal.ink3), lineWidth: ShellLayout.hairline)
                            var arrow = Path(); arrow.move(to: CGPoint(x: b.x - 5, y: b.y - 3)); arrow.addLine(to: b); arrow.addLine(to: CGPoint(x: b.x - 5, y: b.y + 3))
                            context.stroke(arrow, with: .color(app.pal.ink3), lineWidth: ShellLayout.hairline)
                        }
                    }
                    ForEach(thread.nodes) { node in
                        Button { if let url = URL(string: node.url) { app.openTab(url: url, parent: nil, activate: true) } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(node.host).font(ShellType.caption).foregroundStyle(app.pal.ink3).lineLimit(1)
                                Text(node.title).font(ShellType.secondary).lineLimit(2).multilineTextAlignment(.leading)
                            }.padding(12).frame(width: 150, height: 80, alignment: .leading)
                                .background(app.pal.pageBg, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                                .overlay(RoundedRectangle(cornerRadius: ShellLayout.rowRadius).strokeBorder(app.pal.hairline))
                        }.buttonStyle(.plain).offset(positions[node.id].map { CGSize(width: $0.x, height: $0.y) } ?? .zero)
                    }
                }.frame(width: width, height: height)
            }.frame(height: min(height, 320))
            Text("The first path to each page. Select a source to reopen it.").font(ShellType.caption).foregroundStyle(app.pal.ink3)
                .padding(.horizontal, 16).padding(.bottom, 14)
        }.background(app.pal.tileFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
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
struct LibraryBarButton: View {
    let title: String
    let system: String
    let action: () -> Void
    init(_ title: String, system: String, action: @escaping () -> Void) { self.title = title; self.system = system; self.action = action }
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(ShellType.glyph).frame(width: ShellLayout.controlSize, height: ShellLayout.controlSize).contentShape(Rectangle())
        }.buttonStyle(LibraryGlyphStyle())
            .help(title).accessibilityLabel(title).accessibilityIdentifier("library.\(system).\(title)").accessibilityAddTraits(.isButton)
    }
}

/// `ink3` glyph (`inkDisabled` when disabled) with `rowHover` behind it on hover or press.
struct LibraryGlyphStyle: ButtonStyle {
    @EnvironmentObject var app: AppState
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(enabled ? app.pal.ink3 : app.pal.inkDisabled)
            .background(enabled && (hovered || configuration.isPressed) ? app.pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovered)
    }
}
