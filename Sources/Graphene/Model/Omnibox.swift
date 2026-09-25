import Foundation

/// Resolves what the address bar should do with a string: open a URL, or run a
/// search (and remember the query as the "why" behind the resulting page).
enum Omnibox {
    static func acceptsCompletion(_ text: String, selection: NSRange) -> Bool {
        selection.length == 0 && selection.location == (text as NSString).length
    }
    static func isQuestion(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, asURL(text) == nil else { return false }
        let first = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return text.hasSuffix("?") || text.contains("@") || ["who", "what", "why", "how", "explain", "summarize", "compare"].contains(first)
    }

    /// Return a full completion, preserving the typed prefix's casing.
    static func completion(_ prefix: String, candidates: [String]) -> String? {
        guard !prefix.isEmpty else { return nil }
        for candidate in candidates {
            var value = candidate
            if !prefix.contains("://") {
                for scheme in ["https://", "http://"] where value.hasPrefix(scheme) { value = String(value.dropFirst(scheme.count)) }
            }
            if value.count > prefix.count, value.lowercased().hasPrefix(prefix.lowercased()) {
                return prefix + value.dropFirst(prefix.count)
            }
        }
        return nil
    }
    enum Action {
        case navigate(URL)
        case search(URL, query: String)
    }

    static func resolve(_ input: String, engine: SearchEngine = .google, customSearchURL: String? = nil) -> Action? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        if let url = asURL(s) { return .navigate(url) }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let q = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        let target: String
        if let template = customSearchURL {
            guard template.contains("%s") else { return nil }
            target = template.replacingOccurrences(of: "%s", with: q)
        } else { target = engine.prefix + q }
        guard let searchURL = URL(string: target), ["http", "https"].contains(searchURL.scheme ?? ""), searchURL.host != nil else { return nil }
        return .search(searchURL, query: s)
    }

    static func asURL(_ s: String) -> URL? {
        if s.hasPrefix("http://") || s.hasPrefix("https://") || s.hasPrefix("graphene://") {
            return URL(string: s)
        }
        if s.hasPrefix("localhost") { return URL(string: "http://" + s) }
        // bare domain like example.com / sub.example.co.uk/path — no spaces, has a dot
        if !s.contains(" "), s.contains(".") {
            let head = s.split(separator: "/").first.map(String.init) ?? s
            if head.contains("."), !head.hasSuffix(".") {
                return URL(string: "https://" + s)
            }
        }
        return nil
    }
}

enum SearchEngine: String, Codable, CaseIterable {
    case google, duckduckgo

    var prefix: String {
        switch self {
        case .google: return "https://www.google.com/search?q="
        case .duckduckgo: return "https://duckduckgo.com/?q="
        }
    }
}
