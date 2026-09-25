import Foundation
import AppKit
import CryptoKit
import ImageIO

/// Where icons may come from. `/favicon.ico` is same-origin only; a page-declared icon may
/// sit on the page's own CDN, since the page already loads from there. Either way icons are
/// fetched without cookies or credentials, redirects stay on the requested icon's origin,
/// and nothing goes to a third-party icon service.
enum FaviconPolicy {
    static func origin(_ url: URL) -> String { "\(url.scheme ?? "")://\(url.host ?? ""):\(url.port ?? (url.scheme == "https" ? 443 : 80))" }
    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        origin(lhs) == origin(rhs) && rhs.user == nil && rhs.password == nil
    }
    private static func webPage(_ page: URL) -> Bool {
        ["http", "https"].contains(page.scheme) && page.host != nil && page.user == nil && page.password == nil
    }
    /// The conventional `/favicon.ico` on the page's origin.
    static func fallbackURL(page: URL) -> URL? {
        guard webPage(page) else { return nil }
        var parts = URLComponents(url: page, resolvingAgainstBaseURL: false)
        parts?.path = "/favicon.ico"; parts?.query = nil; parts?.fragment = nil
        return parts?.url
    }
    /// A page-declared icon `href`, resolved against the page: http(s) only, never a
    /// downgrade from an https page, never with credentials.
    static func declaredURL(_ href: String, page: URL) -> URL? {
        guard webPage(page), let url = URL(string: href, relativeTo: page)?.absoluteURL,
              let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil,
              url.user == nil, url.password == nil, !(page.scheme == "https" && scheme == "http") else { return nil }
        return url
    }
}

/// An icon `<link>` from the loaded document, as the injected script reports it.
struct FaviconLink: Equatable {
    var href: String
    var rel: String
    var sizes = ""
    var type = ""
}

/// Orders the icons a page declares: `rel=icon` before `apple-touch-icon`; within each,
/// SVG, then the smallest size of at least 32px, then unsized, then smaller sizes.
/// `/favicon.ico` is the last resort after every declared candidate.
enum FaviconDiscovery {
    /// Types an icon link may declare (empty means undeclared). Mask icons and anything else are skipped.
    static let acceptedTypes: Set<String> = ["", "image/png", "image/svg+xml", "image/x-icon", "image/vnd.microsoft.icon",
                                             "image/ico", "image/icon", "image/gif", "image/jpeg", "image/webp"]
    /// Icons at least this many pixels across are sharp at the sidebar's 16pt on Retina.
    static let preferredPixels = 32
    /// At most this many declared candidates are tried per page.
    static let maxCandidates = 4

    /// Reads the script's `icons` array.
    static func links(from payload: Any?) -> [FaviconLink] {
        guard let items = payload as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let href = item["href"] as? String, !href.isEmpty, let rel = item["rel"] as? String else { return nil }
            return FaviconLink(href: href, rel: rel, sizes: item["sizes"] as? String ?? "", type: item["type"] as? String ?? "")
        }
    }

    static func candidates(_ links: [FaviconLink], page: URL) -> [URL] {
        let ranked = links.enumerated().compactMap { index, link -> (rank: [Int], url: URL)? in
            let rels = Set(link.rel.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            let tier: Int
            if rels.contains("icon") { tier = 0 }
            else if rels.contains("apple-touch-icon") || rels.contains("apple-touch-icon-precomposed") { tier = 1 }
            else { return nil }
            let type = link.type.lowercased().trimmingCharacters(in: .whitespaces)
            guard acceptedTypes.contains(type), let url = FaviconPolicy.declaredURL(link.href, page: page) else { return nil }
            return ([tier, sizeRank(link, type: type, url: url), index], url)
        }.sorted { $0.rank.lexicographicallyPrecedes($1.rank) }
        var seen = Set<URL>()
        return Array(ranked.map(\.url).filter { seen.insert($0).inserted }.prefix(maxCandidates))
    }

    /// Lower is better: vector, then ≥ 32px ascending, then unsized, then < 32px descending.
    private static func sizeRank(_ link: FaviconLink, type: String, url: URL) -> Int {
        let sizes = link.sizes.lowercased().split(whereSeparator: \.isWhitespace)
        if type == "image/svg+xml" || url.pathExtension.lowercased() == "svg" || sizes.contains("any") { return 0 }
        let pixels = sizes.compactMap { size -> Int? in
            let parts = size.split(separator: "x")
            guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else { return nil }
            return max(width, height)
        }
        if let best = pixels.filter({ $0 >= preferredPixels }).min() { return 1 + best }
        if let largest = pixels.max() { return 1_000_000 - largest }
        return 100_000
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
    /// Each icon's contrast class, computed once when the icon is stored.
    private(set) var tones: [String: FaviconTone] = [:]
    /// The URL each origin's icon came from, so a page re-declaring it does not refetch.
    private var sources: [String: URL] = [:]
    private var attempts: [URL: Date] = [:]
    private var requests: [String: UUID] = [:]
    private let directory = Paths.root.appendingPathComponent("Favicons", isDirectory: true)
    private static let maxBytes = 524288
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.httpCookieAcceptPolicy = .never; config.httpShouldSetCookies = false; config.urlCache = nil
        return URLSession(configuration: config, delegate: IconRedirectPolicy(), delegateQueue: nil)
    }()

    private func key(page: URL?, host: String?) -> String? {
        if let page { return FaviconPolicy.origin(page) }
        guard let host else { return nil }
        return icons.keys.first { URL(string: $0)?.host == host }
    }

    func image(page: URL?, host: String?) -> NSImage? {
        key(page: page, host: host).flatMap { icons[$0] }
    }

    func tone(page: URL?, host: String?) -> FaviconTone {
        key(page: page, host: host).flatMap { tones[$0] } ?? .other
    }

    /// Fetches the icon for `page`'s origin: each `declared` candidate in order (from
    /// `FaviconDiscovery`), then `/favicon.ico`. Without candidates a cached icon is reused.
    func fetch(_ page: URL, declared: [URL] = []) async {
        guard let fallback = FaviconPolicy.fallbackURL(page: page) else { return }
        let key = FaviconPolicy.origin(page)
        let filename = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(filename + ".icon")
        if declared.isEmpty {
            if icons[key] != nil { return }
            if let attributes = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = attributes.contentModificationDate, Date().timeIntervalSince(date) < 604800,
               let data = try? Data(contentsOf: file), let image = Self.decode(data) { store(image, key: key, source: nil); return }
        } else if let first = declared.first, icons[key] != nil, sources[key] == first {
            return
        }
        let request = UUID(); requests[key] = request
        for url in declared + [fallback] {
            if let date = attempts[url], Date().timeIntervalSince(date) < 60 { continue }
            attempts[url] = Date()
            guard let data = await download(url), requests[key] == request, let image = Self.decode(data) else { continue }
            if icons.count >= 128, let oldest = icons.keys.sorted().first { icons.removeValue(forKey: oldest); tones.removeValue(forKey: oldest) }
            store(image, key: key, source: url)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            trimDisk()
            break
        }
        if attempts.count > 256 { attempts = attempts.filter { Date().timeIntervalSince($0.value) < 60 } }
    }

    private func store(_ image: NSImage, key: String, source: URL?) {
        tones[key] = Self.tone(of: image)
        sources[key] = source
        icons[key] = image
    }

    /// The icon's bytes, or `nil` for a non-200, an off-origin redirect, a non-image or an oversize body.
    private func download(_ url: URL) async -> Data? {
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let finalURL = response.url, FaviconPolicy.sameOrigin(url, finalURL),
                  response.mimeType.map({ $0.hasPrefix("image/") || $0 == "application/octet-stream" }) ?? true,
                  response.expectedContentLength <= Self.maxBytes else { return nil }
            var data = Data()
            for try await byte in bytes { guard data.count < Self.maxBytes else { return nil }; data.append(byte) }
            return data
        } catch { return nil }
    }

    /// PNG, ICO, GIF, JPEG and WebP through ImageIO; SVG through AppKit's vector image rep.
    static func decode(_ data: Data) -> NSImage? {
        guard data.count <= maxBytes else { return nil }
        if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 2048, height <= 2048 else { return nil }
            return NSImage(data: data)
        }
        guard let head = String(data: data.prefix(1024), encoding: .utf8), head.contains("<svg"),
              let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        return image
    }

    /// Classifies an icon from its alpha-weighted mean luminance and chroma at 16×16.
    static func tone(of image: NSImage) -> FaviconTone {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .other }
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .other }
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        var weight = 0.0, luminance = 0.0, chroma = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0 else { continue }
            let channel = { (offset: Int) in min(1, Double(pixels[index + offset]) / 255 / alpha) }
            let r = channel(0), g = channel(1), b = channel(2)
            weight += alpha
            luminance += alpha * (0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b))
            chroma += alpha * (max(r, g, b) - min(r, g, b))
        }
        guard weight / Double(side * side) >= FaviconTone.minimumCoverage else { return .other }
        return FaviconTone.classify(meanLuminance: luminance / weight, meanChroma: chroma / weight)
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
