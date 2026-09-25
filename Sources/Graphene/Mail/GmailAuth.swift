import Foundation
import CryptoKit
import AppKit

enum GmailAuthError: LocalizedError {
    case notConfigured
    case cancelled
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add your Google OAuth client id/secret to connect."
        case .cancelled: return "Sign-in was cancelled."
        case .tokenExchangeFailed(let m): return "Couldn't complete sign-in: \(m)"
        }
    }
}

/// The OAuth 2.0 flow for a Google "Desktop app" client, with PKCE and a loopback
/// redirect. Opens the system browser (which Google allows — embedded WebViews are
/// blocked), captures the code locally, and exchanges it for tokens.
struct GmailAuth {

    /// Run the full interactive sign-in; returns a fresh token set.
    func authorize() async throws -> TokenSet {
        guard let cfg = GmailConfig.current else { throw GmailAuthError.notConfigured }
        OAuthLog.log("authorize() start; client=\(cfg.clientID.prefix(24))…")

        let verifier = Self.randomURLSafe(64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

        let server = LoopbackServer()
        let port = try server.start()
        let redirect = "http://127.0.0.1:\(port)"

        var comps = URLComponents(url: GmailConfig.authEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: cfg.clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: GmailConfig.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        OAuthLog.log("opening browser; redirect=\(redirect)")
        let authorizationURL = comps.url!
        _ = await MainActor.run { NSWorkspace.shared.open(authorizationURL) }

        guard let code = await server.waitForCode() else {
            server.stop()
            OAuthLog.log("no code received → cancelled")
            throw GmailAuthError.cancelled
        }
        OAuthLog.log("code received; exchanging for tokens")
        let tokens = try await exchange(code: code, verifier: verifier, redirect: redirect, cfg: cfg)
        OAuthLog.log("token exchange OK")
        return tokens
    }

    /// Trade the authorization code for access + refresh tokens.
    private func exchange(code: String, verifier: String, redirect: String, cfg: GmailConfig) async throws -> TokenSet {
        let form = [
            "code": code,
            "client_id": cfg.clientID,
            "client_secret": cfg.clientSecret,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        let resp = try await postToken(form)
        guard let access = resp["access_token"] as? String,
              let refresh = resp["refresh_token"] as? String else {
            let msg = (resp["error_description"] as? String) ?? (resp["error"] as? String) ?? "no tokens returned"
            OAuthLog.log("token exchange FAILED: \(msg)")
            throw GmailAuthError.tokenExchangeFailed(msg)
        }
        let expires = (resp["expires_in"] as? Double) ?? 3600
        return TokenSet(accessToken: access, refreshToken: refresh, expiry: Date().addingTimeInterval(expires))
    }

    /// Use a stored refresh token to mint a new access token.
    func refresh(_ tokens: TokenSet) async throws -> TokenSet {
        guard let cfg = GmailConfig.current else { throw GmailAuthError.notConfigured }
        let form = [
            "client_id": cfg.clientID,
            "client_secret": cfg.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
        ]
        let resp = try await postToken(form)
        guard let access = resp["access_token"] as? String else {
            throw GmailAuthError.tokenExchangeFailed(resp["error_description"] as? String ?? "refresh failed")
        }
        let expires = (resp["expires_in"] as? Double) ?? 3600
        // Google usually omits a new refresh token on refresh — keep the old one.
        let newRefresh = (resp["refresh_token"] as? String) ?? tokens.refreshToken
        return TokenSet(accessToken: access, refreshToken: newRefresh, expiry: Date().addingTimeInterval(expires))
    }

    private func postToken(_ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: GmailConfig.tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: helpers
    static func randomURLSafe(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return base64URL(Data(bytes))
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    static func formEncode(_ s: String) -> String {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: cs) ?? s
    }
}
