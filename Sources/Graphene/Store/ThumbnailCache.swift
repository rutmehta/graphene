import AppKit

/// One process-wide bound, shared by all browser windows. Private pages are never cached.
/// Each entry remembers the URL it was taken at, so a page is snapshotted at most once per
/// navigation (`TabLifecycle.needsThumbnail`).
@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    @Published private(set) var images: [UUID: NSImage] = [:]
    private var order: [UUID] = []
    /// The URL each tab was last snapshotted (or is being snapshotted) at.
    private var captured: [UUID: URL] = [:]
    let capacity: Int
    init(capacity: Int = 40) { self.capacity = max(0, capacity) }
    func put(_ image: NSImage, for id: UUID, url: URL? = nil) {
        images[id] = image; order.removeAll { $0 == id }; order.append(id)
        if let url { captured[id] = url }
        while order.count > capacity {
            let evicted = order.removeFirst()
            images.removeValue(forKey: evicted); captured.removeValue(forKey: evicted)
        }
    }
    func capturedURL(_ id: UUID) -> URL? { captured[id] }
    /// Records a snapshot in flight, so a second request for the same page does not start another.
    func markCaptured(_ url: URL, for id: UUID) { captured[id] = url }
    /// A snapshot failed: the page may be captured again.
    func forgetCapture(_ id: UUID) { captured.removeValue(forKey: id) }
}
