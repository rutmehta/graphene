import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension UTType {
    /// A Graphene note reference, `note:<uuid>`. Declared in the app's Info.plist.
    static let grapheneNoteReference = UTType(exportedAs: "com.graphene.browser.note-reference", conformingTo: .data)
}

/// What a dragged Vault note carries: the `note:<uuid>` reference for Graphene's own drop
/// targets (chat, Board) and the note as Markdown plain text for every other app.
@MainActor
enum NoteDrag {
    nonisolated static func reference(_ id: UUID) -> String { "note:\(id)" }

    static func itemProvider(for note: Annotation) -> NSItemProvider {
        let provider = NSItemProvider()
        register(Data(reference(note.id).utf8), on: provider)
        provider.registerObject(Vault.markdown(for: note) as NSString, visibility: .all)
        return provider
    }
}

/// Registers the note reference outside the main actor, so its loader runs wherever the drop
/// target asks for the data.
private func register(_ reference: Data, on provider: NSItemProvider) {
    provider.registerDataRepresentation(forTypeIdentifier: UTType.grapheneNoteReference.identifier, visibility: .all) { @Sendable completion in
        completion(reference, nil); return nil
    }
}

/// Text arriving at an in-app drop target: the note reference when the drag carries one,
/// else the dragged plain text (`tab:<uuid>`, `note:<uuid>` from `.draggable`, a URL, prose).
struct DroppedText: Transferable {
    let value: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .grapheneNoteReference) { data in
            DroppedText(value: String(decoding: data, as: UTF8.self))
        }
        ProxyRepresentation(importing: { (text: String) in DroppedText(value: text) })
    }
}

/// A card the Board makes from a dropped string.
struct BoardDropCard: Equatable {
    var kind: BoardCardKind = .note
    var title: String
    var text: String = ""
    var url: String? = nil
    /// The clipped page text of a quote card.
    var quote: String? = nil
}

extension AppState {
    /// The Board card for a dropped value: a sidebar tab or web link makes a page card, a Vault
    /// note (shelf chip or list row) a quote card, anything else a note card. Nil for a
    /// reference to a tab or note that no longer exists.
    func boardDropCard(for value: String) -> BoardDropCard? {
        if let id = payloadID(value, prefix: "tab:") {
            guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
            guard let url = tab.url?.absoluteString else { return BoardDropCard(kind: .note, title: tab.displayTitle) }
            return BoardDropCard(kind: .page, title: tab.displayTitle, url: url)
        }
        if let id = payloadID(value, prefix: "note:") {
            guard let note = vault.annotations.first(where: { $0.id == id }) else { return nil }
            let url = note.url.isEmpty ? nil : note.url
            if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return BoardDropCard(kind: .note, title: note.title, text: note.note, url: url)
            }
            return BoardDropCard(kind: .quote, title: note.title, text: note.note, url: url, quote: note.text)
        }
        if let url = URL(string: value), ["http", "https"].contains(url.scheme ?? "") {
            return BoardDropCard(kind: .page, title: url.host ?? value, url: value)
        }
        return BoardDropCard(kind: .note, title: "Note", text: value)
    }
}
