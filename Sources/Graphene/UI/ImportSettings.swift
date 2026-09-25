import SwiftUI
import AppKit

struct ImportSettings: View {
    @EnvironmentObject var app: AppState
    @State private var browser = Importer.Browser.arc
    @State private var batch: ImportBatch?
    @State private var busy = false
    @State private var progress = 0.0
    @State private var status = ""
    @State private var summary = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import bookmarks and history without changing the source browser. Passwords are never imported. Arc imports Spaces, pins and Favorites, not Today tabs or history.").foregroundStyle(app.pal.ink2)
            Picker("Browser", selection: $browser) { ForEach(Importer.Browser.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            HStack {
                Button("Preview import") { read(nil) }
                Button("Choose bookmarks/sidebar file…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = false
                    if panel.runModal() == .OK { read(panel.url) }
                }
            }.disabled(busy)
            Text("Safari access may require System Settings → Privacy & Security → Full Disk Access → Graphene, then restart Graphene. Chrome defaults to its Default profile; choose a Bookmarks file for another profile. No permissions are granted automatically.").font(.system(size: 12)).foregroundStyle(app.pal.ink3)
            if busy { ProgressView(value: progress) }
            if let batch {
                Text("Ready: \(batch.bookmarks.count) bookmarks, \(batch.history.count) history pages, \(batch.spaces.count) Arc spaces.")
                Button("Import into Graphene") { apply(batch) }.disabled(busy)
            }
            if !status.isEmpty { Text(status).textSelection(.enabled) }
        }.sheet(isPresented: $summary) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Import summary").font(.headline)
                Text(status).textSelection(.enabled)
                Button("Done") { summary = false }.keyboardShortcut(.defaultAction)
            }.padding(24).frame(width: 480).foregroundStyle(app.pal.ink).background(app.pal.ground)
        }
    }
    private func read(_ file: URL?) {
        busy = true; progress = 0; status = "Reading source…"; batch = nil
        Task { @MainActor in
            await Task.yield()
            do { batch = try Importer.read(browser, file: file); status = batch?.warnings.joined(separator: "\n") ?? "" }
            catch { status = "Couldn’t read \(browser.rawValue): \(error.localizedDescription). For Safari, see Full Disk Access instructions above." }
            busy = false
        }
    }
    private func apply(_ batch: ImportBatch) {
        busy = true
        Task { @MainActor in
            status = await app.applyImport(batch) { progress = $0 }
            self.batch = nil; busy = false; progress = 1; summary = true
        }
    }
}
