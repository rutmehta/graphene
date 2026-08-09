import Foundation

/// Resolves what the address bar should do with a string: open a URL, or run a
/// search (and remember the query as the "why" behind the resulting page).
enum Omnibox {
    enum Action {
        case navigate(URL)
        case search(URL, query: String)
    }

    static func resolve(_ input: String, engine: SearchEngine = .google) -> Action? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        if let url = asURL(s) { return .navigate(url) }
        let q = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        guard let searchURL = URL(string: engine.prefix + q) else { return nil }
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
