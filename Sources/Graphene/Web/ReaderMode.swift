import SwiftUI

struct ReaderArticle {
    var title: String
    var url: URL
    var text: String
    var minutes: Int { max(1, Int(ceil(Double(text.split { $0.isWhitespace }.count) / 200))) }
}
struct ReaderOptions: Codable, Equatable {
    var serif = true
    var size: Double = 18
    var width: Double = 600
    var theme = "Light"
}
enum ReaderMode {
    static let extractor: String = {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "js") ?? Bundle.module.url(forResource: "reader", withExtension: "js") else { return "''" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "''"
    }()
}
struct ReaderPage: View {
    @EnvironmentObject var app: AppState
    let article: ReaderArticle
    private var options: ReaderOptions { app.settings.reader ?? ReaderOptions() }
    private var palette: Palette { Palette(mode: options.theme == "Dark" ? .dark : .light, space: options.theme == "Sepia" ? .clay : app.activeSpace.color, theme: nil) }
    private func option<T>(_ key: WritableKeyPath<ReaderOptions, T>) -> Binding<T> {
        Binding(get: { options[keyPath: key] }, set: { var next = options; next[keyPath: key] = $0; app.settings.reader = next })
    }
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Reader · \(article.minutes) min").foregroundStyle(palette.ink2); Spacer()
                Button("Done") { app.readerPresented = false }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
            HStack {
                Toggle("Serif", isOn: option(\.serif))
                Slider(value: option(\.size), in: 14...28, step: 1).accessibilityLabel("Reader font size")
                Picker("Theme", selection: option(\.theme)) { ForEach(["Light", "Sepia", "Dark"], id: \.self) { Text($0) } }
            }
            HStack { Text("Width"); Slider(value: option(\.width), in: 380...700, step: 20) }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(article.title).font(.system(size: options.size + 8, weight: .semibold, design: options.serif ? .serif : .default))
                    Text(article.url.host ?? "").font(.system(size: 12)).foregroundStyle(palette.ink2)
                    Text(article.text).font(.system(size: options.size, design: options.serif ? .serif : .default)).lineSpacing(7).textSelection(.enabled)
                }.frame(maxWidth: options.width, alignment: .leading).padding(20).frame(maxWidth: .infinity)
            }
            HStack {
                Button("Save to Vault") { app.vault.add(text: article.text, note: "", url: article.url, title: article.title, context: "Reader", spaceID: app.activeSpaceID); app.notify(app.vault.errorText ?? "Saved to Vault") }.disabled(app.isPrivate)
                Button("Ask about this") { app.readerPresented = false; app.sendToAsk("Explain this page") }.disabled(app.isPrivate)
                Spacer()
            }
        }.padding(24).frame(width: 760, height: 640).foregroundStyle(palette.ink).background(palette.ground.mixed(with: palette.sidebarBg, by: options.theme == "Sepia" ? 0.6 : 0))
            .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }
}
