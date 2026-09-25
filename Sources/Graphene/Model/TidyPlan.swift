import Foundation

/// Tidy Today (landing-and-tidy.md §4): groups a space's Today tabs into named folders.
/// Pure: the input is a snapshot of the Today list, the output is the groups and the loose
/// tabs; `AppState.tidyToday()` applies it.
struct TidyPlan: Equatable {
    /// One Today tab as the planner sees it, in list order.
    struct Input: Equatable {
        let id: UUID
        let title: String
        let host: String?
        /// The participating provenance parent (an open Today tab of the same list), if any.
        var parentID: UUID? = nil
        var threadID: UUID? = nil
    }

    enum Kind: Equatable {
        /// Holds at least one provenance branch (and any single tabs of the same thread).
        case branch
        /// Single tabs of one thread.
        case thread
        /// Single tabs of one site whose threads had one page each.
        case host
    }

    struct Group: Equatable {
        var name: String
        var kind: Kind
        /// Members in list order; a branch's tabs stay parent before children.
        var tabIDs: [UUID]
        /// Member titles, for the optional on-device name.
        var titles: [String]
    }

    var groups: [Group] = []
    /// Tabs left in the Today list, in list order.
    var loose: [UUID] = []

    /// Tabs moved into folders.
    var tidiedCount: Int { groups.reduce(0) { $0 + $1.tabIDs.count } }

    /// Words kept from a root's title for a group's name.
    static let nameWords = 3

    /// Step 1: every branch (a root with children) is one unit and is never split.
    /// Step 2: units group by the root's thread; singles whose thread has no other unit group by site.
    /// Step 3: groups of one tab stay loose. Step 4: each group is named.
    static func make(_ tabs: [Input]) -> TidyPlan {
        let ids = tabs.map(\.id)
        let byID = Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var parents: [UUID: UUID] = [:]
        for tab in tabs { if let parent = tab.parentID, parent != tab.id, byID[parent] != nil { parents[tab.id] = parent } }

        // Units in list order of their root: a branch in pre-order, or a single tab.
        var units: [[UUID]] = [], current: [UUID] = []
        for row in ThreadBranch.rows(ids: ids, parents: parents) {
            if row.depth == 0, !current.isEmpty { units.append(current); current = [] }
            current.append(row.id)
        }
        if !current.isEmpty { units.append(current) }
        let order = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        units.sort { (order[$0[0]] ?? 0) < (order[$1[0]] ?? 0) }

        // Step 2a: units sharing their root's thread.
        var threadUnits: [UUID: [Int]] = [:]
        for (index, unit) in units.enumerated() { if let thread = byID[unit[0]]?.threadID { threadUnits[thread, default: []].append(index) } }
        var drafts: [(first: Int, kind: Kind, units: [Int])] = [], placed = Set<Int>()
        for (index, unit) in units.enumerated() where !placed.contains(index) {
            guard let thread = byID[unit[0]]?.threadID, let members = threadUnits[thread] else { continue }
            let size = members.reduce(0) { $0 + units[$1].count }
            guard size > 1 else { continue }
            let hasBranch = members.contains { units[$0].count > 1 }
            drafts.append((index, hasBranch ? .branch : .thread, members))
            placed.formUnion(members)
        }
        // A branch without thread company is still its own group.
        for (index, unit) in units.enumerated() where !placed.contains(index) && unit.count > 1 {
            drafts.append((index, .branch, [index])); placed.insert(index)
        }
        // Step 2b: remaining singles by site.
        var hostUnits: [String: [Int]] = [:], hostOrder: [String] = []
        for (index, unit) in units.enumerated() where !placed.contains(index) {
            guard let host = byID[unit[0]]?.host.flatMap(siteKey) else { continue }
            if hostUnits[host] == nil { hostOrder.append(host) }
            hostUnits[host, default: []].append(index)
        }
        for host in hostOrder {
            guard let members = hostUnits[host], members.count > 1 else { continue }
            drafts.append((members[0], .host, members)); placed.formUnion(members)
        }

        // Step 3 and 4: order groups by their first tab; name them; the rest stays loose.
        var plan = TidyPlan()
        for draft in drafts.sorted(by: { $0.first < $1.first }) {
            let memberIDs = draft.units.flatMap { units[$0] }
            let titles = memberIDs.compactMap { byID[$0]?.title }
            let lead = byID[units[draft.units.first { units[$0].count > 1 } ?? draft.units[0]][0]]
            let name: String
            switch draft.kind {
            case .host: name = siteName(lead?.host) ?? "Tabs"
            case .branch, .thread: name = shortTitle(lead?.title ?? "") ?? siteName(lead?.host) ?? "Tabs"
            }
            plan.groups.append(Group(name: name, kind: draft.kind, tabIDs: memberIDs, titles: titles))
        }
        plan.loose = units.enumerated().filter { !placed.contains($0.offset) }.flatMap(\.element)
        return plan
    }

    // MARK: naming

    /// Separators a page title uses before its site name ("Graphene - Wikipedia").
    private static let titleSeparators = [" - ", " – ", " — ", " | ", " · ", " :: "]

    /// A title's lead part trimmed to `nameWords` words, without trailing punctuation.
    static func shortTitle(_ title: String) -> String? {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in titleSeparators {
            if let range = text.range(of: separator), !text[..<range.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
                text = String(text[..<range.lowerBound])
            }
        }
        let words = text.split(whereSeparator: \.isWhitespace).prefix(nameWords).joined(separator: " ")
        let trimmed = words.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Leading labels that are not the site's name.
    private static let hostPrefixes: Set<String> = ["www", "m", "mobile", "en", "app"]
    /// Second-level labels that belong to a country suffix ("co.uk").
    private static let secondLevel: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu"]

    /// The host a tab groups by: lowercased, without a leading "www.".
    static func siteKey(_ host: String) -> String? {
        var host = host.lowercased().trimmingCharacters(in: .whitespaces)
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }

    /// "en.wikipedia.org" → "Wikipedia", "bbc.co.uk" → "Bbc", "localhost" → "Localhost".
    static func siteName(_ host: String?) -> String? {
        guard let host = host.flatMap(siteKey) else { return nil }
        var labels = host.split(separator: ".").map(String.init)
        if labels.count > 1 { labels.removeLast() }
        if labels.count > 1, let last = labels.last, secondLevel.contains(last), host.split(separator: ".").last?.count == 2 { labels.removeLast() }
        while labels.count > 1, let first = labels.first, hostPrefixes.contains(first) { labels.removeFirst() }
        guard let name = labels.last, !name.isEmpty else { return nil }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
