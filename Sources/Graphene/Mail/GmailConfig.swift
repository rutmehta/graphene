import Foundation

/// OAuth client config for the Gmail integration. Loaded from a local, untracked
/// file so the client id/secret never live in the repo:
///   ~/Library/Application Support/Graphene/gmail.json
///   { "client_id": "…apps.googleusercontent.com", "client_secret": "GOCSPX-…" }
/// A "Desktop app" OAuth client is used → loopback redirect, no app bundling.
struct GmailConfig: Codable {
    var clientID: String
    var clientSecret: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }

    static let scope = "https://www.googleapis.com/auth/gmail.readonly"
    static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    static var file: URL { Paths.root.appendingPathComponent("gmail.json") }

    /// The current config, if the local file exists and is non-empty.
    static var current: GmailConfig? {
        guard let data = try? Data(contentsOf: file),
              let cfg = try? JSONDecoder().decode(GmailConfig.self, from: data),
              !cfg.clientID.isEmpty, !cfg.clientSecret.isEmpty else { return nil }
        return cfg
    }

    static var isConfigured: Bool { current != nil }

    /// Persist a client id/secret (used when the credentials arrive).
    static func save(clientID: String, clientSecret: String) {
        let cfg = GmailConfig(clientID: clientID, clientSecret: clientSecret)
        if let data = try? JSONEncoder().encode(cfg) { try? data.write(to: file) }
    }
}
