import Foundation
import SwiftUI

enum GmailError: LocalizedError {
    case unauthorized
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Gmail session expired."
        case .http(let c): return "Gmail request failed (\(c))."
        }
    }
}

/// Read-only Gmail REST client. Lists the inbox and fetches per-message metadata.
enum GmailClient {
    private static let base = "https://gmail.googleapis.com/gmail/v1/users/me"
    static func accountAddress(accessToken: String) async throws -> String {
        struct Profile: Decodable { let emailAddress: String }
        return try JSONDecoder().decode(Profile.self, from: await get(URL(string: "\(base)/profile")!, token: accessToken)).emailAddress
    }

    static func listInbox(accessToken: String, max: Int = 18) async throws -> [MailItem] {
        let listURL = URL(string: "\(base)/messages?maxResults=\(max)&labelIds=INBOX")!
        let listData = try await get(listURL, token: accessToken)
        let list = (try? JSONSerialization.jsonObject(with: listData) as? [String: Any]) ?? [:]
        let refs = (list["messages"] as? [[String: Any]]) ?? []
        var items: [MailItem] = []
        for ref in refs {
            guard let id = ref["id"] as? String else { continue }
            if let item = try? await fetch(id: id, accessToken: accessToken) { items.append(item) }
        }
        return items
    }

    private static func fetch(id: String, accessToken: String) async throws -> MailItem {
        var comps = URLComponents(string: "\(base)/messages/\(id)")!
        comps.queryItems = [
            .init(name: "format", value: "metadata"),
            .init(name: "metadataHeaders", value: "From"),
            .init(name: "metadataHeaders", value: "Subject"),
            .init(name: "metadataHeaders", value: "Date"),
        ]
        let data = try await get(comps.url!, token: accessToken)
        let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let snippet = (msg["snippet"] as? String) ?? ""
        let labelIds = (msg["labelIds"] as? [String]) ?? []
        let payload = (msg["payload"] as? [String: Any]) ?? [:]
        let headers = (payload["headers"] as? [[String: Any]]) ?? []
        func header(_ name: String) -> String {
            headers.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }?["value"] as? String ?? ""
        }
        let (name, address) = parseFrom(header("From"))
        let date = Self.parseDate(header("Date"), fallbackMillis: msg["internalDate"] as? String)
        return MailItem(
            id: id,
            from: name.isEmpty ? address : name,
            address: address,
            subject: header("Subject").isEmpty ? "(no subject)" : header("Subject"),
            preview: decodeEntities(snippet),
            date: date,
            unread: labelIds.contains("UNREAD"),
            initial: String((name.isEmpty ? address : name).first.map(String.init) ?? "?").uppercased(),
            colorHex: color(for: address),
            body: [decodeEntities(snippet)],
            threadID: msg["threadId"] as? String
        )
    }

    /// Fetch the full message and extract its HTML (preferred) or plain-text body.
    static func fetchBody(id: String, accessToken: String) async throws -> EmailBody {
        let url = URL(string: "\(base)/messages/\(id)?format=full")!
        let data = try await get(url, token: accessToken)
        let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let payload = (msg["payload"] as? [String: Any]) ?? [:]
        var html: String?
        var text = ""
        func walk(_ part: [String: Any]) {
            let mime = (part["mimeType"] as? String) ?? ""
            let body = (part["body"] as? [String: Any]) ?? [:]
            if let dataStr = body["data"] as? String, let decoded = decodeB64URL(dataStr) {
                if mime == "text/html", html == nil { html = decoded }
                else if mime == "text/plain", text.isEmpty { text = decoded }
            }
            if let parts = part["parts"] as? [[String: Any]] { parts.forEach(walk) }
        }
        walk(payload)
        if html == nil && text.isEmpty { text = (msg["snippet"] as? String) ?? "" }
        return EmailBody(html: html, text: text)
    }

    private static func decodeB64URL(_ s: String) -> String? {
        var str = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while str.count % 4 != 0 { str += "=" }
        guard let d = Data(base64Encoded: str, options: .ignoreUnknownCharacters) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func get(_ url: URL, token: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 401 { throw GmailError.unauthorized }
            if http.statusCode >= 400 { throw GmailError.http(http.statusCode) }
        }
        return data
    }

    // MARK: parsing helpers
    private static func parseFrom(_ raw: String) -> (String, String) {
        // "Display Name <email@x.com>"  or  "email@x.com"
        if let open = raw.firstIndex(of: "<"), let close = raw.firstIndex(of: ">") {
            let email = String(raw[raw.index(after: open)..<close])
            var name = String(raw[..<open]).trimmingCharacters(in: .whitespaces)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return (name, email)
        }
        return ("", raw.trimmingCharacters(in: .whitespaces))
    }

    private static func parseDate(_ raw: String, fallbackMillis: String?) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz"] {
            f.dateFormat = fmt
            if let d = f.date(from: raw) { return d }
        }
        if let ms = fallbackMillis, let millis = Double(ms) { return Date(timeIntervalSince1970: millis / 1000) }
        return Date()
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    /// A stable, muted color per sender.
    private static func color(for address: String) -> String {
        let palette = ["3b6ea5", "5b8a5b", "8a6f4a", "6a5a8a", "a5503b", "4a6a7a", "7a5a7a", "5f7a4a"]
        var h = 5381
        for b in address.utf8 { h = ((h << 5) &+ h) &+ Int(b) }
        return palette[abs(h) % palette.count]
    }
}
