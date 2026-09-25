import SwiftUI
import AppKit

/// The Board (graphene-language.md §5.6): the one place the lattice is a working surface.
/// Cards snap to the lattice; provenance connectors between cards are derived from the graph.
struct EaselView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The card being moved or resized, with its live translation.
    @State private var gesture: CardGesture?
    @State private var confirmClear = false
    private var items: [BoardItem] { app.boards.items(in: app.activeSpaceID) }

    struct CardGesture: Equatable {
        let id: UUID
        let resizing: Bool
        var translation: CGSize
    }

    var body: some View {
        let items = items
        let frames = liveFrames(items)
        let links = BoardLinks.derive(items: items, graph: app.graph)
        VStack(spacing: 0) {
            LibraryBar(title: "\(app.activeSpace.name) Board", detail: items.isEmpty ? nil : "\(items.count)") {
                LibraryBarButton("Add note", system: "note.text.badge.plus") { addNote() }
                LibraryBarButton("Add link", system: "link.badge.plus") { addCurrentTab() }.disabled(app.activeTab?.url == nil)
                LibraryBarButton("Export Markdown", system: "square.and.arrow.up") { export() }.disabled(items.isEmpty)
                LibraryBarButton("Clear", system: "trash") { confirmClear = true }.disabled(items.isEmpty)
            }
            if let error = app.boards.errorText {
                Text(error).font(ShellType.secondary).foregroundStyle(app.pal.danger)
                    .padding(.horizontal, ShellLayout.windowGap + ShellLayout.rowInsetLeading).padding(.vertical, ShellLayout.windowGap)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GeometryReader { viewport in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Lattice(fade: false)
                        // Above the lattice: a `pageBg` knockout clears the lattice under the
                        // connector, so the `threadLine` stroke sits on the plain canvas at its
                        // full token opacity instead of mixing with the lattice strokes.
                        ForEach(links) { link in
                            if let parent = frames[link.parent], let child = frames[link.child] {
                                let ends = BoardLinks.endpoints(parent: parent, child: child)
                                ZStack {
                                    BoardConnector(from: ends.from, to: ends.to)
                                        .stroke(app.pal.pageBg, lineWidth: BoardLinks.knockoutWidth)
                                    BoardConnector(from: ends.from, to: ends.to)
                                        .stroke(app.pal.threadLine, lineWidth: ShellLayout.hairline)
                                }
                                .transition(.opacity)
                            }
                        }
                        .allowsHitTesting(false)
                        .zIndex(0.5)
                        .animation(BoardMotion.connector(reduced: reduceMotion), value: links)
                        ForEach(items) { item in
                            let frame = frames[item.id] ?? CGRect(x: item.x, y: item.y, width: item.width, height: item.height)
                            BoardCard(item: item, size: frame.size,
                                      move: { track(item, resizing: false, $0) }, endMove: { finish(item, resizing: false, $0) },
                                      resize: { track(item, resizing: true, $0) }, endResize: { finish(item, resizing: true, $0) })
                                .offset(x: frame.minX, y: frame.minY)
                                .zIndex(gesture?.id == item.id ? 2 : 1)
                        }
                    }
                    .frame(width: max(viewport.size.width, (frames.values.map(\.maxX).max() ?? 0) + ShellLayout.latticeCell * 4),
                           height: max(viewport.size.height, (frames.values.map(\.maxY).max() ?? 0) + ShellLayout.latticeCell * 4))
                    .contentShape(Rectangle())
                    .dropDestination(for: DroppedText.self) { drops, point in
                        guard let value = drops.first?.value, let card = app.boardDropCard(for: value) else { return false }
                        add(card, at: point)
                        return true
                    }
                }
                .onChange(of: viewport.size.width, initial: true) { _, width in app.boardRowWidth = width }
                .overlay {
                    if items.isEmpty {
                        Text("Drop tabs, notes and quotes here.").font(ShellType.secondary).foregroundStyle(app.pal.ink3)
                            .allowsHitTesting(false)
                    }
                }
            }
        }.foregroundStyle(app.pal.ink).background(app.pal.pageBg)
            .confirmationDialog("Clear this Board?", isPresented: $confirmClear) {
                Button("Clear Board", role: .destructive) { app.boards.clear(spaceID: app.activeSpaceID) }
            } message: { Text("Every card on \(app.activeSpace.name)’s Board is removed.") }
    }

    /// Card frames with the live move or resize applied, so connectors follow drags.
    private func liveFrames(_ items: [BoardItem]) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        for item in items {
            var frame = CGRect(x: item.x, y: item.y, width: item.width, height: item.height)
            if let gesture, gesture.id == item.id {
                if gesture.resizing {
                    frame.size.width = min(BoardItem.maxSize.width, max(BoardItem.minSize.width, frame.width + gesture.translation.width))
                    frame.size.height = min(BoardItem.maxSize.height, max(BoardItem.minSize.height, frame.height + gesture.translation.height))
                } else {
                    frame.origin.x = max(0, frame.minX + gesture.translation.width)
                    frame.origin.y = max(0, frame.minY + gesture.translation.height)
                }
            }
            frames[item.id] = frame
        }
        return frames
    }

    private func track(_ item: BoardItem, resizing: Bool, _ translation: CGSize) {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { gesture = CardGesture(id: item.id, resizing: resizing, translation: translation) }
    }

    /// Drop and resize end both snap to the lattice with the Board spring.
    private func finish(_ item: BoardItem, resizing: Bool, _ translation: CGSize) {
        withAnimation(BoardMotion.snap(reduced: reduceMotion)) {
            app.boards.upsert(resizing ? BoardGrid.resized(item, by: translation) : BoardGrid.moved(item, by: translation))
            gesture = nil
        }
    }

    private func addNote() { add(BoardDropCard(kind: .note, title: "Note")) }
    private func addCurrentTab() {
        guard let tab = app.activeTab, let url = tab.url else { return }
        add(BoardDropCard(kind: .page, title: tab.displayTitle, url: url.absoluteString))
    }
    /// A drop keeps its snapped position; Add note and Add link take the first free cell.
    private func add(_ card: BoardDropCard, at point: CGPoint? = nil) {
        withAnimation(BoardMotion.snap(reduced: reduceMotion)) { _ = app.addBoardCard(card, at: point) }
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(app.activeSpace.name) Board.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try app.boards.markdown(spaceID: app.activeSpaceID).write(to: url, atomically: true, encoding: .utf8); app.notify("Board exported") }
        catch { app.notify("Couldn’t export: \(error.localizedDescription)") }
    }
}

/// Board motion (graphene-language.md §6): a card drop snaps to its cell with spring(0.3, 0.75)
/// and connectors redraw over 160ms. Reduce Motion places cards without travel and fades connectors.
enum BoardMotion {
    static func snap(reduced: Bool) -> Animation? { reduced ? nil : .spring(response: 0.3, dampingFraction: 0.75) }
    static func connector(reduced: Bool) -> Animation { reduced ? Motion.hover.reduced(true) : .easeOut(duration: 0.16) }
}

/// A provenance connector between two cards; its endpoints animate with the card spring.
struct BoardConnector: Shape {
    var from: CGPoint
    var to: CGPoint
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(from.x, from.y), AnimatablePair(to.x, to.y)) }
        set { from = CGPoint(x: newValue.first.first, y: newValue.first.second); to = CGPoint(x: newValue.second.first, y: newValue.second.second) }
    }
    func path(in rect: CGRect) -> Path { BoardLinks.path(from: from, to: to) }
}

/// One card: `elev`, `boardCardRadius`, hairline and `pageShadow`, in its kind's layout.
private struct BoardCard: View {
    let item: BoardItem
    let size: CGSize
    let move: (CGSize) -> Void
    let endMove: (CGSize) -> Void
    let resize: (CGSize) -> Void
    let endResize: (CGSize) -> Void
    @EnvironmentObject var app: AppState
    @State private var hovering = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: ShellLayout.boardCardRadius) }
    private var link: URL? { item.url.flatMap(URL.init(string:)) }
    private func binding(_ key: WritableKeyPath<BoardItem, String>) -> Binding<String> {
        Binding(get: { item[keyPath: key] }, set: { var copy = item; copy[keyPath: key] = $0; app.boards.upsert(copy) })
    }
    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .global).onChanged { move($0.translation) }.onEnded { endMove($0.translation) }
    }

    var body: some View {
        let pal = app.pal
        content(pal)
            .padding(ShellLayout.sectionGap)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(pal.elev, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(pal.hairline, lineWidth: ShellLayout.hairline))
            .shadow(color: pal.pageShadow, radius: pal.pageShadowRadius, y: pal.pageShadowY)
            .contentShape(shape)
            .gesture(moveGesture)
            .onTapGesture(count: 2) { open() }
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button { app.boards.delete(item.id) } label: {
                        Image(systemName: "xmark").font(ShellType.glyphSmall).frame(width: ShellLayout.closeTarget, height: ShellLayout.closeTarget).contentShape(Rectangle())
                    }.buttonStyle(LibraryGlyphStyle()).padding(ShellLayout.iconBackingInset).accessibilityLabel("Delete card")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if hovering {
                    Image(systemName: "arrow.down.right").font(ShellType.glyphMini).foregroundStyle(pal.ink3)
                        .frame(width: ShellLayout.closeTarget, height: ShellLayout.closeTarget).contentShape(Rectangle())
                        .gesture(DragGesture(coordinateSpace: .global).onChanged { resize($0.translation) }.onEnded { endResize($0.translation) })
                        .accessibilityLabel("Resize card")
                }
            }
            .onHover { hovering = $0 }
            .contextMenu {
                if link != nil { Button("Open") { open() } }
                Button("Delete", role: .destructive) { app.boards.delete(item.id) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(item.title)
    }

    @ViewBuilder private func content(_ pal: Palette) -> some View {
        switch item.cardKind {
        case .page: PageCardContent(item: item)
        case .note:
            VStack(alignment: .leading, spacing: ShellLayout.iconBackingInset) {
                TextField("Title", text: binding(\.title)).textFieldStyle(.plain).font(ShellType.title).foregroundStyle(pal.ink)
                TextEditor(text: binding(\.text)).font(ShellType.row).foregroundStyle(pal.ink).scrollContentBackground(.hidden)
            }
        case .quote:
            VStack(alignment: .leading, spacing: ShellLayout.rowInsetLeading) {
                HStack(alignment: .top, spacing: ShellLayout.rowInsetLeading) {
                    Rectangle().fill(pal.quoteRule).frame(width: ShellLayout.hairline)
                    // Clamp the quote so the note and the provenance line always fit inside the card.
                    Text(item.quote ?? "").font(ShellType.quote).lineSpacing(ShellType.quoteLineSpacing).foregroundStyle(pal.ink)
                        .lineLimit(BoardCardText.quoteLineLimit).truncationMode(.tail)
                }
                if !item.text.isEmpty { Text(item.text).font(ShellType.row).foregroundStyle(pal.ink2).lineLimit(2) }
                Spacer(minLength: 0)
                Text(BoardCardText.provenance(item)).font(ShellType.caption).foregroundStyle(pal.ink3).lineLimit(1)
            }
        }
    }

    private func open() { if let link { app.openTab(url: link, parent: nil, activate: true) } }
}

/// A page card: 16:10 thumbnail (or a `fill` placeholder), favicon and title, host.
private struct PageCardContent: View {
    let item: BoardItem
    @EnvironmentObject var app: AppState
    @ObservedObject private var thumbnails = ThumbnailCache.shared

    /// The cached thumbnail of an open, non-private tab showing this page.
    private var thumbnail: NSImage? {
        guard let url = item.url else { return nil }
        let key = KnowledgeGraph.canonicalURL(url)
        return app.tabs.first { !$0.isPrivate && $0.url.map { KnowledgeGraph.canonicalURL($0.absoluteString) } == key && thumbnails.images[$0.id] != nil }
            .flatMap { thumbnails.images[$0.id] }
    }

    var body: some View {
        let pal = app.pal
        VStack(alignment: .leading, spacing: ShellLayout.rowInsetLeading) {
            pal.elevFill.aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay { if let thumbnail { Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill) } }
                .clipShape(RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            HStack(spacing: ShellLayout.iconGap) {
                Favicon(FaviconRequest(page: item.url ?? ""), size: ShellLayout.iconSize)
                Text(item.title).font(ShellType.row).foregroundStyle(pal.ink).lineLimit(1)
            }
            Text(BoardCardText.host(item)).font(ShellType.caption).foregroundStyle(pal.ink3).lineLimit(1)
        }
    }
}

/// Text a card derives from its item.
enum BoardCardText {
    static func host(_ item: BoardItem) -> String {
        guard let host = item.url.flatMap(URL.init(string:))?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    /// Lines of quote a card shows before truncating, leaving room for the note and provenance.
    static let quoteLineLimit = 6
    /// The quote card's provenance line: the source page's title and host.
    static func provenance(_ item: BoardItem) -> String {
        [item.title, host(item)].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
