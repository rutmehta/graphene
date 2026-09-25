import Foundation

struct DialogGuard {
    private var events: [String: [Date]] = [:]
    var suppressed: Set<String> = []
    mutating func record(_ origin: String, at date: Date) -> Bool {
        events = events.mapValues { $0.filter { date.timeIntervalSince($0) < 10 } }.filter { !$0.value.isEmpty }
        let recent = events[origin] ?? []
        events[origin] = Array((recent + [date]).suffix(4))
        return recent.count >= 3
    }
}
