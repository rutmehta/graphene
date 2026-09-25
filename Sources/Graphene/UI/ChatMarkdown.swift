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

    /// A run of answer text, a `[n]` citation marker (the model's source number), or the chip of
    /// one of the answer's citations (its 1-based position among them, not its shown number:
    /// several citations of one source share a number but each leads to its own passage).
    enum Segment: Equatable {
        case text(String)
        case marker(Int)
        case anchored(Int)
    }
    /// Private brackets around an anchored chip's position; a model does not write them.
    static let anchorOpen = "⁅", anchorClose = "⁆"
    /// A `[n]` marker (with any `(url)` the model appended) or an anchored chip.
    static let chipPattern = #"\[\d+\](?:\([^)]*\))?|⁅\d+⁆"#
    /// Splits a line at its `[n]` markers (and any `(url)` the model appended to one) and anchored chips.
    static func segments(_ line: String) -> [Segment] {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+)\](?:\([^)]*\))?|⁅(\d+)⁆"#) else { return [.text(line)] }
        var result: [Segment] = [], cursor = line.startIndex
        for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            guard let range = Range(match.range, in: line) else { continue }
            let segment: Segment
            if let number = Range(match.range(at: 1), in: line).flatMap({ Int(line[$0]) }) { segment = .marker(number) }
            else if let index = Range(match.range(at: 2), in: line).flatMap({ Int(line[$0]) }) { segment = .anchored(index) }
            else { continue }
            if cursor < range.lowerBound { result.append(.text(String(line[cursor..<range.lowerBound]))) }
            result.append(segment); cursor = range.upperBound
        }
        if cursor < line.endIndex { result.append(.text(String(line[cursor...]))) }
        return result
    }
    static func hasMarkers(_ text: String) -> Bool {
        text.range(of: #"\[\d+\]"#, options: .regularExpression) != nil || text.contains(anchorOpen)
    }
    /// `text` with each citation's chip in place: the `[n]` markers of per-claim citations
    /// become their chips by position among the answer's markers (older citations keep their
    /// `[n]`, resolved by source number), and each fallback citation's chip follows the
    /// sentences it was matched to. A chip names its citation by position (`Segment.anchored`).
    static func anchored(_ text: String, citations: [ChatCitation]) -> String {
        var result = text
        var byMarker: [Int: Int] = [:]
        for (offset, citation) in citations.enumerated() { for marker in citation.markers ?? [] { byMarker[marker] = offset + 1 } }
        if !byMarker.isEmpty, let regex = try? NSRegularExpression(pattern: #"\[(\d+)\](?:\([^)]*\))?"#) {
            for (ordinal, match) in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).enumerated().reversed() {
                guard let position = byMarker[ordinal], let range = Range(match.range, in: result) else { continue }
                result.replaceSubrange(range, with: anchorOpen + "\(position)" + anchorClose)
            }
        }
        for (offset, citation) in citations.enumerated() {
            for anchor in citation.anchors ?? [] {
                guard !anchor.isEmpty, let range = result.range(of: anchor) else { continue }
                result.insert(contentsOf: " " + anchorOpen + "\(offset + 1)" + anchorClose, at: range.upperBound)
            }
        }
        return result
    }
    /// A line holding only chips ("[5]" after a blank line, "⁅2⁆" alone) joins the last line of
    /// text before it, so a trailing chip never sits alone on its own line.
    static func attachingOrphanChips(_ text: String) -> String {
        var lines: [String] = []
        var code = false
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") { code.toggle(); lines.append(line); continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let chipsOnly = !code && !trimmed.isEmpty
                && trimmed.replacingOccurrences(of: chipPattern, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces).isEmpty
            if chipsOnly, let last = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }), !lines[last].hasPrefix("```") {
                lines.removeSubrange((last + 1)...)
                lines[last] = lines[last].replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) + " " + trimmed
                continue
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
    /// One item of a flowed line: a word, or a chip.
    enum FlowToken: Equatable {
        case word(AttributedString)
        case chip(Segment)
    }
    /// A line's words and chips in wrap units: each chip, and any bare space after it, stays
    /// with the word before it, so a trailing chip wraps with its sentence's last word.
    static func flowGroups(_ line: String) -> [[FlowToken]] {
        var groups: [[FlowToken]] = []
        for segment in segments(line) {
            if case .text(let run) = segment {
                for word in words(run) {
                    let blank = String(word.characters).allSatisfy(\.isWhitespace)
                    if blank, !groups.isEmpty { groups[groups.count - 1].append(.word(word)) } else { groups.append([.word(word)]) }
                }
            } else if groups.isEmpty { groups.append([.chip(segment)]) }
            else { groups[groups.count - 1].append(.chip(segment)) }
        }
        return groups
    }

    // MARK: quoted excerpts

    /// Fewest words a sentence must have to be set as a verbatim excerpt of a passage.
    static let echoWords = 8
    /// Largest share of an answer's words that may be set as quotes: never the whole answer.
    static let quoteShare = 0.4
    /// A run of a line: prose, or sentences set as quoted excerpts.
    struct Piece: Equatable {
        var text: String
        var quote: Bool
    }
    /// The words of `text` compared for an excerpt: markers and chips dropped, case folded,
    /// punctuation ignored.
    static func comparable(_ text: String) -> [String] {
        text.replacingOccurrences(of: #"\[\d+\]|⁅\d+⁆"#, with: " ", options: .regularExpression)
            .lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    /// A sentence's identity across the quote plan and the rendering.
    static func sentenceKey(_ sentence: String) -> String { comparable(sentence).joined(separator: " ") }
    /// The sentences of `line`, exactly covering it; chips a sentence break left at the start of
    /// a sentence ("… 130 GPa. [1]") stay with the one before it.
    static func sentences(_ line: String) -> [String] {
        var result: [String] = []
        for range in PageContext.sentenceRanges(line) {
            var sentence = String(line[range])
            if let last = result.indices.last, let lead = sentence.range(of: #"^\s*((\[\d+\]|⁅\d+⁆)\s*)+"#, options: .regularExpression) {
                result[last] += sentence[lead]
                sentence = String(sentence[lead.upperBound...])
                if sentence.isEmpty { continue }
            }
            result.append(sentence)
        }
        return result
    }
    /// Whether `sentence` is an explicit excerpt: wholly in quotation marks with its words
    /// verbatim in a cited passage or a source, or a whole sentence of at least `echoWords`
    /// words that appears word for word in a cited passage. A paraphrase, or a sentence that
    /// only shares a run of words with a passage, is prose.
    static func excerpt(_ sentence: String, passages: [String], sources: [KnowledgeSource] = []) -> Bool {
        var bare = sentence.replacingOccurrences(of: chipPattern, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = bare.last, ".,;:".contains(last), let before = bare.dropLast().last, "\"”".contains(before) { bare.removeLast() }
        if let first = bare.first, let last = bare.last, bare.count > 2, "\"“".contains(first), "\"”".contains(last) {
            let wanted = normalized(String(bare.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces))
            return !wanted.isEmpty && (passages + sources.map(\.text)).contains { normalized($0).contains(wanted) }
        }
        let words = comparable(bare)
        guard words.count >= echoWords else { return false }
        let run = " " + words.joined(separator: " ") + " "
        return passages.contains { (" " + comparable($0).joined(separator: " ") + " ").contains(run) }
    }
    /// Which blocks and sentences of an answer are set as quotes.
    struct QuotePlan: Equatable {
        /// Ids of whole blocks (`>` quotes, blocks wholly in quotation marks) set as quotes.
        var blocks: Set<Int> = []
        /// `sentenceKey`s of sentences set as quotes.
        var sentences: Set<String> = []
    }
    /// The quotes of `text` (as shown, chips anchored): explicit excerpts, in reading order,
    /// while together they stay within `quoteShare` of the answer's words, so an answer always
    /// keeps prose around its quotes and is never one quote block.
    static func quotePlan(_ text: String, passages: [String], sources: [KnowledgeSource]) -> QuotePlan {
        var total = 0
        var candidates: [(block: Int?, key: String, words: Int)] = []
        for block in blocks(text) where !block.code {
            if block.text.hasPrefix("#") { total += comparable(block.text).count; continue }
            if quote(block.text, sources: sources) != nil {
                let count = comparable(block.text).count
                total += count; candidates.append((block.id, "", count)); continue
            }
            for line in block.text.components(separatedBy: "\n") {
                for sentence in sentences(line) {
                    let count = comparable(sentence).count
                    total += count
                    if count > 0, excerpt(sentence, passages: passages, sources: sources) { candidates.append((nil, sentenceKey(sentence), count)) }
                }
            }
        }
        var plan = QuotePlan(), used = 0
        for candidate in candidates where Double(used + candidate.words) <= quoteShare * Double(total) {
            used += candidate.words
            if let block = candidate.block { plan.blocks.insert(block) } else { plan.sentences.insert(candidate.key) }
        }
        return plan
    }
    /// `line` split into prose and the sentences `quoted` names (`sentenceKey`s), neighbours of
    /// a kind joined; a sentence of chips alone stays with the one before it.
    static func pieces(_ line: String, quoted: Set<String>) -> [Piece] {
        var result: [Piece] = []
        for sentence in sentences(line) {
            let key = sentenceKey(sentence)
            let quote = !key.isEmpty && quoted.contains(key)
            if let last = result.indices.last, key.isEmpty || result[last].quote == quote { result[last].text += sentence }
            else { result.append(Piece(text: sentence, quote: quote)) }
        }
        return result
    }
    /// A `>` block's text without its markers, for a block shown as prose.
    static func unquoted(_ block: String) -> String {
        let lines = block.components(separatedBy: "\n")
        guard lines.allSatisfy({ $0.hasPrefix(">") }) else { return block }
        return lines.map { String($0.dropFirst()).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }

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
/// and explicit excerpts of the page (`ChatMarkdown.quotePlan`) in the serif `quote` face
/// beside a `quoteRule`.
struct ChatMarkdownView<Chip: View>: View {
    @EnvironmentObject var app: AppState
    let text: String
    let sources: [KnowledgeSource]
    var citations: [ChatCitation] = []
    let chip: (ChatCitation) -> Chip
    /// The answer as shown: chips anchored, none left alone on a line.
    private var shown: String { ChatMarkdown.attachingOrphanChips(ChatMarkdown.anchored(text, citations: citations)) }
    var body: some View {
        let answer = shown
        let plan = ChatMarkdown.quotePlan(answer, passages: passages, sources: sources)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ChatMarkdown.blocks(answer)) { block in
                if block.code {
                    ScrollView(.horizontal) { Text(block.text).font(ShellType.code).textSelection(.enabled).padding(10) }
                        .background(app.pal.elevFill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                } else if plan.blocks.contains(block.id), let quote = ChatMarkdown.quote(block.text, sources: sources) {
                    quoteRow {
                        Text(quote).font(ShellType.quote).lineSpacing(ShellType.rowLineSpacing).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    let heading = block.text.hasPrefix("#")
                    let value = heading ? block.text.drop(while: { $0 == "#" || $0 == " " }).description : ChatMarkdown.unquoted(block.text)
                    let font = heading ? ShellType.title : ShellType.row
                    let pieces = heading ? [] : value.components(separatedBy: "\n").flatMap { ChatMarkdown.pieces($0, quoted: plan.sentences) }
                    if pieces.contains(where: \.quote) {
                        VStack(alignment: .leading, spacing: ShellType.rowLineSpacing) {
                            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                                let run = piece.text.trimmingCharacters(in: .whitespaces)
                                if piece.quote { quoteRow { flow(run, font: ShellType.quote) } }
                                else if ChatMarkdown.hasMarkers(run) { flow(run, font: font) }
                                else { Text(ChatMarkdown.attributed(run)).font(font).lineSpacing(ShellType.rowLineSpacing).textSelection(.enabled) }
                            }
                        }
                    } else if ChatMarkdown.hasMarkers(value) {
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
    /// The passages this answer cites: a sentence quoting one verbatim may be set as a quote.
    private var passages: [String] { citations.compactMap(\.passage) }
    /// Page text in the answer: `content` beside the `quoteRule`.
    private func quoteRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: ShellLayout.rowInsetLeading) {
            Rectangle().fill(app.pal.quoteRule).frame(width: ShellLayout.hairline)
            content()
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func flow(_ line: String, font: Font) -> some View {
        ChatFlow(lineSpacing: ShellType.rowLineSpacing) {
            // Each wrap unit is one subview: a chip wraps with the word before it.
            ForEach(Array(ChatMarkdown.flowGroups(line).enumerated()), id: \.offset) { _, group in
                HStack(spacing: 0) {
                    ForEach(Array(group.enumerated()), id: \.offset) { _, token in
                        switch token {
                        case .word(let word): Text(word).font(font)
                        case .chip(let segment): chipView(segment)
                        }
                    }
                }.fixedSize()
            }
        }
    }
    @ViewBuilder private func chipView(_ segment: ChatMarkdown.Segment) -> some View {
        switch segment {
        case .marker(let number):
            if let citation = citations.first(where: { $0.sourceNumber == number }) { chip(citation) }
            else { Text("[unverified source] ").font(ShellType.caption).foregroundStyle(app.pal.ink3) }
        case .anchored(let position):
            if citations.indices.contains(position - 1) { chip(citations[position - 1]) }
        case .text(let run):
            Text(run).font(ShellType.row)
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
