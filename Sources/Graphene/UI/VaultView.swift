import SwiftUI
import AppKit

struct VaultView: View {
    @EnvironmentObject var app: AppState
    @State private var filter = ""
    @State private var currentSpaceOnly = false
    @State private var kind = "All"
    @State private var site = ""
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
            if let error = app.vault.errorText {
                Text("Couldn’t save: \(error)").font(.system(size: 12)).foregroundStyle(app.pal.ink2)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            content
        }
    }

    @ViewBuilder private var content: some View {
        if let error = app.vault.errorText, app.vault.annotations.isEmpty {
            SurfaceState(symbol: "exclamationmark.triangle", title: "Vault unavailable", detail: error) {
                Button("Open vault folder") { NSWorkspace.shared.open(Paths.vault) }.buttonStyle(.bordered)
            }
        } else if app.vault.annotations.isEmpty {
            SurfaceState(symbol: "bookmark", title: "No saved pages yet", detail: "Select text on a page to save a highlight, or press ⌘D to save the page with a note.") {
                HStack(spacing: 12) {
                    Button("Start browsing") { app.newTab() }.buttonStyle(.bordered)
                    Button("Open vault folder") { NSWorkspace.shared.open(Paths.vault) }.buttonStyle(.bordered)
                }
            }
        } else {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Vault").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text("\(app.vault.annotations.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(app.pal.ink3)
                    }.padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 18)
                    FilterField(placeholder: "Search saved items", text: $filter).padding(.horizontal, 12).padding(.bottom, 12)
                    VStack(spacing: 10) {
                        Toggle("Current space only", isOn: $currentSpaceOnly)
                        Picker("Kind", selection: $kind) { ForEach(["All", "Highlights", "Pages"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                        Picker("Site", selection: $site) {
                            Text("All sites").tag("")
                            ForEach(Array(Set(app.vault.annotations.compactMap { URL(string: $0.url)?.host })).sorted(), id: \.self) { Text($0).tag($0) }
                        }
                        Button("Ask my notes") {
                            app.attachedSources = annotations.prefix(4).map { KnowledgeSource(id: $0.id, title: $0.title, url: $0.url, text: $0.text + "\n" + $0.note, kind: "Vault note") }
                            app.knowledgeSearchPresented = true; app.show(.web)
                        }
                    }.font(.system(size: 12)).padding(.horizontal, 14).padding(.bottom, 14)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                            ForEach(annotations) { ann in
                                Button { app.vaultSelectionID = ann.id } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack(spacing: 7) {
                                            Favicon(host: URL(string: ann.url)?.host, size: 14)
                                            Text(ann.title).font(.system(size: 12, weight: .medium)).foregroundStyle(app.pal.ink).lineLimit(1)
                                        }
                                        if !ann.text.isEmpty {
                                            Text(ann.text).font(.system(size: 11)).foregroundStyle(app.pal.ink2).lineLimit(2).multilineTextAlignment(.leading)
                                        } else if !ann.note.isEmpty {
                                            Text(ann.note).font(.system(size: 11)).foregroundStyle(app.pal.ink2).lineLimit(2).multilineTextAlignment(.leading)
                                        }
                                        HStack(spacing: 5) {
                                            Text(URL(string: ann.url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Saved note").lineLimit(1)
                                            Spacer(minLength: 2)
                                            Text(ann.created.formatted(.dateTime.month(.abbreviated).day()))
                                        }.font(.system(size: 10)).foregroundStyle(app.pal.ink3)
                                        Text(ann.provenance ?? "Legacy note").font(.system(size: 10)).foregroundStyle(app.pal.ink3)
                                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selected?.id == ann.id ? app.pal.hover : app.pal.elev, in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(app.pal.hairline))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).draggable("note:\(ann.id)")
                            }
                            if annotations.isEmpty {
                                Text("No matching items").font(.system(size: 12)).foregroundStyle(app.pal.ink3).padding(24)
                            }
                        }.padding(.horizontal, 8)
                    }
                    Button { NSWorkspace.shared.open(Paths.vault) } label: {
                        Label("Open vault folder", systemImage: "folder").font(.system(size: 11)).foregroundStyle(app.pal.ink2)
                    }.buttonStyle(.plain).padding(18)
                }.frame(minWidth: 250, idealWidth: 390, maxWidth: 420).background(app.pal.hover.opacity(0.25))
                Rectangle().fill(app.pal.hairline).frame(width: 1)
                if let selected {
                    NoteDetail(annotation: selected, note: draftBinding(for: selected),
                               onSave: { save(selected) }, onDelete: { delete(selected) })
                        .id(selected.id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 24)).foregroundStyle(app.pal.ink3)
                        Text("No saved items match this search").font(.system(size: 13)).foregroundStyle(app.pal.ink2)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
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

private struct NoteDetail: View {
    let annotation: Annotation
    @Binding var note: String
    let onSave: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var app: AppState
    @State private var deleting = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(annotation.created.formatted(.dateTime.month(.wide).day()), systemImage: "bookmark")
                        .font(.system(size: 11)).foregroundStyle(app.pal.ink3)
                    Spacer()
                    IconButton("Delete note", system: "trash") { deleting = true }
                }.padding(.bottom, 14)
                Text(annotation.title).font(.system(size: 22, weight: .semibold)).tracking(-0.35).fixedSize(horizontal: false, vertical: true)
                Text([annotation.provenance ?? "Legacy note", annotation.accountScope].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(app.pal.ink3).padding(.top, 8)
                Button { if let url = URL(string: annotation.url) { app.openTab(url: url, parent: nil, activate: true) } } label: {
                    HStack(spacing: 6) {
                        Favicon(host: URL(string: annotation.url)?.host, size: 14)
                        Text(URL(string: annotation.url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Open original").lineLimit(1)
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium))
                    }.font(.system(size: 11)).foregroundStyle(app.pal.ink2)
                }.buttonStyle(.plain).padding(.top, 10).padding(.bottom, 30).help("Open original page")
                if !annotation.text.isEmpty {
                    Text("Highlight").font(.system(size: 12, weight: .semibold)).padding(.bottom, 12)
                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: 1).fill(app.pal.ink3.opacity(0.45)).frame(width: 2)
                        Text(annotation.text).font(.system(size: 14)).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.fixedSize(horizontal: false, vertical: true).padding(.bottom, 30)
                }
                Text("Your note").font(.system(size: 12, weight: .semibold)).padding(.bottom, 12)
                TextEditor(text: $note).font(.system(size: 13)).scrollContentBackground(.hidden).padding(10).frame(minHeight: 180)
                    .background(app.pal.hover.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(app.pal.hairline.opacity(0.65)))
                    .accessibilityLabel("Your note")
                HStack {
                    Text("Saved as Markdown on this Mac").font(.system(size: 10)).foregroundStyle(app.pal.ink3)
                    Spacer()
                    Button("Save changes", action: onSave)
                        .buttonStyle(.bordered).controlSize(.small).disabled(note == annotation.note)
                }.padding(.top, 14)
            }.frame(maxWidth: 640, alignment: .leading).padding(28).frame(maxWidth: .infinity, alignment: .top)
        }
        .confirmationDialog("Delete this saved note?", isPresented: $deleting) {
            Button("Delete note", role: .destructive, action: onDelete)
        } message: { Text("The note and its Markdown file will be removed. Your browsing history is kept.") }
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
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Save to Vault").font(.system(size: 18, weight: .semibold))
                Spacer()
                IconButton("Cancel", system: "xmark") { dismiss() }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(sourceTitle.isEmpty ? "Current page" : sourceTitle).font(.system(size: 13, weight: .medium))
                Text(sourceURL?.host ?? "No page selected").font(.system(size: 11)).foregroundStyle(app.pal.ink3)
            }
            if !quote.isEmpty {
                Text(quote).font(.system(size: 13)).lineSpacing(3).lineLimit(5).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(app.pal.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Add a note").font(.system(size: 12, weight: .medium))
            TextEditor(text: $note).font(.system(size: 13)).focused($focused).scrollContentBackground(.hidden).padding(10).frame(height: 140)
                .background(app.pal.hover, in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Add a note")
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
            if let error = app.vault.errorText { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
        }.padding(24).frame(width: 480).background(app.pal.ground)
        .task {
            guard let tab = app.activeTab else { return }
            sourceURL = tab.url; sourceTitle = tab.displayTitle
            quote = (await tab.engine.evaluateJavaScript("String(window.getSelection() || '')")) as? String ?? ""
            focused = true
        }
    }
}
