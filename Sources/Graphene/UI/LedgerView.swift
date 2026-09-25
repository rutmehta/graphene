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
        if let error = app.graph.errorText, app.currentThreads.isEmpty {
            SurfaceState(symbol: "exclamationmark.triangle", title: "Threads unavailable", detail: error) {
                Button("Browse") { app.show(.web) }.buttonStyle(.bordered)
            }
        } else if app.currentThreads.isEmpty {
            SurfaceState(symbol: "point.3.connected.trianglepath.dotted", title: "No threads yet", detail: "Pages you explore together become a thread. Start browsing to create your first one.") {
                Button("Start browsing") { app.newTab() }.buttonStyle(.bordered)
            }
        } else {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Threads").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text("\(app.currentThreads.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(app.pal.ink3)
                    }.padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 18)
                    FilterField(placeholder: "Search threads", text: $filter).padding(.horizontal, 12).padding(.bottom, 12)
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                                if index == 0 || !Calendar.current.isDate(thread.start, inSameDayAs: threads[index - 1].start) {
                                    Text(thread.start.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11, weight: .semibold)).foregroundStyle(app.pal.ink3).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 12)
                                }
                                Button { app.selectedThreadID = thread.id } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(thread.title).font(.system(size: 13, weight: .medium)).foregroundStyle(app.pal.ink).lineLimit(2).multilineTextAlignment(.leading)
                                        HStack(spacing: -3) { ForEach(Array(thread.hosts.prefix(4)), id: \.self) { Favicon(host: $0, size: 14) }; Spacer(); Text("\(max(1, Int(thread.end.timeIntervalSince(thread.start) / 60))) min").font(.system(size: 10)).foregroundStyle(app.pal.ink3) }
                                        Text(thread.hosts.prefix(2).joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(app.pal.ink2).lineLimit(1)
                                        HStack(spacing: 5) {
                                            Text(thread.end.formatted(.dateTime.month(.abbreviated).day()))
                                            Text("·")
                                            Text("\(thread.nodes.count) \(thread.nodes.count == 1 ? "page" : "pages")")
                                        }.font(.system(size: 10)).foregroundStyle(app.pal.ink3)
                                    }
                                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selected?.id == thread.id ? app.pal.hover : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            if threads.isEmpty { Text("No matching threads").font(.system(size: 12)).foregroundStyle(app.pal.ink3).padding(24) }
                        }.padding(.horizontal, 8)
                    }
                    Label("Saved on this Mac", systemImage: "internaldrive").font(.system(size: 10)).foregroundStyle(app.pal.ink3).padding(18)
                }.frame(width: 230).background(app.pal.hover.opacity(0.25))
                    .focusable()
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.return) { if let selected { app.resumeThread(selected) }; return .handled }
                Rectangle().fill(app.pal.hairline).frame(width: 1)
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
    private var notes: [Annotation] {
        let urls = Set(thread.nodes.map { KnowledgeGraph.canonicalURL($0.url) })
        return app.vault.annotations.filter { urls.contains(KnowledgeGraph.canonicalURL($0.url)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(thread.start.formatted(.dateTime.month(.wide).day().hour().minute()), systemImage: "clock")
                    Spacer()
                    IconButton("Export thread as Markdown", system: "square.and.arrow.up") { export() }
                }.font(.system(size: 11)).foregroundStyle(app.pal.ink3).padding(.bottom, 14)
                Text(thread.title).font(.system(size: 22, weight: .semibold)).tracking(-0.35).fixedSize(horizontal: false, vertical: true)
                Text("\(thread.nodes.count) \(thread.nodes.count == 1 ? "page" : "pages") · \(thread.hosts.count) \(thread.hosts.count == 1 ? "site" : "sites") · \(notes.count) \(notes.count == 1 ? "note" : "notes")")
                    .font(.system(size: 11)).foregroundStyle(app.pal.ink2).padding(.top, 8)
                HStack(spacing: 10) {
                    Button { resume() } label: { Label("Continue browsing", systemImage: "arrow.up.right") }.buttonStyle(.bordered)
                    Button { app.askThread(thread) } label: { Label("Ask this thread", systemImage: "text.bubble") }.buttonStyle(.bordered)

                }.controlSize(.small).font(.system(size: 12)).padding(.top, 18).padding(.bottom, 28)
                ThreadSummaryView(thread: thread).padding(.bottom, 18)
                HStack {
                    Text("Pages").font(.system(size: 12, weight: .semibold))
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
                                    Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(app.pal.ink3).padding(.top, 18)
                                }
                                SourceEntry(node: node, threadID: thread.id)
                            }.padding(.leading, CGFloat(min(branch.depth, 6)) * 18)
                                .accessibilityElement(children: .contain).accessibilityLabel("Branch level \(branch.depth + 1): \(node.title)")
                                .accessibilityIdentifier("thread.branch.\(node.id)")
                        }
                    }
                }
                if !notes.isEmpty {
                    Text("Saved notes").font(.system(size: 12, weight: .semibold)).padding(.top, 28).padding(.bottom, 6)
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(note.text.isEmpty ? note.title : note.text).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled)
                            if !note.note.isEmpty { Text(note.note).font(.system(size: 12)).foregroundStyle(app.pal.ink2) }
                            Text(URL(string: note.url)?.host ?? "Saved note").font(.system(size: 11)).foregroundStyle(app.pal.ink3)
                        }.padding(.vertical, 16)
                        Rectangle().fill(app.pal.hairline).frame(height: 1)
                    }
                }
            }.frame(maxWidth: 720, alignment: .leading).padding(28).frame(maxWidth: .infinity, alignment: .top)
        }
    }
    private func resume() {
        guard let node = thread.nodes.last, let url = URL(string: node.url) else { return }
        let tab = app.newTab()
        tab.currentNodeID = node.id; tab.currentThreadID = thread.id; tab.resumeThreadID = thread.id
        tab.load(url)
    }
    private func export() {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Favicon(host: node.host, size: 20).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Button { if let url = URL(string: node.url) { app.openTab(url: url, parent: nil, activate: true) } } label: {
                        Text(node.title).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain)
                    Text(node.host).font(.system(size: 11)).foregroundStyle(app.pal.ink3)
                }
                Spacer(minLength: 0)
                Text(node.firstVisit.formatted(.dateTime.hour().minute())).font(.system(size: 10)).foregroundStyle(app.pal.ink3)
            }
            if !node.snippet.isEmpty {
                Text(node.snippet.split(whereSeparator: \.isWhitespace).joined(separator: " ")).font(.system(size: 12)).foregroundStyle(app.pal.ink2).lineSpacing(3).lineLimit(expanded ? nil : 2).textSelection(.enabled)
                Button(expanded ? "Show less" : "Show more") { expanded.toggle() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(app.pal.ink3)
            }
            if let parent {
                Label("Opened from \(parent.title)", systemImage: "arrow.turn.down.right").font(.system(size: 10)).foregroundStyle(app.pal.ink3).lineLimit(1)
            }
        }.padding(.vertical, 15)
        Rectangle().fill(app.pal.hairline).frame(height: 1)
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
                            context.stroke(path, with: .color(app.pal.ink3.opacity(0.6)), lineWidth: 1)
                            var arrow = Path(); arrow.move(to: CGPoint(x: b.x - 5, y: b.y - 3)); arrow.addLine(to: b); arrow.addLine(to: CGPoint(x: b.x - 5, y: b.y + 3))
                            context.stroke(arrow, with: .color(app.pal.ink3.opacity(0.6)), lineWidth: 1)
                        }
                    }
                    ForEach(thread.nodes) { node in
                        Button { if let url = URL(string: node.url) { app.openTab(url: url, parent: nil, activate: true) } } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(node.host).font(.system(size: 9)).foregroundStyle(app.pal.ink3).lineLimit(1)
                                Text(node.title).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                            }.padding(12).frame(width: 150, height: 80, alignment: .leading).background(app.pal.elev, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(app.pal.hairline))
                        }.buttonStyle(.plain).offset(positions[node.id].map { CGSize(width: $0.x, height: $0.y) } ?? .zero)
                    }
                }.frame(width: width, height: height)
            }.frame(height: min(height, 320))
            Text("The first path to each page. Select a source to reopen it.").font(.system(size: 10)).foregroundStyle(app.pal.ink3).padding(.horizontal, 16).padding(.bottom, 14)
        }.background(app.pal.hover, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct FilterField: View {
    @EnvironmentObject var app: AppState
    let placeholder: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(app.pal.ink3)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 12))
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(app.pal.ink3).accessibilityLabel("Clear search") }
        }.padding(.horizontal, 10).frame(height: 32).background(app.pal.hover, in: RoundedRectangle(cornerRadius: 6))
    }
}
