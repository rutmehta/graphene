import SwiftUI
import AppKit

/// The Vault list's rules (graphene-language.md §5.3), kept apart from the view so they test
/// without a window: order, filtering, the provenance line and the By-page grouping.
enum VaultList {
    /// A row's provenance line: page title, space name, relative date, joined by " · ".
    struct Provenance: Equatable {
        var title: String
        var space: String?
        var date: String
        var line: String { ([title] + [space, date].compactMap { $0 }).filter { !$0.isEmpty }.joined(separator: " · ") }
    }

    /// Newest first.
    static func sorted(_ notes: [Annotation]) -> [Annotation] { notes.sorted { $0.created > $1.created } }

    /// Whether `note` matches the library bar's filter (quote, note, title or address).
    static func matches(_ note: Annotation, filter: String) -> Bool {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [note.text, note.note, note.title, note.url].contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// The page a note names: its title, else its host without "www.", else "Saved note".
    static func title(_ note: Annotation) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let host = URL(string: note.url)?.host, !host.isEmpty { return host.replacingOccurrences(of: "www.", with: "") }
        return "Saved note"
    }

    /// "2 hours ago", "yesterday", "last week": the save date relative to `now`.
    static func relativeDate(_ date: Date, now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func provenance(_ note: Annotation, spaces: [SpaceInfo], now: Date = Date(), locale: Locale = .current) -> Provenance {
        let space = note.spaceID.flatMap { id in spaces.first { $0.id == id }?.name }
        return Provenance(title: title(note), space: space, date: relativeDate(note.created, now: now, locale: locale))
    }

    /// The notes of one page, for the By-page view.
    struct PageGroup: Identifiable {
        /// The page's canonical address, or the note's reference for a note without one.
        let id: String
        let title: String
        let url: String
        /// Newest first.
        let notes: [Annotation]
    }

    /// Notes grouped under their page (by canonical address), each group newest first and the
    /// groups ordered by their newest note. A group takes the title of its newest note.
    @MainActor static func byPage(_ notes: [Annotation]) -> [PageGroup] {
        var order: [String] = []
        var members: [String: [Annotation]] = [:]
        for note in sorted(notes) {
            let key = note.url.isEmpty ? NoteDrag.reference(note.id) : KnowledgeGraph.canonicalURL(note.url)
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(note)
        }
        return order.compactMap { key in
            guard let group = members[key], let newest = group.first else { return nil }
            return PageGroup(id: key, title: title(newest), url: newest.url, notes: group)
        }
    }

    /// Where a By-page connector's tick meets a note row: the middle of the quote's first line.
    static var tickY: CGFloat {
        ShellLayout.sectionGap + ShellLayout.rowInsetLeading + ShellType.quoteSize * ShellType.quoteLineHeight / 2
    }
}

/// The Vault: saved notes as a list of row groups, newest first, or grouped by page.
struct VaultView: View {
    @EnvironmentObject var app: AppState
    @State private var filter = ""
    @State private var byPage = false
    @State private var editingID: UUID?
    @State private var deleting: Annotation?
    private var notes: [Annotation] { VaultList.sorted(app.vault.annotations.filter { VaultList.matches($0, filter: filter) }) }
    private var selected: Annotation? { app.vault.annotations.first { $0.id == app.vaultSelectionID } }

    var body: some View {
        VStack(spacing: 0) {
            LibraryBar(title: "Vault", detail: app.vault.annotations.isEmpty ? nil : "\(app.vault.annotations.count)") {
                if !app.vault.annotations.isEmpty {
                    FilterField(placeholder: "Filter notes", text: $filter).frame(width: ShellLayout.sidebarDefault)
                    if let selected {
                        LibraryBarButton("Edit note", system: "pencil") { editingID = selected.id }
                        LibraryBarButton("Delete note", system: "trash") { deleting = selected }
                        LibraryBarButton("Copy as Markdown", system: "doc.on.doc") { copy(selected) }
                        LibraryBarButton("Add to Board", system: "rectangle.on.rectangle") { addToBoard(selected) }
                    }
                    LibraryBarButton(byPage ? "Newest first" : "By page", system: byPage ? "list.bullet" : "list.bullet.indent") { byPage.toggle() }
                    LibraryBarButton("Ask my notes", system: ShellGlyph.ask) { askNotes() }.disabled(notes.isEmpty)
                }
                LibraryBarButton("Open vault folder", system: "folder") { NSWorkspace.shared.open(Paths.vault) }
            }
            if let error = app.vault.errorText {
                Text("Couldn’t save: \(error)").font(ShellType.secondary).foregroundStyle(app.pal.danger)
                    .padding(.horizontal, ShellLayout.windowGap + ShellLayout.rowInsetLeading).padding(.vertical, ShellLayout.windowGap)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline)
            }
            content
        }.foregroundStyle(app.pal.ink).background(app.pal.pageBg)
            .confirmationDialog("Delete this saved note?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete note", role: .destructive) { if let deleting { app.deleteNote(deleting) }; deleting = nil }
            } message: { Text("The note and its Markdown file will be removed. Your browsing history is kept.") }
    }

    @ViewBuilder private var content: some View {
        if let error = app.vault.errorText, app.vault.annotations.isEmpty {
            SurfaceState(symbol: "exclamationmark.triangle", title: "Vault unavailable", detail: error) {
                Button("Open vault folder") { NSWorkspace.shared.open(Paths.vault) }.buttonStyle(.bordered)
            }
        } else if app.vault.annotations.isEmpty {
            SurfaceState(line: "Select text on any page and press ⌘D.", symbol: "bookmark")
        } else if notes.isEmpty {
            Text("No notes match this filter").font(ShellType.secondary).foregroundStyle(app.pal.ink3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ShellLayout.sectionGap) {
                        if byPage {
                            ForEach(VaultList.byPage(notes)) { group in pageGroup(group) }
                        } else {
                            ForEach(notes) { note in row(note) }
                        }
                    }.padding(.vertical, ShellLayout.sectionGap).padding(.horizontal, ShellLayout.windowGap)
                        .frame(maxWidth: ShellLayout.newTabColumnWidth + 2 * ShellLayout.newTabGap, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
                .onAppear { if let id = app.vaultSelectionID { proxy.scrollTo(id, anchor: .center) } }
                .onChange(of: app.vaultSelectionID) { _, id in if let id { withAnimation(Motion.hover.animation) { proxy.scrollTo(id) } } }
            }
        }
    }

    private func row(_ note: Annotation) -> some View {
        VaultNoteRow(note: note, selected: app.vaultSelectionID == note.id, editing: editingBinding(note)).id(note.id)
    }

    /// One page's notes under its title, joined by a depth-1 hairline tree in the sidebar's
    /// `ProvenanceConnector` geometry: the vertical at `threadLineInset` leaves the bottom of
    /// the page's icon slot and a `threadTick` enters each note's leading edge.
    private func pageGroup(_ group: VaultList.PageGroup) -> some View {
        let line = group.notes.contains { $0.id == app.vaultSelectionID } ? app.pal.threadLineActive : app.pal.threadLine
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Favicon(FaviconRequest(page: group.url), size: ShellLayout.iconSize).frame(width: ShellLayout.iconSlot, height: ShellLayout.iconSlot)
                Button { openPage(group.url) } label: {
                    Text(group.title).font(ShellType.row).foregroundStyle(app.pal.ink).lineLimit(1)
                }.buttonStyle(.plain).padding(.leading, ShellLayout.iconGap).help("Open page").disabled(URL(string: group.url)?.scheme == nil)
                Text("\(group.notes.count)").font(ShellType.caption).monospacedDigit().foregroundStyle(app.pal.ink3).padding(.leading, ShellLayout.iconGap)
                Spacer(minLength: 0)
            }.padding(.leading, ShellLayout.rowInsetLeading).frame(height: ShellLayout.rowHeight)
                .overlay(alignment: .topLeading) {
                    let top = (ShellLayout.rowHeight + ShellLayout.iconSlot) / 2
                    Rectangle().fill(line).frame(width: ShellLayout.hairline, height: ShellLayout.rowHeight - top)
                        .offset(x: ShellLayout.threadLineInset, y: top)
                }
            ForEach(Array(group.notes.enumerated()), id: \.element.id) { index, note in
                row(note).padding(.top, ShellLayout.sectionGap)
                    .padding(.leading, ShellLayout.threadIndent + ShellLayout.rowInsetLeading)
                    .background(alignment: .topLeading) {
                        VaultConnector(tickY: VaultList.tickY, last: index == group.notes.count - 1).fill(line)
                    }
            }
        }
    }

    private func editingBinding(_ note: Annotation) -> Binding<Bool> {
        Binding(get: { editingID == note.id }, set: { editingID = $0 ? note.id : (editingID == note.id ? nil : editingID) })
    }

    private func openPage(_ url: String) {
        guard let url = URL(string: url), url.scheme != nil else { return }
        app.openSource(url: url, passage: nil)
    }

    private func copy(_ note: Annotation) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Vault.markdown(for: note), forType: .string)
        app.notify("Copied as Markdown")
    }

    /// The same quote card a drop of the note makes, in the Board's first free cell.
    private func addToBoard(_ note: Annotation) {
        guard app.addNoteToBoard(note.id) != nil else { return }
        app.notify(app.boards.errorText == nil ? "Added to Board" : "Couldn’t add to Board")
    }

    private func askNotes() {
        app.attachedSources = notes.prefix(4).map { KnowledgeSource(id: $0.id, title: $0.title, url: $0.url, text: $0.text + "\n" + $0.note, kind: "Vault note") }
        app.knowledgeSearchPresented = true
    }
}

/// A note row's share of the By-page tree: the vertical down its leading gutter (to its tick
/// on the last note) and the tick into its leading edge.
struct VaultConnector: Shape {
    let tickY: CGFloat
    let last: Bool
    func path(in rect: CGRect) -> Path {
        let x = ShellLayout.threadLineInset, line = ShellLayout.hairline
        var path = Path()
        path.addRect(CGRect(x: x, y: 0, width: line, height: last ? tickY + line / 2 : rect.height))
        path.addRect(CGRect(x: x + line, y: tickY - line / 2, width: ShellLayout.threadTick - line, height: line))
        return path
    }
}

/// One saved note: the quote in serif beside its rule, the note under it, and the provenance
/// line. Clicking the quote opens the page at the mark; clicking the title opens the page;
/// clicking elsewhere selects the row. Dragging hands out the note (`NoteDrag`).
private struct VaultNoteRow: View {
    let note: Annotation
    let selected: Bool
    @Binding var editing: Bool
    @EnvironmentObject var app: AppState
    @State private var hovering = false
    @FocusState private var focused: Bool
    private var provenance: VaultList.Provenance { VaultList.provenance(note, spaces: app.spaces) }
    private var url: URL? { URL(string: note.url).flatMap { $0.scheme == nil ? nil : $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: ShellLayout.windowGap) {
            if !note.text.isEmpty {
                HStack(alignment: .top, spacing: ShellLayout.rowInsetLeading) {
                    Rectangle().fill(app.pal.quoteRule).frame(width: ShellLayout.hairline)
                        .padding(.vertical, ShellLayout.quoteRuleInset)
                    Text(note.text).font(ShellType.quote).lineSpacing(ShellType.quoteLineSpacing).foregroundStyle(app.pal.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                }.fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { openQuote() }
                    .help(url == nil ? "" : "Open the page at this passage")
                    .accessibilityAddTraits(.isButton).accessibilityAction { openQuote() }
            }
            if editing {
                editor
            } else if !note.note.isEmpty {
                Text(note.note).font(ShellType.row).foregroundStyle(app.pal.ink2).lineSpacing(ShellType.rowLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: ShellLayout.chipRadius) {
                Favicon(FaviconRequest(page: note.url), size: ShellLayout.provenanceIconSize)
                Button { if let url { app.openSource(url: url, passage: nil) } } label: {
                    Text(provenance.title).lineLimit(1)
                }.buttonStyle(.plain).disabled(url == nil).help("Open page")
                ForEach([provenance.space, provenance.date].compactMap { $0 }.filter { !$0.isEmpty }, id: \.self) { part in
                    Text("·"); Text(part).lineLimit(1)
                }
            }.font(ShellType.caption).foregroundStyle(app.pal.ink3)
        }.padding(ShellLayout.rowInsetLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? app.pal.rowSelected : (hovering ? app.pal.rowHover : .clear), in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle())
            .onTapGesture { app.vaultSelectionID = note.id }
            .onHover { hovering = $0 }
            .animation(Motion.hover.animation, value: hovering)
            .onDrag { NoteDrag.itemProvider(for: note) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(VaultShelfLayout.fullText(note))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("vault.row.\(note.id)")
    }

    private var draft: Binding<String> {
        Binding(get: { app.noteDrafts[note.id] ?? note.note }, set: { app.noteDrafts[note.id] = $0 })
    }

    private var editor: some View {
        VStack(alignment: .trailing, spacing: ShellLayout.windowGap) {
            TextEditor(text: draft).font(ShellType.body).focused($focused).scrollContentBackground(.hidden)
                .padding(ShellLayout.chipRadius).frame(minHeight: ShellLayout.commandInputHeight)
                .background(app.pal.tileFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                .accessibilityLabel("Note")
            HStack(spacing: ShellLayout.sectionGap) {
                Button("Cancel") { cancel() }.buttonStyle(.plain).font(ShellType.label).foregroundStyle(app.pal.ink3)
                Button("Save note") { app.updateNote(note, text: draft.wrappedValue); editing = false }
                    .buttonStyle(.plain).font(ShellType.label).foregroundStyle(app.pal.accent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }.onAppear { focused = true }
            .onExitCommand { cancel() }
    }

    private func cancel() {
        app.noteDrafts.removeValue(forKey: note.id)
        editing = false
    }

    private func openQuote() {
        app.vaultSelectionID = note.id
        guard let url else { return }
        app.openSource(url: url, passage: VaultShelfLayout.passage(note))
    }
}

struct NoteComposer: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var quote = ""
    @State private var sourceURL: URL?
    @State private var sourceTitle = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Save to Vault").font(ShellType.title)
                Spacer()
                LibraryBarButton("Cancel", system: "xmark") { dismiss() }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(sourceTitle.isEmpty ? "Current page" : sourceTitle).font(ShellType.rowSelected)
                Text(sourceURL?.host ?? "No page selected").font(ShellType.caption).foregroundStyle(app.pal.ink3)
            }
            if !quote.isEmpty {
                Text(quote).font(ShellType.row).lineSpacing(3).lineLimit(5).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(app.pal.tileFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            }
            Text("Add a note").font(ShellType.label).foregroundStyle(app.pal.ink3)
            TextEditor(text: $note).font(ShellType.row).focused($focused).scrollContentBackground(.hidden).padding(10).frame(height: 140)
                .background(app.pal.tileFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius)).accessibilityLabel("Add a note")
                .accessibilityIdentifier("note.composer")
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("note.cancel").accessibilityLabel("Cancel").accessibilityAddTraits(.isButton)
                Button("Save") {
                    app.vault.add(text: quote, note: note, url: sourceURL, title: sourceTitle, context: "", spaceID: app.activeSpaceID)
                    if app.vault.errorText == nil { app.notify("Saved to Vault"); dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(sourceURL == nil)
                    .accessibilityIdentifier("note.save").accessibilityLabel("Save to Vault").accessibilityAddTraits(.isButton)
            }
            if let error = app.vault.errorText { Text(error).font(ShellType.secondary).foregroundStyle(app.pal.danger) }
        }.font(ShellType.body).padding(24).frame(width: 480).foregroundStyle(app.pal.ink).background(app.pal.pageBg).tint(app.pal.accent)
        .task {
            guard let tab = app.activeTab else { return }
            sourceURL = tab.url; sourceTitle = tab.displayTitle
            quote = (await tab.engine.evaluateJavaScript("String(window.getSelection() || '')")) as? String ?? ""
            focused = true
        }
    }
}
