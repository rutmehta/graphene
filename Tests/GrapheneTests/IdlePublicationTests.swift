import XCTest
import Combine
@testable import Graphene

final class IdlePublicationTests: XCTestCase {
    @MainActor func testUnchangedMediaPollDoesNotInvalidateShell() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        var changes = 0
        let observation = app.objectWillChange.sink { changes += 1 }
        await app.pollMediaAndDiscard()
        XCTAssertEqual(changes, 0, "Idle polling must not publish an unchanged shell")
        withExtendedLifetime(observation) {}
    }

    @MainActor func testEmptyAndPausedToastsDoNotInvalidateShell() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(directory: root)
        var changes = 0
        let observation = app.objectWillChange.sink { changes += 1 }
        app.tickToasts(seconds: 0.25)
        XCTAssertEqual(changes, 0)
        app.toasts.enqueue(title: "Saved", seconds: 1)
        app.toasts.isPaused = true
        changes = 0
        app.tickToasts(seconds: 1)
        XCTAssertEqual(changes, 0)
        app.toasts.isPaused = false
        app.tickToasts(seconds: 1)
        XCTAssertTrue(app.toasts.items.isEmpty)
        withExtendedLifetime(observation) {}
    }
}
