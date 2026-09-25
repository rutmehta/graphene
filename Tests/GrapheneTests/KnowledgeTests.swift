import XCTest
@testable import Graphene

final class KnowledgeTests: XCTestCase {
    @MainActor
    func testBranchingRevisitAndPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("graph.json")
        let graph = KnowledgeGraph(file: file)
        let space = UUID(), otherSpace = UUID(), time = Date(timeIntervalSince1970: 100_000)
        let root = graph.recordVisit(url: URL(string: "https://example.com/search?q=research")!, title: "Research", spaceID: space, parentNodeID: nil, query: "research", date: time)
        let child = graph.recordVisit(url: URL(string: "https://example.com/article")!, title: "Article", spaceID: space, parentNodeID: root, query: nil, date: time.addingTimeInterval(60))
        graph.attachText(nodeID: child, text: "The important passage lives inside this source.")
        _ = graph.recordVisit(url: URL(string: "https://example.com/branch")!, title: "Branch", spaceID: space, parentNodeID: root, query: nil, date: time.addingTimeInterval(90))
        let originalID = graph.threads(spaceID: space).first!.id
        XCTAssertEqual(graph.threads(spaceID: space).first?.nodes.count, 3)
        _ = graph.recordVisit(url: URL(string: "https://example.com/article")!, title: "Article", spaceID: space, parentNodeID: nil, query: nil, date: time.addingTimeInterval(3600))
        XCTAssertEqual(graph.threads(spaceID: space).count, 2)
        XCTAssertEqual(graph.threads(spaceID: space).last?.id, originalID)
        XCTAssertEqual(graph.threads(spaceID: space).last?.nodes.count, 3)
        _ = graph.recordVisit(url: URL(string: "https://example.com/article")!, title: "Article", spaceID: otherSpace, parentNodeID: nil, query: nil, date: time.addingTimeInterval(3700))
        XCTAssertEqual(graph.threads(spaceID: otherSpace).count, 1)
        XCTAssertEqual(graph.threads(spaceID: space).count, 2)
        XCTAssertEqual(graph.search("important passage", spaceID: space).first?.id, child)
        graph.save()
        let restored = KnowledgeGraph(file: file)
        XCTAssertEqual(restored.visits.count, 5)
        XCTAssertEqual(restored.threads(spaceID: space).last?.id, originalID)
        XCTAssertEqual(restored.nodes.count, 3)
    }

    @MainActor
    func testLegacyMigrationAndURLIdentity() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let graph = KnowledgeGraph(file: file)
        let id = graph.recordVisit(url: URL(string: "https://example.com/article?utm_source=test#section")!, title: "Preserved title", spaceID: nil, parentNodeID: nil, query: nil)
        graph.save()
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        json.removeValue(forKey: "visits")
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let migrated = KnowledgeGraph(file: file)
        XCTAssertEqual(migrated.nodes[id]?.title, "Preserved title")
        XCTAssertEqual(migrated.visits.count, 1)
        XCTAssertEqual(migrated.threads().count, 1)
        XCTAssertEqual(migrated.node(for: URL(string: "https://example.com/article")!)?.id, id)
    }

    @MainActor
    func testVaultEditReloadMarkdownAndDelete() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("annotations.json")
        let vault = Vault(file: file, directory: directory)
        vault.add(text: "A passage", note: "First thought", url: URL(string: "https://example.com/a?utm_source=mail"), title: "An article", context: "Context")
        let annotation = try XCTUnwrap(vault.annotations.first)
        let markdown = directory.appendingPathComponent("notes/\(annotation.id.uuidString).md")
        XCTAssertEqual(vault.annotations(forURL: "https://example.com/a").count, 1)
        vault.update(annotation, note: "A revised thought")
        XCTAssertTrue(try String(contentsOf: markdown, encoding: .utf8).contains("A revised thought"))
        let restored = Vault(file: file, directory: directory)
        XCTAssertEqual(restored.annotations.first?.note, "A revised thought")
        restored.delete(annotation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markdown.path))
        XCTAssertTrue(Vault(file: file, directory: directory).annotations.isEmpty)
    }

    @MainActor
    func testRetrievalIncludesNotesAndOmniboxEscapesQuery() throws {
        let annotation = Annotation(id: UUID(), text: "Distributed indexes", note: "Latency is the tradeoff", url: "https://example.com", title: "Notes", context: "", created: Date())
        let found = KnowledgeAssistant.retrieve(query: "What is the latency tradeoff?", nodes: [], annotations: [annotation])
        XCTAssertEqual(found.first?.id, annotation.id)
        XCTAssertTrue(KnowledgeAssistant.retrieve(query: "pottery", nodes: [], annotations: [annotation]).isEmpty)
        guard case let .search(url, query) = Omnibox.resolve("cats & dogs + birds #1") else { return XCTFail("Expected search") }
        XCTAssertEqual(query, "cats & dogs + birds #1")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value, query)
    }
    @MainActor
    func testCorruptFilesStayUntouched() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("broken.json")
        let original = Data("not valid JSON".utf8)
        try original.write(to: file)
        let graph = KnowledgeGraph(file: file)
        XCTAssertNotNil(graph.errorText)
        graph.save()
        XCTAssertEqual(try Data(contentsOf: file), original)
        let vault = Vault(file: file, directory: directory)
        vault.add(text: "New note", note: "", url: nil, title: "", context: "")
        XCTAssertNotNil(vault.errorText)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor
    func testExplicitResumeKeepsOlderThread() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let graph = KnowledgeGraph(file: file), space = UUID()
        let date = Date(timeIntervalSince1970: 1000)
        let url = URL(string: "https://example.com/research")!
        let id = graph.recordVisit(url: url, title: "Research", spaceID: space, parentNodeID: nil, query: nil, date: date)
        let thread = try XCTUnwrap(graph.threads().first)
        _ = graph.recordVisit(url: url, title: "Research", spaceID: space, parentNodeID: id, query: nil, date: date.addingTimeInterval(86400), resumeThreadID: thread.id)
        XCTAssertEqual(graph.threads().count, 1)
        XCTAssertEqual(graph.threads().first?.id, thread.id)
        _ = graph.recordVisit(url: URL(string: "https://example.com/search?q=new")!, title: "New search", spaceID: space, parentNodeID: id, query: "new", date: date.addingTimeInterval(86460))
        XCTAssertEqual(graph.threads().count, 2)
    }

    @MainActor
    func testFailedNoteWriteDoesNotClaimSuccess() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = Vault(file: directory.appendingPathComponent("missing/index.json"), directory: directory)
        vault.add(text: "Keep this", note: "", url: URL(string: "https://example.com"), title: "Source", context: "")
        XCTAssertNotNil(vault.errorText)
        XCTAssertTrue(vault.annotations.isEmpty)
    }

}
