import Foundation
import WebKit
import CryptoKit

enum ContentBlocker {
    static let data: Data = {
        guard let url = Bundle.main.url(forResource: "blocklist", withExtension: "json") ?? Bundle.module.url(forResource: "blocklist", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return Data() }
        return data
    }()
    @MainActor static func compile() async throws -> WKContentRuleList {
        guard let json = String(data: data, encoding: .utf8), !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "graphene-\(digest)", encodedContentRuleList: json) else { throw CocoaError(.fileReadCorruptFile) }
        return list
    }
}
