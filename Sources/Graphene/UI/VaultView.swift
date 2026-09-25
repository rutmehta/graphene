import SwiftUI
import AppKit

struct VaultView: View {
    @EnvironmentObject var app: AppState
    @State private var filter = ""
    @State private var currentSpaceOnly = false
    @State private var kind = "All"
    @State private var site = ""
    @State private var deleting: Annotation?
    private var selectedID: UUID? { app.vaultSelectionID }
    private var annotations: [Annotation] {
        app.vault.annotations.filter { note in
            let inSpace = note.spaceID == app.activeSpaceID || (note.spaceID == nil && app.currentThreads.contains { $0.nodes.contains { $0.url == note.url } })
            return (!currentSpaceOnly || inSpace) && (kind == "All" || (kind == "Highlights" ? !note.text.isEmpty : note.text.isEmpty))
                && (site.isEmpty || URL(string: note.url)?.host == site)
                && (filter.isEmpty || (note.text + " " + note.note + " " + note.title + " " + note.url).localizedCaseInsensitiveContains(filter))
        }
    }
    private var selected: Annotation? { annotations.first { $0.id == selectedID } ?? annotations.first }

    var body: some View {
        VStack(spacing: 0) {
            LibraryBar(title: "Vault", detail: app.vault.annotations.isEmpty ? nil : "\(app.vault.annotations.count)") {
                if !app.vault.annotations.isEmpty {
                    LibraryBarButton("Ask my notes", system: "text.bubble") { askNotes() }.disabled(annotations.isEmpty)
                }
                LibraryBarButton("Open vault folder", system: "folder") { NSWorkspace.shared.open(Paths.vault) }
                if let selected { LibraryBarButton("Delete note", system: "trash") { deleting = selected } }
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
                Button("Delete note", role: .destructive) { if let deleting { delete(deleting) }; deleting = nil }
            } message: { Text("The note and its Markdown file will be removed. Your browsing history is kept.") }
    }

    @ViewBuilder private var content: some View {
        if let error = app.vault.errorText, app.vault.annotations.isEmpty {
            SurfaceState(symbol: "exclamationmark.triangle", title: "Vault unavailable", detail: error) {
                Button("Open vault folder") { NSWorkspace.shared.open(Paths.vault) }.buttonStyle(.bordered)
            }
        } else if app.vault.annotations.isEmpty {
            SurfaceState(line: "Select text on any page and press ⌘D.", symbol: "bookmark")
        } else {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    FilterField(placeholder: "Search saved items", text: $filter).padding(ShellLayout.windowGap)
                    VStack(alignment: .leading, spacing: ShellLayout.windowGap) {
                        Picker("Kind", selection: $kind) { ForEach(["All", "Highlights", "Pages"], id: \.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden()
                        HStack {
                            Picker("Site", selection: $site) {
                                Text("All sites").tag("")
                                ForEach(Array(Set(app.vault.annotations.compactMap { URL(string: $0.url)?.host })).sorted(), id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().fixedSize()
                            Spacer()
                            Toggle("Current space only", isOn: $currentSpaceOnly).toggleStyle(.checkbox)
                        }
                    }.font(ShellType.secondary).controlSize(.small).padding(.horizontal, ShellLayout.windowGap).padding(.bottom, ShellLayout.windowGap)
                    Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: ShellLayout.windowGap)], spacing: ShellLayout.windowGap) {
                            ForEach(annotations) { ann in VaultTile(annotation: ann, selected: selected?.id == ann.id) }
                            if annotations.isEmpty {
                                Text("No matching items").font(ShellType.secondary).foregroundStyle(app.pal.ink3).padding(24)
                            }
                        }.padding(ShellLayout.windowGap)
                    }
                }.frame(minWidth: 250, idealWidth: 390, maxWidth: 420)
                Rectangle().fill(app.pal.hairline).frame(width: ShellLayout.hairline)
                if let selected {
                    NoteDetail(annotation: selected, note: draftBinding(for: selected), onSave: { save(selected) })
                        .id(selected.id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(ShellType.title).foregroundStyle(app.pal.ink3)
                        Text("No saved items match this search").font(ShellType.row).foregroundStyle(app.pal.ink2)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func askNotes() {
        app.attachedSources = annotations.prefix(4).map { KnowledgeSource(id: $0.id, title: $0.title, url: $0.url, text: $0.text + "\n" + $0.note, kind: "Vault note") }
        app.knowledgeSearchPresented = true; app.show(.web)
    }

    private func draftBinding(for annotation: Annotation) -> Binding<String> {
        Binding(
            get: {
                app.noteDrafts[annotation.id]
                    ?? app.vault.annotations.first(where: { $0.id == annotation.id })?.note
                    ?? annotation.note
            },
            set: { app.noteDrafts[annotation.id] = $0 }
        )
    }

    private func save(_ annotation: Annotation) {
        app.vault.update(annotation, note: draftBinding(for: annotation).wrappedValue)
        if app.vault.errorText == nil { app.noteDrafts.removeValue(forKey: annotation.id) }
        app.notify(app.vault.errorText == nil ? "Note updated" : "Couldn’t save note")
    }

    private func delete(_ annotation: Annotation) {
        app.vault.delete(annotation)
        guard !app.vault.annotations.contains(where: { $0.id == annotation.id }) else { return }
        app.noteDrafts.removeValue(forKey: annotation.id)
        if selectedID == annotation.id { app.vaultSelectionID = nil }
    }
}

/// A Vault grid tile: `tileFill` with `rowRadius`, `fillSelected` plus its stroke when selected.
private struct VaultTile: View {
    let annotation: Annotation
    let selected: Bool
    @EnvironmentObject var app: AppState
    @State private var hovering = false
    private var host: String? { URL(string: annotation.url)?.host }
    var body: some View {
        Button { app.vaultSelectionID = annotation.id } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: ShellLayout.rowInsetLeading) {
                    Favicon(host: host, size: ShellLayout.iconSize)
                    Text(annotation.title).font(ShellType.rowSelected).foregroundStyle(app.pal.ink).lineLimit(1)
                }
                if !annotation.text.isEmpty {
                    Text(annotation.text).font(ShellType.secondary).foregroundStyle(app.pal.ink2).lineLimit(2).multilineTextAlignment(.leading)
                } else if !annotation.note.isEmpty {
                    Text(annotation.note).font(ShellType.secondary).foregroundStyle(app.pal.ink2).lineLimit(2).multilineTextAlignment(.leading)
                }
                HStack(spacing: 4) {
                    Text(host?.replacingOccurrences(of: "www.", with: "") ?? "Saved note").lineLimit(1)
                    Spacer(minLength: 2)
                    Text(annotation.created.formatted(.dateTime.month(.abbreviated).day()))
                }.font(ShellType.caption).foregroundStyle(app.pal.ink3)
                Text(annotation.provenance ?? "Legacy note").font(ShellType.caption).foregroundStyle(app.pal.ink3)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? app.pal.fillSelected : (hovering ? app.pal.fillHover : app.pal.tileFill), in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                .overlay(RoundedRectangle(cornerRadius: ShellLayout.rowRadius).strokeBorder(selected ? app.pal.fillSelectedStroke : .clear, lineWidth: ShellLayout.hairline))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }.draggable("note:\(annotation.id)")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct NoteDetail: View {
    let annotation: Annotation
    @Binding var note: String
    let onSave: () -> Void
    @EnvironmentObject var app: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Label(annotation.created.formatted(.dateTime.month(.wide).day()), systemImage: "bookmark")
                    .font(ShellType.caption).foregroundStyle(app.pal.ink3).padding(.bottom, 8)
                Text(annotation.title).font(ShellType.title).fixedSize(horizontal: false, vertical: true)
                Text([annotation.provenance ?? "Legacy note", annotation.accountScope].compactMap { $0 }.joined(separator: " · "))
                    .font(ShellType.caption).foregroundStyle(app.pal.ink3).padding(.top, 4)
                Button { if let url = URL(string: annotation.url) { app.openTab(url: url, parent: nil, activate: true) } } label: {
                    HStack(spacing: 6) {
                        Favicon(host: URL(string: annotation.url)?.host, size: ShellLayout.iconSize)
                        Text(URL(string: annotation.url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Open original").lineLimit(1)
                        Image(systemName: "arrow.up.right").font(ShellType.glyphMini)
                    }.font(ShellType.secondary).foregroundStyle(app.pal.ink2)
                }.buttonStyle(.plain).padding(.top, 10).padding(.bottom, 24).help("Open original page")
                if !annotation.text.isEmpty {
                    Text("Highlight").font(ShellType.label).foregroundStyle(app.pal.ink3).padding(.bottom, 10)
                    HStack(alignment: .top, spacing: 14) {
                        Rectangle().fill(app.pal.hairline).frame(width: 2)
                        Text(annotation.text).font(ShellType.row).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.fixedSize(horizontal: false, vertical: true).padding(.bottom, 24)
                }
                Text("Your note").font(ShellType.label).foregroundStyle(app.pal.ink3).padding(.bottom, 10)
                TextEditor(text: $note).font(ShellType.row).scrollContentBackground(.hidden).padding(10).frame(minHeight: 180)
                    .background(app.pal.tileFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                    .accessibilityLabel("Your note")
                HStack {
                    Text("Saved as Markdown on this Mac").font(ShellType.caption).foregroundStyle(app.pal.ink3)
                    Spacer()
                    Button("Save changes", action: onSave)
                        .buttonStyle(.bordered).controlSize(.small).disabled(note == annotation.note)
                }.padding(.top, 12)
            }.frame(maxWidth: 640, alignment: .leading).padding(24).frame(maxWidth: .infinity, alignment: .top)
        }
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
