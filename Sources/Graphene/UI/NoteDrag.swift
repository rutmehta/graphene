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
        let reference = Data(reference(note.id).utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.grapheneNoteReference.identifier, visibility: .all) { @Sendable completion in
            completion(reference, nil); return nil
        }
        provider.registerObject(Vault.markdown(for: note) as NSString, visibility: .all)
        return provider
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
    var title: String
    var text: String = ""
    var url: String? = nil
}

extension AppState {
    /// The Board card for a dropped value: a tab link, a Vault card, a web link, or a text note.
    /// Nil for a reference to a tab or note that no longer exists.
    func boardDropCard(for value: String) -> BoardDropCard? {
        if let id = payloadID(value, prefix: "tab:") {
            guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
            return BoardDropCard(title: tab.displayTitle, url: tab.url?.absoluteString)
        }
        if let id = payloadID(value, prefix: "note:") {
            guard let note = vault.annotations.first(where: { $0.id == id }) else { return nil }
            return BoardDropCard(title: note.title, text: note.text + "\n" + note.note, url: note.url)
        }
        if let url = URL(string: value), ["http", "https"].contains(url.scheme ?? "") {
            return BoardDropCard(title: url.host ?? value, url: value)
        }
        return BoardDropCard(title: "Note", text: value)
    }
}
