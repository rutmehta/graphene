import Foundation
import SwiftUI

/// One inbox message, view-ready.
struct MailItem: Identifiable {
    let id: String
    var from: String
    var address: String
    var subject: String
    var preview: String
    var date: Date
    var unread: Bool
    var initial: String
    var colorHex: String
    var body: [String]
    /// Gmail's thread id; conversations group by it, else by normalised subject.
    var threadID: String? = nil

    /// Unread rows carry the 6pt `accent` dot in the icon slot (there are no avatars).
    var showsUnreadDot: Bool { unread }

    var timeLabel: String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) { f.dateFormat = "h:mm a" }
        else if cal.isDateInYesterday(date) { f.dateFormat = "'Yesterday'" }
        else { f.dateFormat = "MMM d" }
        return f.string(from: date)
    }
}

/// Mail row metrics (graphene-language.md §5.7): two-line 44pt rows at a 44pt pitch, so the
/// conversation connector reuses `ProvenanceConnector` with these metrics.
enum MailLayout {
    static let rowHeight: CGFloat = 44
    /// Replies shown under a collapsed conversation's first message.
    static let collapsedReplies = 3
}

/// One conversation: the first message and its replies, oldest first.
struct MailConversation: Identifiable {
    /// The Gmail thread id, else `subject:` plus the normalised subject.
    let id: String
    let messages: [MailItem]

    var first: MailItem { messages[0] }
    var replies: ArraySlice<MailItem> { messages.dropFirst() }
    var latest: Date { messages.map(\.date).max() ?? first.date }

    /// Replies hidden behind the "N more" label: all but the latest three unless expanded.
    func hiddenCount(expanded: Bool) -> Int { expanded ? 0 : max(0, replies.count - MailLayout.collapsedReplies) }
    /// The replies shown under the first message.
    func visibleReplies(expanded: Bool) -> [MailItem] { Array(replies.suffix(replies.count - hiddenCount(expanded: expanded))) }

    /// The rows drawn for this conversation, top to bottom.
    func rows(expanded: Bool) -> [MailConversationRow] {
        var rows: [MailConversationRow] = [.message(first, reply: false)]
        let hidden = hiddenCount(expanded: expanded)
        if hidden > 0 { rows.append(.more(hidden)) }
        else if expanded && replies.count > MailLayout.collapsedReplies { rows.append(.fewer) }
        rows += visibleReplies(expanded: expanded).map { .message($0, reply: true) }
        return rows
    }

    /// The thread connector from the first message to each visible reply, in the rows' space.
    func connector(expanded: Bool) -> ProvenanceConnector? {
        let rows = rows(expanded: expanded)
        let children = rows.indices.filter { if case .message(_, true) = rows[$0] { return true } else { return false } }
        guard let last = children.last else { return nil }
        return ProvenanceConnector(parentID: UUID(), parentRow: 0, parentIndent: 0, childRows: children, lastChildRow: last,
                                   active: false, rowPitch: MailLayout.rowHeight, rowHeight: MailLayout.rowHeight)
    }

    /// Conversations from inbox messages, newest activity first.
    static func group(_ items: [MailItem]) -> [MailConversation] {
        var order: [String] = [], buckets: [String: [MailItem]] = [:]
        for item in items {
            let key = item.threadID.map { "thread:\($0)" } ?? "subject:\(normalizedSubject(item.subject))"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.map { key in MailConversation(id: key, messages: buckets[key]!.sorted { $0.date < $1.date }) }
            .enumerated().sorted { $0.element.latest != $1.element.latest ? $0.element.latest > $1.element.latest : $0.offset < $1.offset }
            .map(\.element)
    }

    /// The subject without reply and forward prefixes, case- and space-folded.
    static func normalizedSubject(_ subject: String) -> String {
        var value = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        while let range = value.range(of: #"^(re|fwd?|aw|wg)(\[\d+\])?\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            value.removeSubrange(range)
        }
        return value.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// A row in a conversation: a message (the first, or an indented reply) or the collapse label.
enum MailConversationRow: Identifiable {
    case message(MailItem, reply: Bool)
    case more(Int)
    case fewer
    var id: String {
        switch self {
        case .message(let item, _): return item.id
        case .more: return "more"
        case .fewer: return "fewer"
        }
    }
}

/// A message's rendered body (full HTML preferred, plain-text fallback).
struct EmailBody {
    var html: String?
    var text: String
}

/// Owns the Gmail connection + the fetched inbox. Read-only for now.
@MainActor
final class MailStore: ObservableObject {
    @Published var items: [MailItem] = []
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var errorText: String?
    @Published var selectedID: String?
    @Published var bodyCache: [String: EmailBody] = [:]
    @Published var loadingBody = false
    @Published private(set) var accountAddress: String?
    /// Conversations the user expanded past their latest three replies.
    @Published var expandedConversations: Set<String> = []

    var conversations: [MailConversation] { MailConversation.group(items) }
    func toggleExpanded(_ id: String) {
        if expandedConversations.contains(id) { expandedConversations.remove(id) } else { expandedConversations.insert(id) }
    }

    var isConfigured: Bool { GmailConfig.isConfigured }
    var selected: MailItem? { items.first { $0.id == selectedID } ?? items.first }

    private let auth = GmailAuth()
    private var tokens: TokenSet?

    private var didBootstrap = false

    /// Keychain access may wait on macOS. Never block the browser's main thread.
    /// Only attempt a noninteractive lookup when the user opens Mail.
    func bootstrap() {
        guard !didBootstrap, ProcessInfo.processInfo.environment["GRAPHENE_DATA_DIR"] == nil else { return }
        didBootstrap = true
        Task {
            let saved = await Task.detached(priority: .utility) { Keychain.loadTokens() }.value
            guard tokens == nil, !isBusy, let saved else { return }
            tokens = saved; isConnected = true
            await load()
        }
    }

    func connect() {
        guard !isBusy else { return }
        errorText = nil
        isBusy = true
        Task {
            do {
                let t = try await auth.authorize()
                Keychain.saveTokens(t)
                tokens = t
                isConnected = true
                await load()
            } catch {
                errorText = error.localizedDescription
            }
            isBusy = false
        }
    }

    func disconnect() {
        Keychain.clear()
        tokens = nil
        items = []
        isConnected = false
        selectedID = nil
        bodyCache = [:]; accountAddress = nil; expandedConversations = []
    }

    func reload() { Task { await load() } }

    /// Select a message and lazily fetch its full body.
    func select(_ id: String) {
        selectedID = id
        if bodyCache[id] == nil { Task { await loadBody(id) } }
    }

    private func loadBody(_ id: String) async {
        loadingBody = true
        defer { loadingBody = false }
        do {
            let token = try await validAccessToken()
            let body: EmailBody
            do {
                body = try await GmailClient.fetchBody(id: id, accessToken: token)
            } catch GmailError.unauthorized {
                let fresh = try await refreshTokens()
                body = try await GmailClient.fetchBody(id: id, accessToken: fresh)
            }
            bodyCache[id] = body
        } catch {
            bodyCache[id] = EmailBody(html: nil, text: items.first(where: { $0.id == id })?.preview ?? "Couldn’t load this message.")
            errorText = error.localizedDescription
        }
    }

    private func load() async {
        guard isConnected else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let token = try await validAccessToken()
            do {
                accountAddress = try await GmailClient.accountAddress(accessToken: token)
                items = try await GmailClient.listInbox(accessToken: token)
            } catch GmailError.unauthorized {
                // token rejected — force refresh once and retry
                let fresh = try await refreshTokens()
                accountAddress = try await GmailClient.accountAddress(accessToken: fresh)
                items = try await GmailClient.listInbox(accessToken: fresh)
            }
            errorText = nil
            if let first = (selectedID.flatMap { id in items.first { $0.id == id } } ?? items.first) {
                select(first.id)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func validAccessToken() async throws -> String {
        guard let t = tokens else { throw GmailAuthError.cancelled }
        tokens = t
        if t.isExpired { return try await refreshTokens() }
        return t.accessToken
    }

    private func refreshTokens() async throws -> String {
        guard let t = tokens else { throw GmailAuthError.cancelled }
        let fresh = try await auth.refresh(t)
        Keychain.saveTokens(fresh)
        tokens = fresh
        return fresh.accessToken
    }
}
