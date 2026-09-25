import XCTest
@testable import Graphene

/// G5 (graphene-identity.md §3.5): the Vault shelf above the sidebar footer.
@MainActor
final class VaultShelfTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func save(_ app: AppState, _ text: String, url: String = "https://example.com/a", space: UUID? = nil) {
        app.vault.add(text: text, note: "", url: URL(string: url), title: "Example", context: "", spaceID: space ?? app.activeSpaceID)
    }

    func testTokens() {
        XCTAssertEqual(ShellLayout.shelfHeight, 44)
        XCTAssertEqual(ShellLayout.shelfChipWidth, 96)
        XCTAssertEqual(ShellLayout.shelfChipRadius, 8)
        XCTAssertEqual(VaultShelfLayout.chipHeight, 32)
    }

    func testVisibilityRules() {
        XCTAssertTrue(VaultShelfLayout.isVisible(hasNotes: true, archivePresented: false, isPrivate: false))
        XCTAssertFalse(VaultShelfLayout.isVisible(hasNotes: false, archivePresented: false, isPrivate: false))
        XCTAssertFalse(VaultShelfLayout.isVisible(hasNotes: true, archivePresented: true, isPrivate: false))
        XCTAssertFalse(VaultShelfLayout.isVisible(hasNotes: true, archivePresented: false, isPrivate: true))
    }

    func testShelfFollowsTheCurrentSpacesNotesAndTheArchive() {
        let app = AppState(directory: root)
        XCTAssertFalse(app.shelfVisible, "No notes: no shelf")
        save(app, "Saved elsewhere", space: UUID())
        XCTAssertFalse(app.shelfVisible, "Notes in another space don't show")
        save(app, "Strongest material ever measured")
        XCTAssertTrue(app.shelfVisible)
        app.archivePresented = true
        XCTAssertFalse(app.shelfVisible, "Hidden while the archive view is open")
        XCTAssertTrue(app.shelfNotes(contentWidth: 208).isEmpty)
        app.archivePresented = false
        for note in app.vault.notes(inSpace: app.activeSpaceID) { app.vault.delete(note) }
        XCTAssertFalse(app.shelfVisible, "Deleting the space's notes removes the shelf")
    }

    func testPrivateWindowHasNoShelf() {
        let owner = AppState(directory: root)
        save(owner, "A public note")
        let privateApp = AppState(directory: root, sharing: owner, privateMode: true)
        privateApp.activeSpaceID = owner.activeSpaceID
        XCTAssertFalse(privateApp.shelfVisible)
        XCTAssertTrue(privateApp.shelfNotes(contentWidth: 300).isEmpty)
    }

    func testChipCountByWidth() {
        XCTAssertEqual(VaultShelfLayout.chipCount(contentWidth: ShellLayout.sidebarContentWidth(ShellLayout.sidebarDefault)), 4)
        XCTAssertEqual(VaultShelfLayout.chipCount(contentWidth: 208), 4)
        XCTAssertEqual(VaultShelfLayout.chipCount(contentWidth: 207.5), 3)
        XCTAssertEqual(VaultShelfLayout.chipCount(contentWidth: ShellLayout.sidebarContentWidth(ShellLayout.sidebarRange.lowerBound)), 3)

        let app = AppState(directory: root)
        for index in 1...5 { save(app, "Quote \(index)") }
        XCTAssertEqual(app.shelfNotes(contentWidth: 300).count, 4)
        XCTAssertEqual(app.shelfNotes(contentWidth: 180).count, 3)
    }

    func testNotesAreNewestFirstAndScopedToTheSpace() {
        let app = AppState(directory: root)
        let other = UUID()
        save(app, "First")
        save(app, "Other space", space: other)
        save(app, "Second")
        save(app, "Third")
        XCTAssertEqual(app.vault.notes(inSpace: app.activeSpaceID).map(\.text), ["Third", "Second", "First"])
        XCTAssertEqual(app.vault.notes(inSpace: app.activeSpaceID, limit: 2).map(\.text), ["Third", "Second"])
        XCTAssertEqual(app.vault.notes(inSpace: other).map(\.text), ["Other space"])
        XCTAssertTrue(app.vault.notes(inSpace: app.activeSpaceID, limit: 0).isEmpty)
        XCTAssertEqual(app.shelfNotes(contentWidth: 300).map(\.text), ["Third", "Second", "First"])
    }

    func testChipTextTrimming() {
        func note(_ text: String, note: String = "", title: String = "Title") -> Annotation {
            Annotation(id: UUID(), text: text, note: note, url: "https://example.com", title: title, context: "", created: Date(), spaceID: nil)
        }
        XCTAssertEqual(VaultShelfLayout.chipText(note("  single\n atomic\tlayer  ")), "single atomic layer")
        XCTAssertEqual(VaultShelfLayout.chipText(note("one two three four five six seven eight")), "one two three four five six…")
        XCTAssertEqual(VaultShelfLayout.chipText(note("one two three four five six")), "one two three four five six")
        XCTAssertEqual(VaultShelfLayout.chipText(note(" \n ", note: "My own words")), "My own words", "A page note falls back to the note")
        XCTAssertEqual(VaultShelfLayout.chipText(note("", title: "Page title")), "Page title")
        XCTAssertEqual(VaultShelfLayout.fullText(note("\n A long quote kept whole  \n")), "A long quote kept whole")
        XCTAssertEqual(VaultShelfLayout.passage(note("  quote  ")), "quote")
        XCTAssertNil(VaultShelfLayout.passage(note(" \n", note: "just a note")))
    }

    func testMarkdownPayloadMatchesTheNoteFile() throws {
        let app = AppState(directory: root)
        app.vault.add(text: "line one\nline two", note: "My thought", url: URL(string: "https://example.com/page"), title: "Example page", context: "", spaceID: app.activeSpaceID)
        let note = try XCTUnwrap(app.vault.notes(inSpace: app.activeSpaceID).first)
        let markdown = Vault.markdown(for: note)
        XCTAssertTrue(markdown.hasPrefix("# Example page\n\n> line one\n> line two\n\nMy thought\n\n[Source](https://example.com/page)\n\nSaved "))
        let file = root.appendingPathComponent("notes").appendingPathComponent("\(note.id.uuidString).md")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), markdown, "The dragged Markdown is the note's file")
    }

    func testShelfIsOneInsertionAboveTheFooterAndUsesTokens() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Graphene/UI")
        let sidebar = try String(contentsOf: sources.appendingPathComponent("Sidebar.swift"), encoding: .utf8)
        XCTAssertTrue(sidebar.contains("VaultShelf()\n            SidebarFooter("))
        let shelf = try String(contentsOf: sources.appendingPathComponent("VaultShelf.swift"), encoding: .utf8)
        for pattern in [#"\.font\(\.system\(size:"#, #"cornerRadius:\s*[0-9]"#, #"\.opacity\("#, #"Color\(hex:"#] {
            XCTAssertNil(shelf.range(of: pattern, options: .regularExpression), "VaultShelf.swift has a literal matching \(pattern)")
        }
    }
}
