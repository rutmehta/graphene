import Foundation
import WebKit
import CryptoKit

enum ContentBlocker {
    static let data: Data = {
        guard let url = Bundle.main.url(forResource: "blocklist", withExtension: "json") ?? Bundle.module.url(forResource: "blocklist", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return Data() }
        return data
    }()
    /// The rule list once compiled (or found compiled on disk), shared by every engine.
    @MainActor private(set) static var compiled: WKContentRuleList?
    @MainActor private static var compiling: Task<WKContentRuleList, Error>?

    /// The compiled list: from memory, else WebKit's store on disk (compiled by an earlier
    /// launch, keyed by the list's digest), else compiled now. Concurrent callers share one
    /// attempt. Started at launch (`prewarm`), so the first page load rarely waits for it.
    @MainActor static func compile() async throws -> WKContentRuleList {
        if let compiled { return compiled }
        if let compiling { return try await compiling.value }
        let task = Task<WKContentRuleList, Error> { @MainActor in
            StartupTrace.mark("content blocker load start")
            let data = self.data
            guard !data.isEmpty, let json = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
            let digest = await Task.detached(priority: .userInitiated) { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }.value
            let identifier = "graphene-\(digest)"
            let store = WKContentRuleListStore.default()!
            let stored: WKContentRuleList? = await withCheckedContinuation { continuation in
                store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in continuation.resume(returning: list) }
            }
            if let stored {
                StartupTrace.mark("content blocker found compiled on disk")
                return stored
            }
            guard let list = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) else { throw CocoaError(.fileReadCorruptFile) }
            StartupTrace.mark("content blocker compiled")
            return list
        }
        compiling = task
        do {
            let list = try await task.value
            compiled = list; compiling = nil
            return list
        } catch { compiling = nil; throw error }
    }

    /// Loads the list in the background after launch, off the first page load's path.
    @MainActor static func prewarm() {
        guard compiled == nil, compiling == nil else { return }
        Task { @MainActor in _ = try? await compile() }
    }
}
