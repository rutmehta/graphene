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
/// Native reader sheet. Colours come from the shared `app.pal` reading tokens (`rd*`),
/// so the reader no longer builds its own `Palette`; the article keeps its reading face.
struct ReaderPage: View {
    @EnvironmentObject var app: AppState
    let article: ReaderArticle
    private var options: ReaderOptions { app.settings.reader ?? ReaderOptions() }
    private var dark: Bool { options.theme == "Dark" }
    /// Light and Sepia read on the paper sheet (Sepia warms it with the Clay preset);
    /// Dark inverts the reading ramp.
    private var sheet: Color {
        let pal = app.pal
        switch options.theme {
        case "Dark": return pal.rdInk
        case "Sepia": return pal.rdBg.mixed(with: SpaceColor.clay.c1, by: 0.14)
        default: return pal.rdBg
        }
    }
    private var ink: Color { dark ? app.pal.rdHair : app.pal.rdInk }
    private var ink2: Color { dark ? app.pal.rdInk3 : app.pal.rdInk2 }
    private func option<T>(_ key: WritableKeyPath<ReaderOptions, T>) -> Binding<T> {
        Binding(get: { options[keyPath: key] }, set: { var next = options; next[keyPath: key] = $0; app.settings.reader = next })
    }
    /// The reading face: serif or system at the reader's own size, outside the shell type scale.
    private func readingFace(_ size: Double, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: options.serif ? .serif : .default)
    }
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Reader · \(article.minutes) min").font(ShellType.secondary).foregroundStyle(ink2); Spacer()
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
                    Text(article.title).font(readingFace(options.size + 8, weight: .semibold))
                    Text(article.url.host ?? "").font(ShellType.secondary).foregroundStyle(ink2)
                    Text(article.text).font(readingFace(options.size)).lineSpacing(7).textSelection(.enabled)
                }.frame(maxWidth: options.width, alignment: .leading).padding(20).frame(maxWidth: .infinity)
            }
            HStack {
                Button("Save to Vault") { app.vault.add(text: article.text, note: "", url: article.url, title: article.title, context: "Reader", spaceID: app.activeSpaceID); app.notify(app.vault.errorText ?? "Saved to Vault") }.disabled(app.isPrivate)
                Button("Ask about this") { app.readerPresented = false; app.sendToAsk("Explain this page") }.disabled(app.isPrivate)
                Spacer()
            }
        }.font(ShellType.body).padding(24).frame(width: 760, height: 640).foregroundStyle(ink).background(sheet).tint(app.pal.accent)
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}
