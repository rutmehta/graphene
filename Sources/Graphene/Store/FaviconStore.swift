import Foundation
import AppKit
import CryptoKit
import ImageIO

/// Same-origin only, including redirects: icon discovery must not leak history to a service.
enum FaviconPolicy {
    static func origin(_ url: URL) -> String { "\(url.scheme ?? "")://\(url.host ?? ""):\(url.port ?? (url.scheme == "https" ? 443 : 80))" }
    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        origin(lhs) == origin(rhs) && rhs.user == nil && rhs.password == nil
    }
    static func iconURL(page: URL, declared: String?) -> URL? {
        guard ["http", "https"].contains(page.scheme), page.host != nil, page.user == nil, page.password == nil else { return nil }
        if let declared, let url = URL(string: declared, relativeTo: page)?.absoluteURL, sameOrigin(page, url) { return url }
        var parts = URLComponents(url: page, resolvingAgainstBaseURL: false)
        parts?.path = "/favicon.ico"; parts?.query = nil; parts?.fragment = nil
        return parts?.url
    }
}

private final class IconRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let next = request.url, FaviconPolicy.sameOrigin(original, next) else { completionHandler(nil); return }
        completionHandler(request)
    }
}

@MainActor
final class FaviconStore: ObservableObject {
    static let shared = FaviconStore()
    @Published private(set) var icons: [String: NSImage] = [:]
    private var attempts: [URL: Date] = [:]
    private var requests: [String: UUID] = [:]
    private let directory = Paths.root.appendingPathComponent("Favicons", isDirectory: true)
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.httpCookieAcceptPolicy = .never; config.httpShouldSetCookies = false; config.urlCache = nil
        return URLSession(configuration: config, delegate: IconRedirectPolicy(), delegateQueue: nil)
    }()

    func image(page: URL?, host: String?) -> NSImage? {
        if let page { return icons[FaviconPolicy.origin(page)] }
        guard let host else { return nil }
        return icons.first { URL(string: $0.key)?.host == host }?.value
    }

    func fetch(_ page: URL, declared: String? = nil) async {
        guard let url = FaviconPolicy.iconURL(page: page, declared: declared) else { return }
        let key = FaviconPolicy.origin(page)
        let filename = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(filename + ".icon")
        if declared == nil {
            if icons[key] != nil { return }
            if let attributes = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = attributes.contentModificationDate, Date().timeIntervalSince(date) < 604800,
               let data = try? Data(contentsOf: file), let image = decode(data) { icons[key] = image; return }
        }
        if let date = attempts[url], Date().timeIntervalSince(date) < 60 { return }
        attempts[url] = Date()
        let request = UUID(); requests[key] = request
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let finalURL = response.url, FaviconPolicy.sameOrigin(page, finalURL),
                  response.mimeType?.hasPrefix("image/") == true, response.expectedContentLength <= 524288 else { return }
            var data = Data()
            for try await byte in bytes { guard data.count < 524288 else { return }; data.append(byte) }
            guard requests[key] == request, let image = decode(data) else { return }
            if icons.count >= 128, let oldest = icons.keys.sorted().first { icons.removeValue(forKey: oldest) }
            icons[key] = image
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            trimDisk()
            if attempts.count > 256 { attempts = attempts.filter { Date().timeIntervalSince($0.value) < 60 } }
        } catch { /* A missing/invalid icon leaves the monogram, with a bounded retry window. */ }
    }

    private func decode(_ data: Data) -> NSImage? {
        guard data.count <= 524288,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 2048, height <= 2048 else { return nil }
        return NSImage(data: data)
    }

    private func trimDisk() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        let entries = files.filter { $0.pathExtension == "icon" }.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 > $1.2 }
        var bytes = 0
        for (index, entry) in entries.enumerated() {
            bytes += entry.1
            if index >= 128 || bytes > 8 * 1024 * 1024 { try? FileManager.default.removeItem(at: entry.0) }
        }
    }
}
