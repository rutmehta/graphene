import Foundation

struct RoutingRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var pattern: String
    var spaceID: UUID
    var enabled = true

    /// Anchored glob over the complete URL. Only * and ? are wildcards.
    func matches(_ url: URL) -> Bool {
        guard enabled, !pattern.isEmpty, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        let regex = pattern.map { character -> String in
            switch character {
            case "*": return ".*"
            case "?": return "."
            default: return NSRegularExpression.escapedPattern(for: String(character))
            }
        }.joined()
        return url.absoluteString.range(of: "\\A" + regex + "\\z", options: .regularExpression) != nil
    }
}
