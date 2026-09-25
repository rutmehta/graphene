import XCTest
import UniformTypeIdentifiers
@testable import Graphene

/// Shelf chips drop into chat and the Board (graphene-identity.md §3.5), and a mark hovered in
/// the page scrolls its chip into view (§3.4).
@MainActor
final class NoteDragTests: XCTestCase {
    private var root: URL!
    private var app: AppState!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        app = AppState(directory: root)
        app.vault.add(text: "Saved quote", note: "My note", url: URL(string: "https://example.org/a"), title: "Example", context: "", spaceID: app.activeSpaceID)
    }

    override func tearDown() async throws {
        app = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func load(_ provider: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: DroppedText.self) { continuation.resume(with: $0.map(\.value)) }
        }
    }

    private func loadData(_ provider: NSItemProvider, type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }

    func testShelfDragCarriesTheReferenceAndMarkdown() async throws {
        let note = try XCTUnwrap(app.vault.annotations.first)
        let provider = NoteDrag.itemProvider(for: note)
        XCTAssertEqual(provider.registeredTypeIdentifiers.first, UTType.grapheneNoteReference.identifier, "in-app targets find the reference first")
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier), "other apps get plain text")
        let reference = try await loadData(provider, type: .grapheneNoteReference)
        XCTAssertEqual(String(decoding: reference, as: UTF8.self), "note:\(note.id)")
        let markdown = try await loadData(provider, type: .utf8PlainText)
        XCTAssertEqual(String(decoding: markdown, as: UTF8.self), Vault.markdown(for: note))
    }

    func testDropTargetsReadTheReferenceBeforeThePlainText() async throws {
        let note = try XCTUnwrap(app.vault.annotations.first)
        let fromShelf = try await load(NoteDrag.itemProvider(for: note))
        XCTAssertEqual(fromShelf, "note:\(note.id)")
        // The Vault list's `.draggable` string and other plain text still arrive as they are.
        let fromList = try await load(NSItemProvider(object: NoteDrag.reference(note.id) as NSString))
        XCTAssertEqual(fromList, "note:\(note.id)")
        let prose = try await load(NSItemProvider(object: "Some text" as NSString))
        XCTAssertEqual(prose, "Some text")
    }

    func testChatAttachesTheDroppedNote() async throws {
        let note = try XCTUnwrap(app.vault.annotations.first)
        let value = try await load(NoteDrag.itemProvider(for: note))
        let sources = app.noteDropSources([value])
        XCTAssertEqual(sources.map(\.id), [note.id])
        XCTAssertEqual(sources.first?.text, "Saved quote\n\nMy note")
        XCTAssertTrue(app.noteDropSources([Vault.markdown(for: note)]).isEmpty, "Markdown alone is not a note reference")
    }

    func testBoardMakesAVaultCardFromTheDroppedNote() async throws {
        let note = try XCTUnwrap(app.vault.annotations.first)
        let value = try await load(NoteDrag.itemProvider(for: note))
        XCTAssertEqual(app.boardDropCard(for: value), BoardDropCard(kind: .quote, title: "Example", text: "My note", url: "https://example.org/a", quote: "Saved quote"))
        XCTAssertNil(app.boardDropCard(for: "note:\(UUID())"), "a deleted note makes no card")
        let tab = app.newTab()
        XCTAssertEqual(app.boardDropCard(for: "tab:\(tab.id)"), BoardDropCard(kind: tab.url == nil ? .note : .page, title: tab.displayTitle, url: tab.url?.absoluteString))
        XCTAssertEqual(app.boardDropCard(for: "https://swift.org/blog"), BoardDropCard(kind: .page, title: "swift.org", url: "https://swift.org/blog"))
        XCTAssertEqual(app.boardDropCard(for: "Loose words"), BoardDropCard(kind: .note, title: "Note", text: "Loose words"))
    }

    func testOnlyMarkHoversAskTheTranscriptToScroll() async {
        let tab = UUID(), message = UUID()
        let source = KnowledgeSource(id: tab, title: "Page", url: "https://example.com/page", text: "Alpha is first.", kind: "Tab")
        let citations = ChatCitation.assign(answer: "Alpha is first [1].", sources: [source], messageID: message)
        let id = citations[0].citationID
        let linker = CitationLinker()
        let page = CitationPage(highlight: { $0.map(\.id) }, setActive: { _ in }, scroll: { _ in }, clear: {})
        await linker.link(messageID: message, citations: citations, sources: [source], tabID: tab, url: URL(string: source.url), page: page)
        var raised: [String] = []
        let subscription = linker.markRaised.sink { raised.append($0) }
        linker.hoverChip(id)
        linker.markHovered(id, tabID: UUID())
        linker.markHovered("not-linked", tabID: tab)
        linker.markHovered(nil, tabID: tab)
        XCTAssertEqual(raised, [])
        linker.markHovered(id, tabID: tab)
        XCTAssertEqual(raised, [id])
        subscription.cancel()
    }
}
