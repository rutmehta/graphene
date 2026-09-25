import SwiftUI

enum ChatMarkdown {
    struct Block: Identifiable {
        var id: Int
        var text: String
        var code: Bool
    }
    static func blocks(_ text: String) -> [Block] {
        var result: [Block] = [], lines: [String] = []
        var code = false
        func flush() {
            if !lines.isEmpty { result.append(Block(id: result.count, text: lines.joined(separator: "\n"), code: code)); lines = [] }
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") { flush(); code.toggle() }
            else if line.isEmpty && !code { flush() }
            else { lines.append(line) }
        }
        flush(); return result
    }
    static func citations(_ text: String, sources: [KnowledgeSource]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+)\](?:\([^)]*\))?"#) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let numberRange = Range(match.range(at: 1), in: text), let range = Range(match.range, in: result), let number = Int(text[numberRange]) else { continue }
            result.replaceSubrange(range, with: number > 0 && number <= sources.count ? "[\(number)](graphene-source://\(number))" : "[unverified source]")
        }
        return result
    }
}
struct ChatMarkdownView: View {
    @EnvironmentObject var app: AppState
    let text: String
    let sources: [KnowledgeSource]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ChatMarkdown.blocks(text)) { block in
                if block.code {
                    ScrollView(.horizontal) { Text(block.text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(10) }
                        .background(app.pal.hover, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    let heading = block.text.hasPrefix("#")
                    let value = heading ? block.text.drop(while: { $0 == "#" || $0 == " " }).description : block.text
                    Text((try? AttributedString(markdown: ChatMarkdown.citations(value, sources: sources), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value))
                        .font(.system(size: heading ? 16 : 13, weight: heading ? .semibold : .regular)).lineSpacing(4).textSelection(.enabled)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "graphene-source", let number = Int(url.host ?? ""), sources.indices.contains(number - 1), let target = URL(string: sources[number - 1].url), ["https", "http"].contains(target.scheme ?? "") {
                    app.openTab(url: target, parent: nil, activate: true); return .handled
                }
                if ["http", "https"].contains(url.scheme ?? "") { app.openTab(url: url, parent: nil, activate: true); return .handled }
                return .discarded
            })
    }
}
