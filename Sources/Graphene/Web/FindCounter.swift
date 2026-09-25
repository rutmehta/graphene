import Foundation

struct FindCounter {
    static func script(query: String, backwards: Bool) -> String {
        guard let url = Bundle.module.url(forResource: "find", withExtension: "js"), let script = try? String(contentsOf: url, encoding: .utf8) else { return "null" }
        return script.replacingOccurrences(of: "BACKWARDS_VALUE", with: backwards ? "true" : "false").replacingOccurrences(of: "QUERY_VALUE", with: jsLiteral(query))
    }
    mutating func select(query: String, current: Int, total: Int) {
        self.query = query; self.total = max(0, total); self.current = max(0, min(current, self.total))
    }
    private(set) var query = ""
    private(set) var current = 0
    private(set) var total = 0
    mutating func update(query: String, total: Int, backwards: Bool, found: Bool) {
        let changed = self.query != query || self.total != total
        self.query = query; self.total = max(0, total)
        guard found, total > 0, !query.isEmpty else { current = 0; return }
        if changed || current == 0 { current = backwards ? total : 1 }
        else { current = (current - 1 + (backwards ? -1 : 1) + total) % total + 1 }
    }
}
