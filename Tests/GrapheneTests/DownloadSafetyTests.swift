import XCTest
@testable import Graphene

final class DownloadSafetyTests: XCTestCase {
    @MainActor
    func testUnreadableHistoryIsNotOverwrittenByLaterMutations() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("downloads.json")
        let original = Data("{incomplete download history".utf8)
        try original.write(to: file)

        let store = DownloadStore(file: file)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.errorText)
        let id = store.begin(root.appendingPathComponent("report.pdf"))
        store.finish(id, error: nil)
        store.clear()

        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertNotNil(store.errorText)
    }

    @MainActor
    func testRenameMovesContentsAndPersistsDestinationAndProvenance() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("downloads.json")
        let old = root.appendingPathComponent("original.pdf")
        let new = root.appendingPathComponent("report.pdf")
        let contents = Data("download contents".utf8)
        try contents.write(to: old)
        let source = try XCTUnwrap(URL(string: "https://example.org/original.pdf"))
        let profileID = UUID()
        let store = DownloadStore(file: file)
        let id = store.begin(old, sourceURL: source, profileID: profileID)
        store.finish(id, error: nil)

        try store.rename(id, to: new.lastPathComponent)

        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try Data(contentsOf: new), contents)
        XCTAssertEqual(store.entries.first?.destination, new)
        let restored = try XCTUnwrap(DownloadStore(file: file).entries.first)
        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.destination, new)
        XCTAssertEqual(restored.status, .finished)
        XCTAssertEqual(restored.sourceURL, source)
        XCTAssertEqual(restored.profileID, profileID)
    }

    @MainActor
    func testUnsafeAndCollidingRenamesLeaveFilesAndHistoryUntouched() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("downloads.json")
        let old = root.appendingPathComponent("original.pdf")
        let occupied = root.appendingPathComponent("existing.pdf")
        let contents = Data("original download".utf8)
        let otherContents = Data("another download".utf8)
        try contents.write(to: old)
        try otherContents.write(to: occupied)
        let store = DownloadStore(file: file)
        let id = store.begin(old)
        store.finish(id, error: nil)
        let history = try Data(contentsOf: file)

        for name in ["../escaped.pdf", "folder/report.pdf", "folder\\report.pdf", ".hidden.pdf", "report.txt", "existing.pdf"] {
            XCTAssertThrowsError(try store.rename(id, to: name), name)
            XCTAssertEqual(store.entries.first?.destination, old, name)
            XCTAssertEqual(try Data(contentsOf: old), contents, name)
            XCTAssertEqual(try Data(contentsOf: occupied), otherContents, name)
            XCTAssertEqual(try Data(contentsOf: file), history, name)
        }
    }

    @MainActor
    func testRenameRequiresFinishedDownloadAndSuccessfulFileMove() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("downloads.json")
        let old = root.appendingPathComponent("original.pdf")
        let new = root.appendingPathComponent("report.pdf")
        let contents = Data("partial download".utf8)
        try contents.write(to: old)
        let store = DownloadStore(file: file)
        let id = store.begin(old)

        for error in [nil, "Network interrupted"] as [String?] {
            if let error { store.finish(id, error: error) }
            let history = try Data(contentsOf: file)
            XCTAssertThrowsError(try store.rename(id, to: new.lastPathComponent))
            XCTAssertEqual(try Data(contentsOf: old), contents)
            XCTAssertEqual(try Data(contentsOf: file), history)
        }

        store.finish(id, error: nil)
        try FileManager.default.removeItem(at: old)
        let history = try Data(contentsOf: file)
        XCTAssertThrowsError(try store.rename(id, to: new.lastPathComponent))
        XCTAssertEqual(store.entries.first?.destination, old)
        XCTAssertEqual(try Data(contentsOf: file), history)
        XCTAssertFalse(FileManager.default.fileExists(atPath: new.path))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
