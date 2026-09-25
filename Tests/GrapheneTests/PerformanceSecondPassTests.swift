import XCTest
import SwiftUI
import AppKit
import WebKit
@testable import Graphene

/// The second performance pass (docs/parity/perf-audit.md, "Second pass"): session saves off
/// the main thread, a cached command table, rasterised chrome textures, shared web-view
/// configuration, a deferred graph load, cheaper sidebar rows, delayed page-text capture,
/// memory-pressure discards that spare recent tabs, and cached Vault lookups.
@MainActor
final class PerformanceSecondPassTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDown() async throws {
        SessionWriter.shared.flush()
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
        try await super.tearDown()
    }
    private func directory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        roots.append(root)
        return root
    }
    private func milliseconds(_ runs: Int = 1, _ body: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<runs { body() }
        return (CFAbsoluteTimeGetCurrent() - start) * 1000 / Double(runs)
    }
    /// An app with 60 tabs and a full 2,000-entry archive.
    private func largeSession() -> AppState {
        let app = AppState(directory: directory())
        for index in 0..<60 {
            let tab = app.newTab(activate: false)
            tab.url = URL(string: "https://example.com/page/\(index)"); tab.title = "Page \(index) with a moderately long title"
        }
        var entry = AppState.SessionTab(app.tabs[1]); entry.archivedAt = Date()
        app.archivedTabs = (0..<2000).map { index in
            var copy = entry; copy.archiveID = UUID(); copy.id = UUID(); copy.url = "https://example.com/archived/\(index)?q=x"; copy.title = "Archived \(index)"
            return copy
        }
        return app
    }

    // MARK: 1. session save

    func testSaveHandsTheMainThreadOnlyASnapshot() throws {
        let app = largeSession()
        app.persist(); app.flushSaves()
        // What the main thread used to do on every save: encode the archive and the session.
        let encoding = milliseconds(5) { _ = try? JSONEncoder().encode(app.archivedTabs) }
        let saving = milliseconds(5) { app.persist() }
        app.flushSaves()
        print(String(format: "[perf] persist() on the main thread: %.3f ms; encoding the archive alone: %.3f ms", saving, encoding))
        XCTAssertLessThan(saving, encoding / 4, "persist() takes a snapshot; encoding happens on the writer queue")
        let restored = AppState(directory: app.dataDirectory)
        XCTAssertEqual(restored.archivedTabs.count, 2000)
        XCTAssertEqual(restored.tabs.count, app.tabs.count)
    }

    /// Session, archive and settings writes for `app`'s files.
    private func writes(_ app: AppState) -> (session: Int, archive: Int, settings: Int) {
        let writer = SessionWriter.shared
        return (writer.writes(to: app.dataDirectory.appendingPathComponent("session.json")),
                writer.writes(to: app.dataDirectory.appendingPathComponent("archive.json")),
                writer.writes(to: app.dataDirectory.appendingPathComponent("settings.json")))
    }

    func testBurstsOfChangesCoalesceIntoOneSave() async throws {
        let app = AppState(directory: directory())
        app.persist(); app.flushSaves()
        let before = writes(app)
        for _ in 0..<25 { app.persistSoon() }
        SessionWriter.shared.flush()
        XCTAssertEqual(writes(app).session, before.session, "Nothing is written while changes keep arriving")
        try await Task.sleep(for: .milliseconds(Int(AppState.saveDelay * 1000) + 300))
        SessionWriter.shared.flush()
        let after = writes(app)
        XCTAssertEqual(after.session - before.session, 1, "One save for the burst")
        XCTAssertEqual(after.settings - before.settings, 1)
        XCTAssertEqual(after.archive, before.archive, "The unchanged archive is not re-encoded")
        XCTAssertLessThanOrEqual(AppState.saveDelay, 0.5)
    }

    func testArchiveIsEncodedOnlyWhenItChanged() throws {
        let app = AppState(directory: directory())
        app.persist(); app.flushSaves()
        var before = writes(app)
        XCTAssertEqual(before.archive, 1)
        app.persist(); app.flushSaves()
        XCTAssertEqual(writes(app).session - before.session, 1)
        XCTAssertEqual(writes(app).archive, before.archive)
        let tab = app.newTab(); tab.url = URL(string: "https://example.com/closed")
        app.closeTab(tab.id, announce: false)
        before = writes(app)
        app.persist(); app.flushSaves()
        XCTAssertEqual(writes(app).archive - before.archive, 1, "A changed archive is written with the session")
        let archive = try JSONDecoder().decode([AppState.SessionTab].self, from: Data(contentsOf: app.dataDirectory.appendingPathComponent("archive.json")))
        XCTAssertTrue(archive.contains { $0.url == "https://example.com/closed" })
    }

    func testAPendingSaveIsFlushedBeforeTheFilesAreRead() throws {
        let root = directory()
        let app = AppState(directory: root)
        app.layout = .topTabs
        app.flushSaves()
        XCTAssertEqual(AppState(directory: root).layout, .topTabs, "flushSaves writes the debounced save now (quit)")
    }

    func testANewerSnapshotReplacesOneStillQueued() throws {
        let writer = SessionWriter()
        let root = directory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let slow = root.appendingPathComponent("slow.json"), file = root.appendingPathComponent("session.json")
        writer.write(slow, encode: { Thread.sleep(forTimeInterval: 0.2); return Data("{}".utf8) })
        for index in 0..<5 { writer.write(file, encode: { Data("\(index)".utf8) }) }
        writer.flush()
        XCTAssertEqual(writer.writes, 2, "The four snapshots replaced while queued are never encoded")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "4")
    }

    // MARK: 2. command table

    func testCommandTableIsBuiltOncePerChange() throws {
        let app = AppState(directory: directory())
        let tab = try XCTUnwrap(app.activeTab)
        tab.url = URL(string: "https://example.com")
        _ = app.commandActions
        let builds = app.commandRegistryBuilds
        for _ in 0..<50 { _ = app.commandActions; _ = app.allCommandActions; _ = app.commandAction("reload") }
        XCTAssertEqual(app.commandRegistryBuilds, builds, "Unchanged state reuses the table")
        XCTAssertNil(app.commandAction("stop"))
        tab.isLoading = true
        XCTAssertNotNil(app.commandAction("stop"), "Loading enables Stop")
        XCTAssertEqual(app.commandRegistryBuilds, builds + 1)
        XCTAssertNil(app.commandAction("find-next"))
        app.findQuery = "graphene"
        XCTAssertNotNil(app.commandAction("find-next"))
        let other = app.newTab()
        XCTAssertNil(app.commandAction("reload"), "The new active tab has no page")
        other.url = URL(string: "https://example.org")
        XCTAssertEqual(app.commandAction("pin")?.title, "Pin Tab")
        app.pin(other)
        XCTAssertEqual(app.commandAction("pin")?.title, "Unpin Tab")
        app.renameSpace(app.spaces[0].id, name: "Reading")
        XCTAssertEqual(app.allCommandActions.first { $0.id == "space-1" }?.title, "Switch to Reading")
    }

    func testKeyMonitorLooksCommandsUpByKeyEquivalent() throws {
        let app = AppState(directory: directory())
        let next = CommandShortcut(key: "\t", command: false, control: true)
        let previous = CommandShortcut(key: "\t", command: false, control: true, shift: true)
        XCTAssertTrue(app.commandIDs(for: next).contains("mru-next"))
        XCTAssertTrue(app.commandIDs(for: previous).contains("mru-previous"))
        XCTAssertEqual(app.commandIDs(for: CommandShortcut(key: "q", command: false, control: true)), [])
        let builds = app.commandRegistryBuilds
        let perKey = milliseconds(2000) { _ = app.commandIDs(for: next) }
        XCTAssertEqual(app.commandRegistryBuilds, builds, "A keystroke never builds the command table")
        print(String(format: "[perf] key-equivalent lookup: %.4f ms", perKey))
        XCTAssertNil(app.remapCommand("mru-next", to: CommandShortcut(key: "j", command: false, control: true)))
        XCTAssertEqual(app.commandIDs(for: CommandShortcut(key: "j", command: false, control: true)), ["mru-next"])
        XCTAssertFalse(app.commandIDs(for: next).contains("mru-next"), "The index follows shortcut overrides")
    }

    // MARK: 3. rasterised textures

    func testGrainMaskIsCachedAcrossRedrawsAtTheSameSize() throws {
        let size = CGSize(width: 1280, height: 820)
        let first = try XCTUnwrap(ChromeGrain.mask(size: size, scale: 2))
        let renders = MaskRaster.shared.renders
        for _ in 0..<20 { XCTAssertTrue(ChromeGrain.mask(size: size, scale: 2) === first, "Same size, same image") }
        XCTAssertEqual(MaskRaster.shared.renders, renders)
        XCTAssertEqual(first.width, 2560); XCTAssertEqual(first.height, 1640)

        _ = ChromeGrain.mask(size: CGSize(width: 1281, height: 820), scale: 2)
        XCTAssertEqual(MaskRaster.shared.renders, renders + 1, "A new size rasterises once")

        // The view itself: redrawing it (a colour change, the space-switch fade) reuses the mask.
        let app = AppState(directory: directory())
        app.mode = .dark
        let view = ChromeGrain().environmentObject(app).frame(width: size.width, height: size.height)
        let render = { let renderer = ImageRenderer(content: view); renderer.scale = 2; _ = renderer.cgImage }
        render()
        let drawn = MaskRaster.shared.renders
        for _ in 0..<3 { render() }
        app.mode = .light
        render()
        XCTAssertEqual(MaskRaster.shared.renders, drawn, "Redraws and appearance changes do not rasterise again")

        let redraw = milliseconds(20) {
            let context = CGContext(data: nil, width: 2560, height: 1640, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
            context.scaleBy(x: 2, y: 2); ChromeGrain.draw(context, size: size)
        }
        let cached = milliseconds(200) { _ = ChromeGrain.mask(size: size, scale: 2) }
        print(String(format: "[perf] grain: drawing 2,400 dots %.3f ms per redraw before; cached mask lookup %.4f ms", redraw, cached))
    }

    func testGrainMaskDrawsTheSameDotsAsTheCanvas() throws {
        let size = CGSize(width: 400, height: 300), scale: CGFloat = 2
        let mask = try XCTUnwrap(ChromeGrain.mask(size: size, scale: scale))
        // The Canvas the grain replaced, drawn in opaque white on clear.
        let reference = Canvas { context, size in
            for index in 0..<2400 {
                let x = CGFloat((index * 73) % 997) / 997 * size.width
                let y = CGFloat((index * 193) % 991) / 991 * size.height
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white))
            }
        }.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: reference); renderer.scale = scale
        let canvas = try XCTUnwrap(renderer.cgImage)
        let lhs = alphaPixels(mask), rhs = alphaPixels(canvas)
        XCTAssertEqual(lhs.count, rhs.count)
        var both = 0, either = 0
        for index in lhs.indices { let a = lhs[index] > 127, b = rhs[index] > 127; if a && b { both += 1 }; if a || b { either += 1 } }
        XCTAssertGreaterThan(either, 1000)
        XCTAssertGreaterThan(Double(both) / Double(either), 0.9, "The mask's dots are where the Canvas drew them (same orientation and scale)")

        // Through SwiftUI's image mask, the grain colour lands on those dots.
        let app = AppState(directory: directory()); app.mode = .dark
        let shown = ImageRenderer(content: ChromeGrain().environmentObject(app).frame(width: size.width, height: size.height)); shown.scale = scale
        let drawn = alphaPixels(try XCTUnwrap(shown.cgImage))
        var onDots = 0, offDots = 0
        for index in lhs.indices where drawn[index] > 0 { if lhs[index] > 127 { onDots += 1 } else if lhs[index] == 0 { offDots += 1 } }
        XCTAssertGreaterThan(onDots, 1000, "The grain draws")
        XCTAssertLessThan(offDots, onDots / 10, "and only on the dots")
    }

    func testLatticeMaskIsCachedPerSize() throws {
        let size = CGSize(width: 900, height: Lattice.bandHeight)
        let first = try XCTUnwrap(MaskRaster.shared.image(kind: Lattice.rasterKind, size: size, scale: 2, draw: Lattice.draw))
        let renders = MaskRaster.shared.renders
        XCTAssertTrue(MaskRaster.shared.image(kind: Lattice.rasterKind, size: size, scale: 2, draw: Lattice.draw) === first)
        XCTAssertEqual(MaskRaster.shared.renders, renders)
        XCTAssertNil(MaskRaster.shared.image(kind: Lattice.rasterKind, size: CGSize(width: 5000, height: 5000), scale: 2, draw: Lattice.draw),
                     "An oversized Board canvas draws directly instead of caching a huge bitmap")
    }

    private func alphaPixels(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    // MARK: 4. shared web-view configuration

    func testEnginesShareUserScriptsAndTheProfileDataStore() throws {
        let first = WKWebEngine(), second = WKWebEngine()
        let lhs = first.webView.configuration.userContentController.userScripts
        let rhs = second.webView.configuration.userContentController.userScripts
        XCTAssertEqual(lhs.count, rhs.count)
        XCTAssertTrue(zip(lhs, rhs).allSatisfy { $0 === $1 }, "One set of WKUserScript objects serves every engine")
        XCTAssertTrue(first.webView.configuration.websiteDataStore === second.webView.configuration.websiteDataStore, "One data store per profile")
        XCTAssertFalse(first.webView.configuration.userContentController === second.webView.configuration.userContentController,
                       "Each page keeps its own controller: rule lists and message handlers are per page")
        let isolated = WKWebEngine(privateMode: true)
        XCTAssertFalse(isolated.webView.configuration.websiteDataStore.isPersistent)
    }

    func testNewTabsDoNotRebuildOrEvaluateScriptsTheyAlreadyHave() throws {
        let app = AppState(directory: directory())
        let tab = app.newTab(activate: false)
        let engine = try XCTUnwrap(tab.loadedEngine as? WKWebEngine)
        let installed = engine.webView.configuration.userContentController.userScripts
        XCTAssertTrue(zip(installed, engine.desiredUserScripts).allSatisfy { $0 === $1 })
        engine.refreshBoosts()
        let again = engine.webView.configuration.userContentController.userScripts
        XCTAssertTrue(zip(installed, again).allSatisfy { $0 === $1 }, "An unchanged script set is left installed")

        _ = app.newTab(activate: false)
        let create = milliseconds(10) { _ = app.newTab(activate: false) }
        print(String(format: "[perf] new tab with a configured web view: %.2f ms", create))
    }

    // MARK: 5. cold start

    func testDeferredGraphLoadKeepsWhatIsRecordedWhileItLoads() async throws {
        let root = directory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("graph.json")
        let saved = KnowledgeGraph(file: file)
        let old = saved.recordVisit(url: URL(string: "https://example.com/old")!, title: "Old", spaceID: nil, parentNodeID: nil, query: nil)
        saved.save()

        let graph = KnowledgeGraph(file: file, deferLoad: true)
        XCTAssertFalse(graph.isLoaded, "init returns before the file is decoded")
        XCTAssertTrue(graph.nodes.isEmpty)
        var loadedFirst = false
        graph.whenLoaded { loadedFirst = graph.nodes[old] != nil }
        let new = graph.recordVisit(url: URL(string: "https://example.com/new")!, title: "New", spaceID: nil, parentNodeID: nil, query: nil)
        XCTAssertTrue(graph.isLoaded && loadedFirst, "A change waits for the load first")
        XCTAssertNotNil(graph.nodes[old]); XCTAssertNotNil(graph.nodes[new])

        let lazy = KnowledgeGraph(file: file, deferLoad: true)
        for _ in 0..<100 where !lazy.isLoaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(lazy.isLoaded, "The load lands on its own")
        XCTAssertEqual(lazy.node(for: URL(string: "https://example.com/old")!)?.id, old)
    }

    func testContentBlockerIsLoadedOncePerProcess() async throws {
        async let first = ContentBlocker.compile()
        async let second = ContentBlocker.compile()
        let (lhs, rhs) = try await (first, second)
        XCTAssertTrue(lhs === rhs, "Concurrent callers share one load")
        XCTAssertTrue(ContentBlocker.compiled === lhs)
    }

    // MARK: 6. sidebar rows

    func testTodayBuildsLazilyBeyondFortyRows() {
        XCTAssertFalse(Sidebar.lazyToday(rows: 40, hasBranches: false))
        XCTAssertTrue(Sidebar.lazyToday(rows: 41, hasBranches: false))
        XCTAssertFalse(Sidebar.lazyToday(rows: 400, hasBranches: true), "Branches keep one stack for their connectors")
        XCTAssertEqual(Sidebar.lazyTodayThreshold, 40)
    }

    func testRowStateChangesOnlyWithWhatTheRowShows() throws {
        let app = AppState(directory: directory())
        let row = app.newTab(activate: false), other = app.newTab(activate: true)
        let state = app.sidebarRowState(row, pal: app.pal)
        other.url = URL(string: "https://example.com")
        _ = app.graph.recordVisit(url: URL(string: "https://example.com")!, title: "Example", spaceID: app.activeSpaceID, parentNodeID: nil, query: nil)
        app.findQuery = "x"
        XCTAssertEqual(app.sidebarRowState(row, pal: app.pal), state, "A graph change or another tab's page leaves the row alone")
        app.activate(row.id)
        XCTAssertTrue(app.sidebarRowState(row, pal: app.pal).selected)
        XCTAssertFalse(app.sidebarRowState(other, pal: app.pal).selected)
        app.mode = app.mode == .dark ? .light : .dark
        XCTAssertNotEqual(app.sidebarRowState(row, pal: app.pal).pal, state.pal, "An appearance change redraws the rows")
    }

    // MARK: 7. page-text capture

    func testReadableTextIsCappedAndSpacedLikeThePage() async throws {
        let engine = WKWebEngine()
        let long = String(repeating: "graphene ", count: 12_000)
        let html = "<html><body><nav>Menu</nav><main><p>First</p><p>Second<br>line</p><div><p>inner</p>tail</div><span aria-hidden=\"true\">hidden</span><p>\(long)</p></main></body></html>"
        engine.webView.loadHTMLString(html, baseURL: URL(string: "https://example.com/long"))
        for _ in 0..<100 where engine.isLoading || engine.currentURL == nil { try await Task.sleep(for: .milliseconds(50)) }
        let content = await engine.captureReadableContent()
        XCTAssertEqual(content.text.count, 40_000, "Capped at 40,000 characters")
        XCTAssertTrue(content.text.hasPrefix("First Second line inner tail graphene"), String(content.text.prefix(80)))
        XCTAssertFalse(content.text.contains("Menu") || content.text.contains("hidden"))
        let idle = await engine.captureReadableContent(idle: true)
        XCTAssertEqual(idle.text, content.text, "The idle read returns the same text")
    }

    func testPageTextIsReadAfterTwoSecondsAndNotForPagesLeftSooner() async throws {
        let app = AppState(directory: directory())
        let tab = try XCTUnwrap(app.activeTab)
        let engine = try XCTUnwrap(tab.engine as? WKWebEngine)
        func load(_ path: String, _ text: String) async throws {
            engine.webView.loadHTMLString("<html><head><title>\(text)</title></head><body><main><p>\(text) body text</p></main></body></html>", baseURL: URL(string: "https://example.com/\(path)"))
            for _ in 0..<100 where tab.url?.path != "/\(path)" || engine.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        }
        try await load("left", "Left")
        let left = try XCTUnwrap(tab.currentNodeID)
        try await Task.sleep(for: .milliseconds(500))
        try await load("stayed", "Stayed")
        let stayed = try XCTUnwrap(tab.currentNodeID)
        XCTAssertNotEqual(left, stayed)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(app.graph.nodes[stayed]?.snippet, "", "Nothing is read during the first two seconds")
        try await Task.sleep(for: .milliseconds(2700))
        XCTAssertEqual(app.graph.nodes[left]?.snippet, "", "A page left within two seconds is never read")
        XCTAssertEqual(app.graph.nodes[stayed]?.snippet, "Stayed body text")
    }

    // MARK: memory pressure spares recent tabs

    func testRecentTabsSurviveTheCapAndWarningsButNotCriticalPressure() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let shown = TabLifecycle.Resident(id: UUID(), lastActive: now, displayed: true)
        let background = (0..<6).map { TabLifecycle.Resident(id: UUID(), lastActive: now.addingTimeInterval(-Double($0 + 1) * 60)) }
        let all = [shown] + background.reversed()
        XCTAssertEqual(Set(TabLifecycle.lruVictims(all, limit: 1, exemptRecent: 3)), Set(background[4...].map(\.id)),
                       "The three most recent background tabs are kept and do not count toward the cap")
        XCTAssertEqual(Set(TabLifecycle.lruVictims(all, limit: 0, exemptRecent: TabLifecycle.pressureExempt(critical: false))), Set(background[3...].map(\.id)))
        XCTAssertEqual(Set(TabLifecycle.lruVictims(all, limit: 0, exemptRecent: TabLifecycle.pressureExempt(critical: true))), Set(background.map(\.id)))
        XCTAssertEqual(TabLifecycle.recentExempt, 3)
    }

    func testMemoryWarningKeepsTheTabYouJustLeft() async throws {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let app = AppState(directory: directory(), clock: { now })
        app.settings.backgroundTabLimit = 2
        var visited: [Graphene.Tab] = []
        for _ in 0..<6 {
            now.addTimeInterval(60)
            let tab = app.newTab(activate: true)
            visited.append(tab)
        }
        now.addTimeInterval(60)
        let current = app.newTab(activate: true)
        // visited[5] is the tab just left; visited[3...5] are the three most recent.
        await app.relieveMemoryPressure(critical: false)
        XCTAssertTrue(visited[3...].allSatisfy { $0.loadedEngine != nil }, "A warning never discards the three most recent tabs")
        XCTAssertNotNil(visited[2].loadedEngine, "The warning keeps half the cap beyond them")
        XCTAssertTrue(visited[..<2].allSatisfy { $0.loadedEngine == nil })
        XCTAssertNotNil(current.loadedEngine)

        await app.pollMediaAndDiscard()
        XCTAssertTrue(visited[3...].allSatisfy { $0.loadedEngine != nil }, "The periodic cap spares them too")

        await app.relieveMemoryPressure(critical: true)
        XCTAssertTrue(visited.allSatisfy { $0.loadedEngine == nil }, "Critical pressure may discard them")
        XCTAssertNotNil(current.loadedEngine)
    }

    // MARK: 8. Vault lookups

    func testVaultLookupsAreIndexedAndFollowChanges() throws {
        let root = directory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let space = UUID()
        let notes = (0..<2000).map { index in
            Annotation(id: UUID(), text: "Quote \(index)", note: "", url: "https://example\(index % 300).com/page/\(index % 700)?utm_source=x",
                       title: "T", context: "", created: Date(timeIntervalSince1970: Double(index)), spaceID: index.isMultiple(of: 2) ? space : nil)
        }
        try JSONEncoder().encode(notes).write(to: root.appendingPathComponent("annotations.json"))
        let vault = Vault(file: root.appendingPathComponent("annotations.json"), directory: root)
        let url = "https://example5.com/page/5"
        let expected = notes.filter { KnowledgeGraph.canonicalURL($0.url) == KnowledgeGraph.canonicalURL(url) }.map(\.id)
        XCTAssertEqual(vault.annotations(forURL: url).map(\.id), expected)
        let lookup = milliseconds(50) { _ = vault.annotations(forURL: url) }
        let shelf = milliseconds(50) { _ = vault.notes(inSpace: space, limit: 3) }
        print(String(format: "[perf] Vault lookup by URL (2,000 notes): %.4f ms; shelf notes: %.4f ms", lookup, shelf))
        XCTAssertLessThan(lookup, 0.5)
        XCTAssertEqual(vault.notes(inSpace: space, limit: 1).first?.text, "Quote 1998")

        let added = try XCTUnwrap(vault.add(text: "New quote", note: "", url: URL(string: url), title: "T", context: "", spaceID: space))
        XCTAssertEqual(vault.annotations(forURL: url).first?.id, added.id, "The index is rebuilt after a change")
        XCTAssertEqual(vault.notes(inSpace: space, limit: 1).first?.id, added.id)
        vault.delete(added)
        XCTAssertFalse(vault.annotations(forURL: url).contains { $0.id == added.id })
    }
}
