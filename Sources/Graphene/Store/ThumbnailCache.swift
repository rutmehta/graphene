import AppKit

/// One process-wide bound, shared by all browser windows. Private pages are never cached.
@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    @Published private(set) var images: [UUID: NSImage] = [:]
    private var order: [UUID] = []
    let capacity: Int
    init(capacity: Int = 40) { self.capacity = max(0, capacity) }
    func put(_ image: NSImage, for id: UUID) {
        images[id] = image; order.removeAll { $0 == id }; order.append(id)
        while order.count > capacity { images.removeValue(forKey: order.removeFirst()) }
    }
}
