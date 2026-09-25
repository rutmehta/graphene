import SwiftUI
import AppKit

/// The Vault shelf's rules (graphene-identity.md §3.5), kept apart from the view so they test
/// without a window.
enum VaultShelfLayout {
    /// Chips shown when the sidebar content is at least `narrowContentWidth` wide.
    static let maxChips = 4
    /// A chip never shrinks below this; the count is whatever fits between the "Vault" word and the trailing edge.
    static let minChipWidth: CGFloat = 72
    /// Width reserved for the "Vault" word and its gap.
    static let labelWidth: CGFloat = 36
    static let chipHeight: CGFloat = 32
    /// Gap between chips, and between a chip's favicon and its text.
    static let chipGap: CGFloat = 6
    /// Words of the quote a chip carries before it is cut with an ellipsis.
    static let chipWordLimit = 6
    /// Width of the hover card, as `TabPreview`.
    static let cardWidth: CGFloat = 260

    /// Shown only with notes in the current space, outside the archive view, in non-private windows.
    static func isVisible(hasNotes: Bool, archivePresented: Bool, isPrivate: Bool) -> Bool {
        hasNotes && !archivePresented && !isPrivate
    }

    static func chipCount(contentWidth: CGFloat) -> Int {
        let available = contentWidth - labelWidth + chipGap
        return min(maxChips, max(1, Int(available / (minChipWidth + chipGap))))
    }

    /// The full text a note shows: its quote, else its note, else its page title.
    static func fullText(_ note: Annotation) -> String {
        [note.text, note.note, note.title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? (URL(string: note.url)?.host ?? "")
    }

    /// The first words of `fullText` on one line: whitespace and newlines collapse to single
    /// spaces, and an ellipsis marks words left out.
    static func chipText(_ note: Annotation) -> String {
        let words = fullText(note).split(whereSeparator: \.isWhitespace)
        let head = words.prefix(chipWordLimit).joined(separator: " ")
        return words.count > chipWordLimit ? head + "…" : head
    }

    /// The passage handed to `openSource`: the trimmed quote, or nil for a page note.
    static func passage(_ note: Annotation) -> String? {
        let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Shelf motion (graphene-identity.md §4): height 0→44 easeOut 180ms with the chips fading;
/// Reduce Motion keeps only a 120ms fade.
enum ShelfMotion {
    static let reveal = Animation.easeOut(duration: 0.18)
    static let fade = Animation.easeOut(duration: 0.12)
}

extension AppState {
    var shelfVisible: Bool {
        VaultShelfLayout.isVisible(hasNotes: !vault.notes(inSpace: activeSpaceID, limit: 1).isEmpty,
                                   archivePresented: archivePresented, isPrivate: isPrivate)
    }

    /// The notes on the shelf for a sidebar of `contentWidth`, newest first.
    func shelfNotes(contentWidth: CGFloat) -> [Annotation] {
        guard shelfVisible else { return [] }
        return vault.notes(inSpace: activeSpaceID, limit: VaultShelfLayout.chipCount(contentWidth: contentWidth))
    }
}

/// The Vault shelf: a `shelfHeight` row above the sidebar footer holding the space's latest
/// saves as serif chips. It takes its height from the Today list rather than overlaying it,
/// and collapses to nothing when there is nothing to show.
struct VaultShelf: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the row holds its height.
    @State private var expanded = false
    /// Whether the row's content is drawn; it fades in and out.
    @State private var shown = false

    var body: some View {
        GeometryReader { geometry in
            if shown {
                row(contentWidth: ShellLayout.sidebarContentWidth(geometry.size.width))
                    .transition(.opacity)
            }
        }
        .frame(height: expanded ? ShellLayout.shelfHeight : 0)
        .clipped()
        .allowsHitTesting(expanded)
        .onAppear { expanded = app.shelfVisible; shown = expanded }
        .onChange(of: app.shelfVisible) { _, visible in animate(to: visible) }
    }

    private func row(contentWidth: CGFloat) -> some View {
        HStack(spacing: VaultShelfLayout.chipGap) {
            Text("Vault").font(ShellType.label).foregroundStyle(app.pal.ink3)
                .fixedSize().contentShape(Rectangle())
                .onTapGesture { app.show(.vault) }
                .help("Open Vault")
                .accessibilityAddTraits(.isButton).accessibilityLabel("Open Vault")
                .accessibilityIdentifier("sidebar.shelf.vault")
                .accessibilityAction { app.show(.vault) }
            ForEach(app.shelfNotes(contentWidth: contentWidth)) { note in
                ShelfChip(note: note)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, ShellLayout.windowGap)
            .frame(height: ShellLayout.shelfHeight)
            .accessibilityElement(children: .contain).accessibilityLabel("Vault shelf")
            .accessibilityIdentifier("sidebar.shelf")
    }

    private func animate(to visible: Bool) {
        guard reduceMotion else {
            withAnimation(ShelfMotion.reveal) { expanded = visible; shown = visible }
            return
        }
        if visible {
            expanded = true
            withAnimation(ShelfMotion.fade) { shown = true }
        } else {
            withAnimation(ShelfMotion.fade) { shown = false } completion: {
                if !app.shelfVisible { expanded = false }
            }
        }
    }
}

/// One saved note: favicon and the quote's first words on `fill`. Click opens the source at
/// the passage, hover shows the whole quote, and dragging hands out the note
/// as its `note:<uuid>` reference for chat and the Board and as Markdown for other apps.
private struct ShelfChip: View {
    let note: Annotation
    @EnvironmentObject var app: AppState
    @State private var hovered = false
    @State private var previewTask: Task<Void, Never>?
    @State private var previewShown = false
    private var host: String? { URL(string: note.url)?.host }

    var body: some View {
        HStack(spacing: VaultShelfLayout.chipGap) {
            Favicon(host: host, size: ShellLayout.iconSize)
            Text(VaultShelfLayout.chipText(note)).font(ShellType.quoteSmall).foregroundStyle(app.pal.ink2)
                .lineLimit(1).truncationMode(.tail)
        }.padding(.horizontal, ShellLayout.rowInsetLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: VaultShelfLayout.chipHeight)
            .background(hovered ? app.pal.fillHover : app.pal.fill, in: RoundedRectangle(cornerRadius: ShellLayout.shelfChipRadius))
            .contentShape(RoundedRectangle(cornerRadius: ShellLayout.shelfChipRadius))
            .frame(minWidth: VaultShelfLayout.minChipWidth, maxWidth: ShellLayout.shelfChipWidth)
            .animation(SidebarMotion.hover, value: hovered)
            .onTapGesture { open() }
            .onHover { inside in
                hovered = inside
                previewTask?.cancel()
                if inside {
                    previewTask = Task { try? await Task.sleep(for: .milliseconds(600)); if !Task.isCancelled { previewShown = true } }
                } else { previewShown = false }
            }
            .popover(isPresented: $previewShown, arrowEdge: .top) { ShelfQuoteCard(note: note).environmentObject(app) }
            .onDisappear { previewTask?.cancel(); previewShown = false }
            .onDrag { NoteDrag.itemProvider(for: note) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(VaultShelfLayout.fullText(note))
            .accessibilityHint("Opens the source page")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("sidebar.shelf.chip.\(note.id)")
            .accessibilityAction { open() }
    }

    private func open() {
        previewTask?.cancel(); previewShown = false
        if let url = URL(string: note.url), url.scheme != nil {
            app.openSource(url: url, passage: VaultShelfLayout.passage(note))
        } else {
            app.vaultSelectionID = note.id
            app.show(.vault)
        }
    }
}

/// The hover card: the whole quote in serif with its source beneath, styled as `TabPreview`.
private struct ShelfQuoteCard: View {
    let note: Annotation
    @EnvironmentObject var app: AppState
    private var host: String? { URL(string: note.url)?.host }

    var body: some View {
        VStack(alignment: .leading, spacing: ShellLayout.windowGap) {
            Text(VaultShelfLayout.fullText(note)).font(ShellType.quoteSmall).foregroundStyle(app.pal.ink)
                .lineSpacing(ShellType.rowLineSpacing).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: VaultShelfLayout.chipGap) {
                Favicon(host: host, size: ShellLayout.iconSize)
                Text(note.title.isEmpty ? (host ?? "Saved note") : note.title)
                    .font(ShellType.caption).foregroundStyle(app.pal.ink3).lineLimit(1)
            }
        }.padding(ShellLayout.sectionGap)
            .frame(width: VaultShelfLayout.cardWidth, alignment: .leading)
            .background(app.pal.elev, in: RoundedRectangle(cornerRadius: ShellLayout.popoverRadius))
            .overlay(RoundedRectangle(cornerRadius: ShellLayout.popoverRadius).strokeBorder(app.pal.hairline, lineWidth: ShellLayout.hairline))
            .shadow(color: app.pal.pageShadow, radius: app.pal.pageShadowRadius, y: app.pal.pageShadowY)
    }
}
