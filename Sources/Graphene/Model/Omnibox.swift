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

/// Command bar geometry and sectioning (arc-look.md §3.4), kept free of views so it can be tested.
enum CommandBarLayout {
    /// `min(commandWidth, window − commandMargin)`, never negative.
    static func width(window: CGFloat) -> CGFloat {
        max(0, min(ShellLayout.commandWidth, window - ShellLayout.commandMargin))
    }

    /// Distance from the window's top edge to the card's top edge.
    static func top(window height: CGFloat) -> CGFloat {
        max(0, height) * ShellLayout.commandTop
    }

    /// Indices of results that open a section. Labels show only when more than one section is present.
    static func sectionStarts(_ sections: [String]) -> Set<Int> {
        guard Set(sections).count > 1 else { return [] }
        return Set(sections.indices.filter { $0 == 0 || sections[$0 - 1] != sections[$0] })
    }

    /// The result list's height: at most `commandMaxRows` rows plus the section labels among them,
    /// top padding when the list does not open with a label, and bottom padding. Anything more scrolls.
    static func listHeight(_ sections: [String]) -> CGFloat {
        guard !sections.isEmpty else { return 0 }
        let starts = sectionStarts(sections)
        let visible = min(sections.count, ShellLayout.commandMaxRows)
        let labels = starts.filter { $0 < visible }.count
        let top = starts.contains(0) ? 0 : ShellLayout.commandListPadding
        return CGFloat(visible) * ShellLayout.commandRowHeight + CGFloat(labels) * ShellLayout.commandSectionHeight
            + top + ShellLayout.commandListPadding
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
