import SwiftUI

struct BoostEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let host: String
    @State private var draft = Boost(host: "")
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Boost · \(host)").font(.headline); Spacer(); Toggle("Enabled", isOn: $draft.enabled) }
            TabView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker("Font", selection: $draft.font) { ForEach(["Default", "Serif", "Sans"], id: \.self) { Text($0) } }
                        Picker("Scheme", selection: $draft.preset) { ForEach(["Default", "Dim", "Sepia", "Contrast"], id: \.self) { Text($0) } }
                    }
                    HStack { Text("Text scale"); Slider(value: $draft.scale, in: 0.5...2, step: 0.1); Text("\(Int(draft.scale * 100))%") }
                    TextEditor(text: $draft.css).font(.system(size: 12)).border(app.pal.hairline)
                    HStack { Text("\(draft.selectors.count) zapped elements"); Spacer(); Button("Restore zapped elements") { draft.selectors = [] } }
                }.padding(12).tabItem { Text("Style") }
                VStack(alignment: .leading, spacing: 12) {
                    Text("JavaScript runs on this host after each page loads. Only use code you trust. Saving changes requires a reload to run or undo code.").foregroundStyle(app.pal.ink2)
                    TextEditor(text: $draft.javascript).font(.system(size: 12)).border(app.pal.hairline)
                }.padding(12).tabItem { Text("Code") }
            }
            Text(status).font(.system(size: 12)).foregroundStyle(app.pal.ink2)
            HStack {
                Button("Cancel") { dismiss() }; Spacer()
                Button("Save Boost") {
                    do { try app.boosts.save(draft); for tab in app.tabs { (tab.loadedEngine as? WKWebEngine)?.refreshBoosts() }; dismiss() }
                    catch { status = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 620, height: 510).foregroundStyle(app.pal.ink).background(app.pal.ground)
            .onAppear { draft = app.boosts.boost(host) }
    }
}

struct BoostSettings: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var store: Boosts
    @State private var selected: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Boosts apply to an exact host. CSS updates immediately; JavaScript changes require reloading the page.").foregroundStyle(app.pal.ink2)
            if let error = store.error { Text(error) }
            if store.items.isEmpty { Text("Open a website’s Site controls to create a Boost.") }
            ForEach(store.items) { boost in
                HStack { Text(boost.host); Text(boost.enabled ? "On" : "Off").foregroundStyle(app.pal.ink3); Spacer(); Button("Edit…") { selected = boost.host } }
            }
        }.sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let selected { BoostEditor(host: selected) }
        }
    }
}
