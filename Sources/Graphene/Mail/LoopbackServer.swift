import Foundation
import Darwin

/// Appends OAuth diagnostics to ~/Library/Application Support/Graphene/oauth.log
enum OAuthLog {
    static var file: URL { Paths.root.appendingPathComponent("oauth.log") }
    static func log(_ s: String) {
        let line = "[\(Date())] \(s)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: file)
        }
    }
}

/// A one-shot HTTP listener bound explicitly to 127.0.0.1 (IPv4 loopback) via a
/// raw POSIX socket — the reliable way to catch Google's "Desktop app" OAuth
/// redirect. No app bundling / URL scheme needed.
// All mutable state is protected by lock. The reader owns a duplicated listener
// and closes its client; completion only shuts that client down to unblock I/O.
final class LoopbackServer: @unchecked Sendable {
    private var boundPort: UInt16 = 0
    var port: UInt16 { lock.withLock { boundPort } }
    private var fd: Int32 = -1
    private var clientFD: Int32 = -1
    private var started = false
    private var waiting = false
    private var stopped = false
    private var continuation: CheckedContinuation<String?, Never>?
    private let lock = NSLock()

    /// Bind to an ephemeral 127.0.0.1 port and start listening; returns the port.
    func start() throws -> UInt16 {
        lock.lock(); defer { lock.unlock() }
        guard !started, !stopped else {
            throw NSError(domain: "graphene.loopback", code: Int(EALREADY),
                          userInfo: [NSLocalizedDescriptionKey: "This sign-in listener has already been used."])
        }
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { throw posixError("socket") }
        var yes: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0                       // ephemeral
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0 else { close(s); throw posixError("bind") }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(s, $0, &len) }
        }
        boundPort = UInt16(bigEndian: addr.sin_port)

        guard listen(s, 1) == 0 else { close(s); throw posixError("listen") }
        fd = s
        started = true
        OAuthLog.log("loopback listening on 127.0.0.1:\(boundPort)")
        return boundPort
    }

    /// Await the authorization code delivered to the loopback redirect (with a
    /// hard timeout so the sign-in can never hang forever).
    func waitForCode(timeout: TimeInterval = 180) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let listener: Int32 = lock.withLock {
                guard fd >= 0, !waiting, !stopped else { return -1 }
                let copy = dup(fd)
                guard copy >= 0 else { return -1 }
                waiting = true; continuation = cont
                return copy
            }
            guard listener >= 0 else { cont.resume(returning: nil); return }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                complete(acceptAndRead(listener))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.stop()
            }
        }
    }

    func stop() {
        complete(nil)
    }

    private func complete(_ code: String?) {
        let pending = lock.withLock {
            stopped = true
            if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd); fd = -1 }
            if clientFD >= 0 { shutdown(clientFD, SHUT_RDWR) }
            let pending = continuation; continuation = nil
            return pending
        }
        pending?.resume(returning: code)
    }

    deinit { stop() }

    private func acceptAndRead(_ listener: Int32) -> String? {
        defer { close(listener) }
        let client = accept(listener, nil, nil)
        guard client >= 0 else { OAuthLog.log("accept returned \(client)"); return nil }
        let accepted = lock.withLock {
            guard !stopped else { close(client); return false }
            clientFD = client
            return true
        }
        guard accepted else { return nil }
        defer { lock.withLock { clientFD = -1; close(client) } }
        var yes: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var buf = [UInt8](repeating: 0, count: 8192)
        let n = read(client, &buf, buf.count)
        var code: String?
        var errParam: String?
        if n > 0, let req = String(bytes: buf[0..<n], encoding: .utf8),
           let line = req.split(separator: "\r\n").first {
            let parts = line.split(separator: " ")
            if parts.count >= 2, let comps = URLComponents(string: "http://127.0.0.1" + parts[1]) {
                code = comps.queryItems?.first(where: { $0.name == "code" })?.value
                errParam = comps.queryItems?.first(where: { $0.name == "error" })?.value
            }
        }
        OAuthLog.log("loopback got request (bytes=\(n)) code=\(code != nil ? "yes" : "no") error=\(errParam ?? "-")")

        let html = """
        <html><head><meta charset="utf-8"><title>Graphene</title></head>
        <body style="font-family:-apple-system,system-ui;text-align:center;padding-top:90px;color:#1b1b20">
        <h2 style="font-weight:600">Graphene is connected \u{2713}</h2>
        <p style="color:#5e5e68">You can close this tab and return to the app.</p>
        </body></html>
        """
        let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        let out = Array(resp.utf8)
        _ = out.withUnsafeBytes { raw in write(client, raw.baseAddress, out.count) }
        return code
    }

    private func posixError(_ op: String) -> NSError {
        NSError(domain: "graphene.loopback", code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "\(op) failed (errno \(errno))"])
    }
}
