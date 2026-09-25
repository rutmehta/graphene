import SwiftUI
import AppKit

struct EaselView: View {
    @EnvironmentObject var app: AppState
    @State private var vaultPicker = false
    private var items: [BoardItem] { app.boards.items(in: app.activeSpaceID) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(app.activeSpace.name) Board", systemImage: "rectangle.3.group").font(.system(size: 17, weight: .semibold))
                Spacer()
                Menu {
                    Button("Link from current tab") { addCurrentTab() }.disabled(app.activeTab?.url == nil)
                    Button("Text note") { add(title: "Note") }
                    Button("From Vault…") { vaultPicker = true }
                } label: { Label("Add", systemImage: "plus") }
                Button("Export Markdown") { export() }.disabled(items.isEmpty)
            }.padding(18)
            Rectangle().fill(app.pal.hairline).frame(height: 1)
            if let error = app.boards.errorText { Text(error).font(.system(size: 13)).padding(12) }
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        for x in stride(from: 16.0, to: size.width, by: 24) {
                            for y in stride(from: 16.0, to: size.height, by: 24) {
                                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(app.pal.hairline))
                            }
                        }
                    }
                    if items.isEmpty {
                        Text("Drop a tab or Vault note here, or add a text note.").font(.system(size: 13)).foregroundStyle(app.pal.ink3).padding(28)
                    }
                    ForEach(items) { item in BoardCard(item: item).offset(x: item.x, y: item.y) }
                }.frame(width: max(1200, (items.map { $0.x + $0.width }.max() ?? 0) + 100), height: max(900, (items.map { $0.y + $0.height }.max() ?? 0) + 100))
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { strings, point in
                        guard let value = strings.first else { return false }
                        if let id = payloadID(value, prefix: "tab:"), let tab = app.tabs.first(where: { $0.id == id }) {
                            add(title: tab.displayTitle, url: tab.url?.absoluteString, at: point); return true
                        }
                        if let id = payloadID(value, prefix: "note:"), let note = app.vault.annotations.first(where: { $0.id == id }) {
                            add(title: note.title, text: note.text + "\n" + note.note, url: note.url, at: point); return true
                        }
                        if let url = URL(string: value), ["http", "https"].contains(url.scheme ?? "") { add(title: url.host ?? value, url: value, at: point) }
                        else { add(title: "Note", text: value, at: point) }
                        return true
                    }
            }
        }.foregroundStyle(app.pal.ink).background(app.pal.ground)
            .sheet(isPresented: $vaultPicker) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Add from Vault").font(.headline)
                    List(app.vault.annotations) { note in
                        Button(note.title) { add(title: note.title, text: note.text + "\n" + note.note, url: note.url); vaultPicker = false }.buttonStyle(.plain)
                    }
                    Button("Cancel") { vaultPicker = false }
                }.padding(20).frame(width: 460, height: 400).foregroundStyle(app.pal.ink).background(app.pal.ground)
            }
    }
    private func addCurrentTab() { if let tab = app.activeTab { add(title: tab.displayTitle, url: tab.url?.absoluteString) } }
    private func add(title: String, text: String = "", url: String? = nil, at point: CGPoint? = nil) {
        var item = BoardItem(spaceID: app.activeSpaceID, title: title, text: text, url: url)
        item.x = point.map { Double($0.x) } ?? Double(24 + items.count % 4 * 270)
        item.y = point.map { Double($0.y) } ?? Double(24 + items.count / 4 * 210)
        app.boards.upsert(item)
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(app.activeSpace.name) Board.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try app.boards.markdown(spaceID: app.activeSpaceID).write(to: url, atomically: true, encoding: .utf8); app.notify("Board exported") }
        catch { app.notify("Couldn’t export: \(error.localizedDescription)") }
    }
}

private struct BoardCard: View {
    let item: BoardItem
    @EnvironmentObject var app: AppState
    @GestureState private var movement = CGSize.zero
    @GestureState private var resize = CGSize.zero
    private func binding(_ key: WritableKeyPath<BoardItem, String>) -> Binding<String> {
        Binding(get: { item[keyPath: key] }, set: { var copy = item; copy[keyPath: key] = $0; app.boards.upsert(copy) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Favicon(host: item.url.flatMap { URL(string: $0)?.host }, size: 16)
                Image(systemName: "line.3.horizontal").foregroundStyle(app.pal.ink3)
                Spacer()
                Button { app.boards.delete(item.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Delete board item")
            }.contentShape(Rectangle())
                .gesture(DragGesture().updating($movement) { value, state, _ in state = value.translation }.onEnded { value in
                    var copy = item; copy.x += value.translation.width; copy.y += value.translation.height; app.boards.upsert(copy)
                })
                .help("Drag to move")
            TextField("Title", text: binding(\.title)).textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
            TextEditor(text: binding(\.text)).font(.system(size: 13)).scrollContentBackground(.hidden)
            HStack {
                if let url = item.url.flatMap(URL.init(string:)) {
                    Button("Open source") { app.openTab(url: url, parent: nil, activate: true) }.buttonStyle(.plain).foregroundStyle(app.pal.accentText)
                }
                Spacer()
                Image(systemName: "arrow.down.right").contentShape(Rectangle()).accessibilityLabel("Resize board item")
                    .gesture(DragGesture().updating($resize) { value, state, _ in state = value.translation }.onEnded { value in
                        var copy = item; copy.width += value.translation.width; copy.height += value.translation.height; app.boards.upsert(copy)
                    })
            }.font(.system(size: 11))
        }.padding(12).frame(width: max(180, item.width + resize.width), height: max(120, item.height + resize.height))
            .background(app.pal.elev, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(app.pal.hairline))
            .offset(movement)
            .contextMenu {
                Button("Move right") { var copy = item; copy.x += 24; app.boards.upsert(copy) }
                Button("Move down") { var copy = item; copy.y += 24; app.boards.upsert(copy) }
                Button("Make larger") { var copy = item; copy.width += 24; copy.height += 24; app.boards.upsert(copy) }
                Button("Delete", role: .destructive) { app.boards.delete(item.id) }
            }
    }
}
