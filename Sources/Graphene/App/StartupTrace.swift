import Foundation
import os

/// The launch timeline, for `GRAPHENE_TRACE=1`: each mark prints the milliseconds since the
/// process started to stderr (`[trace] +123.4 ms label`) and emits an os_signpost event in the
/// Points of Interest category for Instruments. Without the variable every call returns at once.
enum StartupTrace {
    static let enabled = ProcessInfo.processInfo.environment["GRAPHENE_TRACE"] == "1"
    private static let log = OSLog(subsystem: "app.graphene", category: .pointsOfInterest)

    /// When the kernel started this process, so time spent before `main` (dyld, static
    /// initialisers) is counted too.
    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return Date() }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }()

    @MainActor static var firstFrameMarked = false
    @MainActor private static var marked: Set<String> = []

    /// Marks `label` the first time only (a view body's first evaluation).
    @MainActor static func once(_ label: String) {
        guard enabled, marked.insert(label).inserted else { return }
        mark(label)
    }

    static func elapsed() -> Double { Date().timeIntervalSince(processStart) * 1000 }

    static func mark(_ label: @autoclosure () -> String) {
        guard enabled else { return }
        let text = label()
        os_signpost(.event, log: log, name: "startup", "%{public}s", text)
        FileHandle.standardError.write(Data(String(format: "[trace] +%.1f ms %@\n", elapsed(), text).utf8))
    }

    /// Runs `body` and marks how long it took.
    @discardableResult
    static func measure<T>(_ label: @autoclosure () -> String, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let start = CFAbsoluteTimeGetCurrent()
        let result = try body()
        let text = label()
        os_signpost(.event, log: log, name: "startup", "%{public}s", text)
        FileHandle.standardError.write(Data(String(format: "[trace] +%.1f ms %@ (%.1f ms)\n", elapsed(), text, (CFAbsoluteTimeGetCurrent() - start) * 1000).utf8))
        return result
    }
}
