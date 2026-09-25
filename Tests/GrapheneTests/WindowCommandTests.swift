import XCTest
import AppKit
@testable import Graphene

final class WindowCommandTests: XCTestCase {
    @MainActor func testCloseKeyboardCommandStillClosesABrowserTab() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previousWindow = BrowserFocus.shared.window
        defer { BrowserFocus.shared.window = previousWindow; try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let original = app.activeTabID
        let browser = CloseTrackingWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        BrowserFocus.shared.window = browser
        app.closeFromKeyboard(in: browser)
        XCTAssertFalse(browser.closeRequested)
        XCTAssertNotEqual(app.activeTabID, original)
    }

    @MainActor func testCloseKeyboardCommandDoesNotCloseTabsBehindSettings() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let original = app.activeTabID
        let settings = CloseTrackingWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        app.closeFromKeyboard(in: settings)
        XCTAssertTrue(settings.closeRequested)
        XCTAssertEqual(app.activeTabID, original)
    }
}

private final class CloseTrackingWindow: NSWindow {
    var closeRequested = false
    override func performClose(_ sender: Any?) { closeRequested = true }
}
