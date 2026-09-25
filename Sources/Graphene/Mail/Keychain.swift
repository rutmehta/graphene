import Foundation
import Security
import LocalAuthentication

/// The Gmail token set, persisted in the macOS Keychain (never on disk in plain text).
struct TokenSet: Codable {
    var accessToken: String
    var refreshToken: String
    var expiry: Date

    var isExpired: Bool { Date() >= expiry.addingTimeInterval(-60) }  // refresh a minute early
}

/// Minimal Keychain wrapper for one JSON blob under a fixed service/account.
enum Keychain {
    static func saveAIKey(_ key: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.graphene.ai", kSecAttrAccount as String: account]
        let status: OSStatus
        if key.isEmpty { status = SecItemDelete(query as CFDictionary) }
        else {
            let update = [kSecValueData as String: Data(key.utf8)]
            let existing = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if existing == errSecItemNotFound {
                var add = query; add[kSecValueData as String] = Data(key.utf8)
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(add as CFDictionary, nil)
            } else { status = existing }
        }
        guard status == errSecSuccess || (key.isEmpty && status == errSecItemNotFound) else { throw ProviderFailure(message: "Keychain couldn’t save the API key (\(status)).") }
    }
    static func aiKey(account: String) -> String? {
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.graphene.ai", kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: context]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static let service = "com.graphene.gmail"
    private static let account = "tokens"

    static func saveTokens(_ tokens: TokenSet) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadTokens() -> TokenSet? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let tokens = try? JSONDecoder().decode(TokenSet.self, from: data) else { return nil }
        return tokens
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
