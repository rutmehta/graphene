import Foundation

/// Encodes and writes the session, archive and settings files off the main thread, in order.
///
/// `AppState.persist()` hands over an immutable snapshot (value types only). Encoding the tab
/// list and up to 2,000 archived tabs used to run on the main thread after every change
/// (docs/parity/perf-audit.md, second pass §1). Each file keeps only its newest snapshot:
/// when saves pile up behind a slow disk, the older ones are skipped, not written twice.
/// Every write is atomic, as before.
final class SessionWriter: @unchecked Sendable {
    static let shared = SessionWriter()

    private let queue = DispatchQueue(label: "graphene.session.save", qos: .utility)
    private let lock = NSLock()
    private var tickets: [String: Int] = [:]
    private var nextTicket = 0
    private var writeCount = 0
    private var fileWrites: [String: Int] = [:]
    /// Files encoded and written, for tests.
    var writes: Int { lock.lock(); defer { lock.unlock() }; return writeCount }
    /// Times `file` was encoded and written, for tests.
    func writes(to file: URL) -> Int { lock.lock(); defer { lock.unlock() }; return fileWrites[file.path] ?? 0 }

    /// Queues `encode()` to be written to `file`. `done` runs on the main queue with the
    /// error text (nil on success); it is not called for a snapshot a newer one replaced.
    func write(_ file: URL, encode: @escaping @Sendable () throws -> Data, done: (@Sendable (String?) -> Void)? = nil) {
        lock.lock(); nextTicket += 1; let ticket = nextTicket; tickets[file.path] = ticket; lock.unlock()
        queue.async { [self] in
            lock.lock(); let current = tickets[file.path] == ticket; lock.unlock()
            guard current else { return }
            var failure: String?
            do { try encode().write(to: file, options: .atomic); lock.lock(); writeCount += 1; fileWrites[file.path, default: 0] += 1; lock.unlock() }
            catch { failure = error.localizedDescription }
            if let done { DispatchQueue.main.async { done(failure) } }
        }
    }

    /// Returns once every write queued so far is on disk: at quit, and before a window reads
    /// the files back.
    func flush() { queue.sync {} }
}
