import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case system, user, assistant }
    var id = UUID()
    var role: Role
    var content: String
    var sources: [KnowledgeSource]?
}

enum ProviderKind: String, Codable, CaseIterable {
    case onDevice, compatible, anthropic
    var title: String {
        switch self { case .onDevice: return "Apple · on device"; case .compatible: return "OpenAI-compatible"; case .anthropic: return "Anthropic" }
    }
}
struct AISettings: Codable, Equatable {
    var provider: ProviderKind = .onDevice
    var baseURL = "https://api.openai.com/v1"
    var model = "gpt-4.1-mini"
    var anthropicModel = "claude-sonnet-5"
    var remoteConsent = false
    var personalContext = false
    var tidyTitles: Bool?
    var tidyDownloads: Bool?
    var tidiedURLs: Set<String>?
}

/// No tool execution is exposed to the model.
protocol LanguageModelProvider {
    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>
}
struct ProviderFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct RemoteProvider: LanguageModelProvider {
    let kind: ProviderKind
    let baseURL: String
    let model: String
    let key: String

    static func request(kind: ProviderKind, baseURL: String, model: String, key: String, messages: [ChatMessage]) throws -> URLRequest {
        guard let base = URL(string: baseURL), let host = base.host,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)),
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderFailure(message: "Use an HTTPS API base URL, or HTTP on localhost, and a model name.")
        }
        var request = URLRequest(url: base.appendingPathComponent(kind == .anthropic ? "messages" : "chat/completions"))
        request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let encoded = messages.filter { kind != .anthropic || $0.role != .system }.map { ["role": $0.role.rawValue, "content": $0.content] }
        var body: [String: Any] = ["model": model, "stream": true, "messages": encoded]
        if kind == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body["system"] = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
            body["max_tokens"] = 2048
        } else if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func delta(_ data: String, kind: ProviderKind) throws -> String? {
        guard data != "[DONE]", let bytes = data.data(using: .utf8), let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return nil }
        if json["error"] != nil { throw ProviderFailure(message: "The provider returned a streaming error. Check model access and quota.") }
        if kind == .anthropic { return (json["delta"] as? [String: Any])?["text"] as? String }
        return (((json["choices"] as? [[String: Any]])?.first)?["delta"] as? [String: Any])?["content"] as? String
    }
    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Ephemeral sessions do not borrow browser cookies, credentials or cache.
                let session = URLSession(configuration: .ephemeral, delegate: NoAIRedirect(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                do {
                    let request = try Self.request(kind: kind, baseURL: baseURL, model: model, key: key, messages: messages)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                        throw ProviderFailure(message: "Provider request failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Check endpoint, key and model in Settings → AI.")
                    }
                    var data: [String] = []
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line.hasPrefix("data:") {
                            let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            // Providers normally emit one JSON document per data line.
                            if value == "[DONE]" { break }
                            data.append(value)
                            if let joined = data.joined(separator: "\n").data(using: .utf8), (try? JSONSerialization.jsonObject(with: joined)) != nil {
                                if let text = try Self.delta(data.joined(separator: "\n"), kind: kind) { continuation.yield(text) }
                                data = []
                            }
                            if data.joined().count > 1_000_000 { throw ProviderFailure(message: "Provider event exceeded the size limit.") }
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
private final class NoAIRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct OnDeviceProvider: LanguageModelProvider {
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled): return "Enable Apple Intelligence in System Settings. Source search works without a model."
            case .unavailable(.modelNotReady): return "Apple’s on-device model is still getting ready. Source search remains available."
            case .unavailable: return "On-device answers aren’t available on this Mac. Source search remains available."
            }
        }
        #endif
        return "On-device answers require macOS 26 and Apple Intelligence. Source search remains available."
    }
    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    #if canImport(FoundationModels)
                    if #available(macOS 26, *) {
                        let system = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n")
                        let turns = messages.filter { $0.role != .system }
                        // One self-contained turn (Chat's request) goes as is; role labels would read as a transcript to continue.
                        let prompt = turns.count == 1 ? turns[0].content : turns.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n\n")
                        for attempt in 0...1 {
                            let session = LanguageModelSession(instructions: system)
                            let context = attempt == 0 ? prompt : PageContext.shortened(messages.last { $0.role == .user }?.content ?? prompt, limit: 2400)
                            var gate = RefusalGate()
                            do {
                                for try await snapshot in session.streamResponse(to: context, options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 700)) {
                                    try Task.checkCancellation()
                                    if let text = gate.receive(snapshot.content) { continuation.yield(text) }
                                }
                                switch gate.finish() {
                                case .text(let text):
                                    if !text.isEmpty { continuation.yield(text) }
                                    continuation.finish(); return
                                case .refused:
                                    // A canned "I cannot fulfill that request" is not an answer; retry once, then say so plainly.
                                    guard attempt == 0 else { throw ProviderFailure(message: RefusalGate.declinedMessage) }
                                }
                            } catch LanguageModelSession.GenerationError.guardrailViolation {
                                try Task.checkCancellation()
                                guard attempt == 0 else { throw ProviderFailure(message: RefusalGate.declinedMessage) }
                                // Keep partial output visibly separate from the retry; never silently splice two answers.
                                if gate.released { continuation.yield("\n\nApple's on-device model declined this request. Retrying with a shorter excerpt…\n\n") }
                            }
                        }
                    }
                    #endif
                    throw ProviderFailure(message: Self.unavailableReason ?? "Model unavailable")
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Holds back the opening of an on-device answer until it is clear the model is answering,
/// so a short canned refusal ("I cannot fulfill that request.") is never shown as the answer.
/// Snapshots are cumulative, as `LanguageModelSession.streamResponse` delivers them.
struct RefusalGate {
    enum Outcome: Equatable { case text(String), refused }
    /// Refusals are one short sentence; anything longer is released as it streams.
    static let holdLimit = 160
    static let declinedMessage = "Apple's on-device model declined this request. Try asking about a specific passage, or choose another provider in Settings → AI."
    /// The model declining the task itself, in the first person. "I cannot find that in the
    /// sources" is a legitimate grounded answer, and "the site cannot comply with GDPR" is about
    /// the page, so neither matches.
    static let subjects = ["i cannot ", "i can't ", "i can not ", "i'm unable to ", "i am unable to ", "i'm not able to ", "i am not able to "]
    static let tasks = ["fulfill", "assist with", "help with that", "help with this", "comply", "summarize", "provide a summary", "complete that request", "complete this request"]

    static func isRefusal(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        guard !normalized.isEmpty, normalized.count <= holdLimit else { return false }
        return subjects.contains { subject in tasks.contains { normalized.contains(subject + $0) } }
    }

    private var latest = ""
    private var sent = 0
    /// Whether any text has been handed on; once it has, the rest streams straight through.
    private(set) var released = false

    /// Takes the cumulative snapshot and returns the new text to show, if any.
    mutating func receive(_ snapshot: String) -> String? {
        latest = snapshot
        guard released || snapshot.count > Self.holdLimit else { return nil }
        released = true
        return drain()
    }
    /// The stream ended: either the rest of the answer, or a refusal to retry.
    mutating func finish() -> Outcome {
        if !released, Self.isRefusal(latest) { return .refused }
        released = true
        return .text(drain() ?? "")
    }
    private mutating func drain() -> String? {
        guard latest.count > sent else { return nil }
        let text = String(latest.dropFirst(sent))
        sent = latest.count
        return text
    }
}

@MainActor
struct ProviderRegistry {
    let settings: AISettings
    let namespace: String
    var status: String { settings.provider.title }
    var unavailableReason: String? {
        if settings.provider == .onDevice { return OnDeviceProvider.unavailableReason }
        guard settings.remoteConsent else { return "Choose and approve this provider in Settings → AI before sending content." }
        if settings.provider == .anthropic, Keychain.aiKey(account: keyAccount) == nil { return "Add your Anthropic API key in Settings → AI." }
        return nil
    }
    var keyAccount: String { "\(namespace):\(settings.provider.rawValue):\(settings.provider == .anthropic ? "https://api.anthropic.com/v1" : settings.baseURL)" }
    func provider() throws -> any LanguageModelProvider {
        if let reason = unavailableReason { throw ProviderFailure(message: reason) }
        if settings.provider == .onDevice { return OnDeviceProvider() }
        return RemoteProvider(kind: settings.provider, baseURL: settings.provider == .anthropic ? "https://api.anthropic.com/v1" : settings.baseURL, model: settings.provider == .anthropic ? settings.anthropicModel : settings.model, key: Keychain.aiKey(account: keyAccount) ?? "")
    }
}
