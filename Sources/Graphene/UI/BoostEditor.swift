import SwiftUI

struct BoostEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let host: String
    @State private var draft = Boost(host: "")
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Boost · \(host)").font(ShellType.title); Spacer(); Toggle("Enabled", isOn: $draft.enabled) }
            TabView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker("Font", selection: $draft.font) { ForEach(["Default", "Serif", "Sans"], id: \.self) { Text($0) } }
                        Picker("Scheme", selection: $draft.preset) { ForEach(["Default", "Dim", "Sepia", "Contrast"], id: \.self) { Text($0) } }
                    }
                    HStack { Text("Text scale"); Slider(value: $draft.scale, in: 0.5...2, step: 0.1); Text("\(Int(draft.scale * 100))%") }
                    TextEditor(text: $draft.css).font(ShellType.secondary.monospaced()).overlay { RoundedRectangle(cornerRadius: ShellLayout.rowRadius).strokeBorder(app.pal.hairline) }
                    HStack { Text("\(draft.selectors.count) zapped elements"); Spacer(); Button("Restore zapped elements") { draft.selectors = [] } }
                }.padding(12).tabItem { Text("Style") }
                VStack(alignment: .leading, spacing: 12) {
                    SettingsHelp("JavaScript runs on this host after each page loads. Only use code you trust. Saving changes requires a reload to run or undo code.")
                    TextEditor(text: $draft.javascript).font(ShellType.secondary.monospaced()).overlay { RoundedRectangle(cornerRadius: ShellLayout.rowRadius).strokeBorder(app.pal.hairline) }
                }.padding(12).tabItem { Text("Code") }
            }
            Text(status).font(ShellType.secondary).foregroundStyle(app.pal.danger)
            HStack {
                Button("Cancel") { dismiss() }; Spacer()
                Button("Save Boost") {
                    do { try app.boosts.save(draft); for tab in app.tabs { (tab.loadedEngine as? WKWebEngine)?.refreshBoosts() }; dismiss() }
                    catch { status = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.font(ShellType.body).padding(24).frame(width: 620, height: 510).tint(app.pal.accent)
            .onAppear { draft = app.boosts.boost(host) }
    }
}

struct BoostSettings: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var store: Boosts
    @State private var selected: String?
    var body: some View {
        Form {
            Section {
                if let error = store.error { Text(error).font(ShellType.secondary).foregroundStyle(app.pal.danger) }
                if store.items.isEmpty { Text("Open a website’s Site controls to create a Boost.") }
                ForEach(store.items) { boost in
                    HStack { Text(boost.host); Text(boost.enabled ? "On" : "Off").foregroundStyle(app.pal.ink3); Spacer(); Button("Edit…") { selected = boost.host } }
                }
            } footer: {
                SettingsHelp("Boosts apply to an exact host. CSS updates immediately; JavaScript changes require reloading the page.")
            }
        }.sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let selected { BoostEditor(host: selected) }
        }
    }
}
