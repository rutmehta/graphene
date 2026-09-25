import Foundation

struct Toast: Identifiable {
    let id = UUID()
    var icon: String
    var title: String
    var remaining: Double
    var actionTitle: String?
    var action: (@MainActor () -> Void)?
}

struct ToastQueue {
    private(set) var items: [Toast] = []
    var isPaused = false
    mutating func enqueue(title: String, icon: String = "checkmark.circle", seconds: Double = 3,
                          actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        items.append(Toast(icon: icon, title: title, remaining: seconds, actionTitle: actionTitle, action: action))
    }
    mutating func dismiss(_ id: UUID) { items.removeAll { $0.id == id }; isPaused = false }
    /// A toast's time ran out (the overlay's countdown).
    mutating func expire(_ id: UUID) { items.removeAll { $0.id == id } }
    mutating func tick(seconds: Double) {
        guard !isPaused, !items.isEmpty else { return }
        items[0].remaining -= max(0, seconds)
        if items[0].remaining <= 0 { items.removeFirst() }
    }
}

extension AppState {
    func tickToasts(seconds: Double) {
        // Guard before entering the @Published value's mutating accessor.
        // A no-op mutating call still publishes and redraws the whole shell.
        guard !toasts.isPaused, !toasts.items.isEmpty, seconds > 0 else { return }
        toasts.tick(seconds: seconds)
    }
}
