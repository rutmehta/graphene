import Foundation

enum SearchSuggestions {
    static func parse(_ data: Data, engine: SearchEngine) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let strings: [String]
        switch engine {
        case .google: strings = (object as? [Any])?[safe: 1] as? [String] ?? []
        case .duckduckgo: strings = (object as? [[String: Any]])?.compactMap { $0["phrase"] as? String } ?? []
        }
        var seen = Set<String>()
        return Array(strings.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(5))
    }
    static func fetch(_ query: String, engine: SearchEngine) async throws -> [String] {
        let base = engine == .google ? "https://suggestqueries.google.com/complete/search?client=firefox" : "https://duckduckgo.com/ac/"
        var components = URLComponents(string: base)!
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "q", value: query)]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: components.url!)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 128_000 else { return [] }
        return parse(data, engine: engine)
    }
}
