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

    /// A run of answer text, or a `[n]` citation marker (the model's source number).
    enum Segment: Equatable {
        case text(String)
        case marker(Int)
    }
    /// Splits a line at its `[n]` markers (and any `(url)` the model appended to one).
    static func segments(_ line: String) -> [Segment] {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+)\](?:\([^)]*\))?"#) else { return [.text(line)] }
        var result: [Segment] = [], cursor = line.startIndex
        for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            guard let range = Range(match.range, in: line), let number = Range(match.range(at: 1), in: line).flatMap({ Int(line[$0]) }) else { continue }
            if cursor < range.lowerBound { result.append(.text(String(line[cursor..<range.lowerBound]))) }
            result.append(.marker(number)); cursor = range.upperBound
        }
        if cursor < line.endIndex { result.append(.text(String(line[cursor...]))) }
        return result
    }
    static func hasMarkers(_ text: String) -> Bool { text.range(of: #"\[\d+\]"#, options: .regularExpression) != nil }

    /// The text of a block that quotes a page: a `>` block quote, or a block wholly in quotation
    /// marks whose words appear verbatim in one of the answer's sources. `nil` otherwise.
    static func quote(_ block: String, sources: [KnowledgeSource]) -> String? {
        let lines = block.components(separatedBy: "\n")
        if lines.allSatisfy({ $0.hasPrefix(">") }) {
            return lines.map { String($0.dropFirst()).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        }
        let trimmed = block.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, let last = trimmed.last, trimmed.count > 2, "\"“".contains(first), "\"”".contains(last) else { return nil }
        let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        let wanted = normalized(inner)
        guard !wanted.isEmpty, sources.contains(where: { normalized($0.text).contains(wanted) }) else { return nil }
        return inner
    }
    /// Whitespace-collapsed, case-folded text: the same normalisation the page search uses.
    static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Inline markdown for `text`, falling back to the plain string.
    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    /// Words of `text`, each keeping its markdown attributes and trailing whitespace, for the flow layout.
    static func words(_ text: String) -> [AttributedString] {
        let attributed = attributed(text)
        var result: [AttributedString] = []
        var start = attributed.startIndex, index = attributed.startIndex, sawSpace = false
        while index < attributed.endIndex {
            let isSpace = attributed.characters[index].isWhitespace
            if sawSpace && !isSpace { result.append(AttributedString(attributed[start..<index])); start = index; sawSpace = false }
            if isSpace { sawSpace = true }
            index = attributed.characters.index(after: index)
        }
        if start < attributed.endIndex { result.append(AttributedString(attributed[start..<attributed.endIndex])) }
        return result
    }
}

/// Lays children left to right, wrapping at the proposed width: answer words with inline
/// citation chips between them.
struct ChatFlow: Layout {
    var lineSpacing: CGFloat
    private func rows(_ width: CGFloat, _ subviews: Subviews) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]], x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((index, size)); x += size.width
        }
        return rows
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(width, subviews)
        let height = rows.reduce(0) { $0 + ($1.map(\.size.height).max() ?? 0) } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let used = rows.map { $0.reduce(0) { $0 + $1.size.width } }.max() ?? 0
        return CGSize(width: width.isFinite ? width : used, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews) {
            let height = row.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for item in row {
                subviews[item.index].place(at: CGPoint(x: x, y: y + height / 2), anchor: .leading, proposal: ProposedViewSize(item.size))
                x += item.size.width
            }
            y += height + lineSpacing
        }
    }
}

/// An answer in `row` `ink` at 1.45, with `[n]` markers drawn as the answer's numbered chips
/// and quoted page text in the serif `quote` face beside a `quoteRule`.
struct ChatMarkdownView<Chip: View>: View {
    @EnvironmentObject var app: AppState
    let text: String
    let sources: [KnowledgeSource]
    var citations: [ChatCitation] = []
    let chip: (ChatCitation) -> Chip
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ChatMarkdown.blocks(text)) { block in
                if block.code {
                    ScrollView(.horizontal) { Text(block.text).font(ShellType.code).textSelection(.enabled).padding(10) }
                        .background(app.pal.elevFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                } else if let quote = ChatMarkdown.quote(block.text, sources: sources) {
                    HStack(alignment: .top, spacing: ShellLayout.rowInsetLeading) {
                        Rectangle().fill(app.pal.quoteRule).frame(width: ShellLayout.hairline)
                        Text(quote).font(ShellType.quote).lineSpacing(ShellType.rowLineSpacing).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }.fixedSize(horizontal: false, vertical: true)
                } else {
                    let heading = block.text.hasPrefix("#")
                    let value = heading ? block.text.drop(while: { $0 == "#" || $0 == " " }).description : block.text
                    let font = heading ? ShellType.title : ShellType.row
                    if ChatMarkdown.hasMarkers(value) {
                        VStack(alignment: .leading, spacing: ShellType.rowLineSpacing) {
                            ForEach(Array(value.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in flow(line, font: font) }
                        }
                    } else {
                        Text(ChatMarkdown.attributed(value)).font(font).lineSpacing(ShellType.rowLineSpacing).textSelection(.enabled)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                if ["http", "https"].contains(url.scheme ?? "") { app.openTab(url: url, parent: nil, activate: true); return .handled }
                return .discarded
            })
    }
    private func flow(_ line: String, font: Font) -> some View {
        ChatFlow(lineSpacing: ShellType.rowLineSpacing) {
            ForEach(Array(ChatMarkdown.segments(line).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let run):
                    ForEach(Array(ChatMarkdown.words(run).enumerated()), id: \.offset) { _, word in Text(word).font(font) }
                case .marker(let number):
                    if let citation = citations.first(where: { $0.sourceNumber == number }) { chip(citation) }
                    else { Text("[unverified source] ").font(ShellType.caption).foregroundStyle(app.pal.ink3) }
                }
            }
        }
    }
}

/// A citation index: `label` numerals, tabular, on a 16pt `elevFill` chip with a 4pt radius,
/// set 2pt off the text around it. `active` raises it to `accentSoft`; an unlinked chip reads `ink3`.
struct CitationIndexLabel: View {
    @EnvironmentObject var app: AppState
    let index: Int
    var active = false
    var linked = true
    var body: some View {
        Text("\(index)").font(ShellType.label.monospacedDigit())
            .foregroundStyle(active ? app.pal.accent : (linked ? app.pal.ink : app.pal.ink3))
            .padding(.horizontal, ShellLayout.iconBackingInset)
            .frame(minWidth: ShellLayout.iconSize, minHeight: ShellLayout.iconSize, maxHeight: ShellLayout.iconSize)
            .background(active ? app.pal.accentSoft : app.pal.elevFill, in: RoundedRectangle(cornerRadius: ShellLayout.chipRadius))
            .padding(.horizontal, ShellLayout.iconBackingInset)
    }
}

/// The plain chip for surfaces without a page link (thread summaries): the model's source
/// number, opening the source on click.
struct SourceNumberLink: View {
    @EnvironmentObject var app: AppState
    let citation: ChatCitation
    let sources: [KnowledgeSource]
    var body: some View {
        let source = sources.indices.contains(citation.sourceNumber - 1) ? sources[citation.sourceNumber - 1] : nil
        Button {
            if let source, let url = URL(string: source.url), ["http", "https"].contains(url.scheme ?? "") { app.openTab(url: url, parent: nil, activate: true) }
        } label: { CitationIndexLabel(index: citation.index) }
            .buttonStyle(.plain).help(source?.title ?? "")
            .accessibilityLabel("Source \(citation.index)\(source.map { ": " + $0.title } ?? "")").accessibilityAddTraits(.isButton)
    }
}

extension ChatMarkdownView where Chip == SourceNumberLink {
    /// Keeps the model's own source numbers, for text outside the Ask panel.
    init(text: String, sources: [KnowledgeSource]) {
        let citations = ChatCitation.assign(answer: text, sources: sources, messageID: UUID(), passages: false).map { citation in
            var numbered = citation; numbered.index = citation.sourceNumber; return numbered
        }
        self.init(text: text, sources: sources, citations: citations) { SourceNumberLink(citation: $0, sources: sources) }
    }
}
