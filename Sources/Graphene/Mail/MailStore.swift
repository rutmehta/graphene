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

    var timeLabel: String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) { f.dateFormat = "h:mm a" }
        else if cal.isDateInYesterday(date) { f.dateFormat = "'Yesterday'" }
        else { f.dateFormat = "MMM d" }
        return f.string(from: date)
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
        bodyCache = [:]; accountAddress = nil
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
