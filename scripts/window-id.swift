// Prints the CGWindowID of the frontmost on-screen window owned by the process whose name
// (or PID, with -p) matches. Use with: screencapture -l "$(swift scripts/window-id.swift Graphene)" -o out.png
import AppKit
let args = CommandLine.arguments.dropFirst()
var pid: pid_t? = nil; var name = "Graphene"
if let i = args.firstIndex(of: "-p"), let v = Int32(args[args.index(after: i)]) { pid = v } else if let n = args.first { name = n }
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let ownerPID = w[kCGWindowOwnerPID as String] as? Int32 ?? -1
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    guard layer == 0, (bounds["Width"] ?? 0) > 300 else { continue }
    if let pid { guard ownerPID == pid else { continue } } else { guard owner == name else { continue } }
    if let id = w[kCGWindowNumber as String] as? Int { print(id); exit(0) }
}
FileHandle.standardError.write("no window found\n".data(using: .utf8)!); exit(1)
