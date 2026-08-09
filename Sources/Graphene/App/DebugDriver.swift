import Foundation

/// A dev-only command channel so the app can be driven deterministically without
/// GUI automation: write a line to `cmd.txt` and it runs a real app action. Only
/// active when launched with GRAPHENE_DEBUG=1.
extension AppState {
    func startDebugDriverIfEnabled() {
        guard ProcessInfo.processInfo.environment["GRAPHENE_DEBUG"] == "1" else { return }
        let cmdFile = Paths.root.appendingPathComponent("cmd.txt")
        try? "".write(to: cmdFile, atomically: true, encoding: .utf8)
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let content = try? String(contentsOf: cmdFile, encoding: .utf8),
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                try? "".write(to: cmdFile, atomically: true, encoding: .utf8)
                for line in content.split(separator: "\n") {
                    AppState.shared.runDebugCommand(String(line))
                }
            }
        }
    }

    private func runDebugCommand(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let cmd = parts.first else { return }
        let arg = parts.count > 1 ? parts[1] : ""
        switch cmd {
        case "go":       submit(arg)
        case "new":      newTab()
        case "select":   if let i = Int(arg), let t = tabs[safe: i] { activate(t.id) }
        case "close":    if let id = activeTabID { closeTab(id) }
        case "graph":    showGraph = (arg != "off")
        case "notes":    showAnnotations = (arg != "off")
        case "sidebar":  if let w = Double(arg) { sidebarWidth = CGFloat(w) }
        case "annotate":
            if let tab = activeTab {
                self.tab(tab, didCapture: CapturedAnnotation(
                    text: arg, note: "", url: tab.url, title: tab.title, context: ""))
            }
        default: break
        }
    }
}
