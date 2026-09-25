import XCTest
import SwiftUI
@testable import Graphene

/// Hands-on fixes to Threads and Ask (graphene-language.md §5.2, §5.4): the space-wide map,
/// labelled List and Map, Ask over a library surface, and the thread-summary request.
@MainActor
final class ThreadsAskTests: XCTestCase {
    private var directory: URL!
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Two threads: A with B under it, then (a new root) X with Y under it.
    private func recordTwoThreads(_ app: AppState) throws -> (first: KnowledgeGraph.Thread, second: KnowledgeGraph.Thread) {
        var ids: [String: UUID] = [:]
        func record(_ name: String, parent: String?, minute: Double) {
            ids[name] = app.graph.recordVisit(url: URL(string: "https://map.invalid/\(name)")!, title: name.uppercased(),
                                              spaceID: app.activeSpaceID, parentNodeID: parent.flatMap { ids[$0] }, query: nil,
                                              date: Date().addingTimeInterval(minute * 60 - 600))
        }
        record("a", parent: nil, minute: 0); record("b", parent: "a", minute: 1)
        record("x", parent: nil, minute: 5); record("y", parent: "x", minute: 6)
        let first = try XCTUnwrap(app.currentThreads.first { $0.nodes.first?.url.hasSuffix("/a") == true })
        let second = try XCTUnwrap(app.currentThreads.first { $0.nodes.first?.url.hasSuffix("/x") == true })
        XCTAssertNotEqual(first.id, second.id)
        return (first, second)
    }

    // MARK: item 1: the space-wide map

    func testForestIsOneTreePerThreadEachWithItsStartLabel() throws {
        let app = AppState(directory: directory)
        let (first, second) = try recordTwoThreads(app)
        let forest = ThreadForest(threads: app.currentThreads, visits: app.graph.visits)
        XCTAssertEqual(Set(forest.trees.map(\.id)), [first.id, second.id], "every thread in the space")
        XCTAssertEqual(forest.trees.map(\.id), app.currentThreads.map(\.id), "in the list's order")
        XCTAssertEqual(forest.pageCount, 4)
        for tree in forest.trees {
            XCTAssertEqual(tree.layout, app.threadLayout(tree.thread), "the same layout as the single-thread map")
            XCTAssertEqual(tree.layout.headers.first?.start, tree.thread.start, "each tree carries its start label")
            XCTAssertEqual(tree.layout.nodes.map(\.column), [0, 1])
        }
        XCTAssertEqual(ThreadPanes.forestCounts(threads: 2, pages: 4), "2 threads · 4 pages")
        XCTAssertEqual(ThreadPanes.forestCounts(threads: 1, pages: 1), "1 thread · 1 page")
    }

    func testThreadsOpensOnTheMapWithLabelledModesAndAnAllThreadsItem() throws {
        let ledger = try source("Sources/Graphene/UI/LedgerView.swift")
        XCTAssertTrue(ledger.contains("@State private var map = true"), "Map is the default view")
        XCTAssertTrue(ledger.contains(#"LibraryBarButton("List", system: "list.bullet.indent", selected: !map, showsTitle: true)"#))
        XCTAssertTrue(ledger.contains(#"LibraryBarButton("Map", system: "point.3.connected.trianglepath.dotted", selected: map, showsTitle: true)"#))
        XCTAssertTrue(ledger.contains("if showsTitle { Text(title).font(ShellType.label)"), "the mode titles are visible text in label")
        XCTAssertTrue(ledger.contains("AllThreadsRow(count: threads.count, selected: selected == nil) { app.selectedThreadID = nil }"))
        XCTAssertTrue(ledger.contains("else { ForestDetail(threads: threads, map: map) }"), "no selection shows every thread")
        XCTAssertFalse(ledger.contains("?? threads.first"), "no thread is selected until the list selects one")
        XCTAssertFalse(ledger.contains("GraphView"), "the force-directed graph stays deleted")
    }

    func testTheChatGlyphIsSparkle() throws {
        let ledger = try source("Sources/Graphene/UI/LedgerView.swift")
        XCTAssertTrue(ledger.contains(#"LibraryBarButton("Ask this thread", system: ShellGlyph.ask)"#), "the Ask glyph comes from the shared ShellGlyph.ask (sparkle)")
        XCTAssertFalse(ledger.contains("text.bubble"))
    }

    // MARK: item 3: Ask over a library surface

    func testAskOverThreadsKeepsThreadsAndGroundsOnTheSelectedThread() throws {
        let app = AppState(directory: directory)
        let (_, second) = try recordTwoThreads(app)
        app.show(.threads)
        app.selectedThreadID = second.id
        app.toggleKnowledge()
        XCTAssertEqual(app.activeSurface, .threads, "the panel floats over Threads")
        XCTAssertTrue(app.knowledgeSearchPresented)
        XCTAssertEqual(app.knowledgeThreadID, second.id, "grounded on the selected thread")
        app.toggleKnowledge()
        XCTAssertFalse(app.knowledgeSearchPresented)
        XCTAssertEqual(app.activeSurface, .threads)

        // The library bar's Ask glyph does the same.
        app.askThread(second)
        XCTAssertEqual(app.activeSurface, .threads)
        XCTAssertEqual(app.knowledgeThreadID, second.id)
        app.knowledgeSearchPresented = false

        // All threads selected: the panel still opens over Threads, on the current tab.
        app.selectedThreadID = nil
        app.toggleKnowledge()
        XCTAssertEqual(app.activeSurface, .threads)
        XCTAssertNil(app.knowledgeThreadID)
        app.knowledgeSearchPresented = false

        for surface in [Surface.vault, .board, .mail] {
            app.show(surface)
            app.toggleKnowledge()
            XCTAssertEqual(app.activeSurface, surface, "Ask never switches \(surface) to the web")
            XCTAssertTrue(app.knowledgeSearchPresented)
            app.toggleKnowledge()
        }
    }

    func testGroundingLineSaysThisThreadForAThreadsPages() {
        let page = KnowledgeSource(id: UUID(), title: "A", url: "https://map.invalid/a", text: "Text", kind: "Visited page")
        let tab = KnowledgeSource(id: UUID(), title: "T", url: "https://map.invalid/t", text: "Text", kind: "Tab")
        let pages = [page, KnowledgeSource(id: UUID(), title: "B", url: "https://map.invalid/b", text: "Text", kind: "Visited page")]
        XCTAssertEqual(ChatView.groundingLine(ChatGrounding(sources: pages, activeTabID: nil), sources: pages, thread: true), "This thread")
        XCTAssertEqual(ChatView.groundingLine(ChatGrounding(sources: pages, activeTabID: nil), sources: pages, thread: false), "2 sources")
        XCTAssertEqual(ChatView.groundingLine(ChatGrounding(sources: [page, tab], activeTabID: nil), sources: [page, tab], thread: true), "2 sources",
                       "an attached tab is no longer just the thread")
        XCTAssertEqual(ChatView.groundingLine(ChatGrounding(sources: [], activeTabID: nil), sources: [], thread: true), "Nothing yet")
    }

    // MARK: item 2: the thread-summary request

    func testSummaryRequestListsPagesNotAChat() {
        let pages = [
            KnowledgeSource(id: UUID(), title: "Graphene - Wikipedia", url: "https://en.wikipedia.org/wiki/Graphene", text: "Graphene is an allotrope of carbon.", kind: "Thread"),
            KnowledgeSource(id: UUID(), title: "hello - Google Search", url: "https://www.google.com/search?q=hello", text: "Results", kind: "Thread"),
        ]
        let messages = ThreadSummaryModel.messages(pages)
        XCTAssertEqual(messages.map(\.role), [.system, .user])
        XCTAssertEqual(messages[0].content, PageContext.threadSummaryInstructions)
        XCTAssertNotEqual(messages[0].content, PageContext.instructions, "not the Ask instructions")
        let request = messages[1].content
        XCTAssertTrue(request.hasPrefix("Page 1: Graphene - Wikipedia (en.wikipedia.org)\nGraphene is an allotrope of carbon."))
        XCTAssertTrue(request.contains("\n\nPage 2: hello - Google Search (google.com), search results for “hello”\nResults"))
        XCTAssertTrue(request.hasSuffix("\n\nIn one paragraph of 2 to 4 sentences, summarise what these 2 pages are about and what the person seems to be researching. End every sentence with the page number it draws on in square brackets, like [1] or [2]."))
        for word in ["Question:", "Source [", "user", "assistant"] { XCTAssertFalse(request.contains(word), word) }
        for phrase in ["web pages one person visited, in the order they visited them", "It is not a conversation", "2 to 4 sentences", "never as \"Page 1\"",
                       "Never describe the input's format", "search results for “hello”; there isn't enough content to summarise."] {
            XCTAssertTrue(PageContext.threadSummaryInstructions.contains(phrase), phrase)
        }
    }

    func testSearchOnlyThreadsSaySoInOneSentence() {
        func page(_ url: String, _ text: String) -> KnowledgeSource { KnowledgeSource(id: UUID(), title: "Google", url: url, text: text, kind: "Thread") }
        let results = String(repeating: "Hello - Wikipedia. Hello is a salutation or greeting in the English language. ", count: 10)
        XCTAssertEqual(PageContext.thinThreadSummary([page("https://www.google.com/", "Google Search I'm Feeling Lucky"), page("https://www.google.com/search?q=hello&hl=en", results)]),
                       "These pages are search results for “hello”; there isn't enough content to summarise.")
        XCTAssertEqual(PageContext.thinThreadSummary([page("https://duckduckgo.com/?q=graphene+strength", "")]),
                       "This page is search results for “graphene strength”; there isn't enough content to summarise.")
        XCTAssertEqual(PageContext.thinThreadSummary([page("https://example.org/a", ""), page("https://example.org/b", "Sign in")]),
                       "These pages have too little text to summarise.")
        XCTAssertEqual(PageContext.thinThreadSummary([page("https://www.bing.com/search?q=a", ""), page("https://www.bing.com/search?q=b", ""), page("https://www.bing.com/search?q=A", ""), page("https://www.google.com/search?q=c", "")]),
                       "These pages are search results for “a”, “b” and “c”; there isn't enough content to summarise.")
        XCTAssertNil(PageContext.thinThreadSummary([page("https://www.google.com/search?q=hello", results), page("https://en.wikipedia.org/wiki/Hello", results)]),
                     "one real page: the model summarises")
        XCTAssertNil(PageContext.searchQuery("https://docs.google.com/document/d/1?q=x"), "not a web search")
        XCTAssertNil(PageContext.searchQuery("https://www.google.com/search?q=%20"))
        XCTAssertEqual(PageContext.searchQuery("https://search.yahoo.com/search?p=kittens"), "kittens")
        XCTAssertEqual(PageContext.searchQuery("https://www.google.com/search?q=c%2B%2B+tutorial"), "c++ tutorial")
    }
}
