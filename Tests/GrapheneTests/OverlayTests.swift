import XCTest
import AppKit
import SwiftUI
@testable import Graphene

/// Command bar, chat, toast and motion geometry (arc-look.md §3.4–3.6, §4).
final class OverlayTests: XCTestCase {
    func testCommandBarWidthAndTopFollowTheWindow() {
        XCTAssertEqual(CommandBarLayout.width(window: 1280), ShellLayout.commandWidth)
        XCTAssertEqual(CommandBarLayout.width(window: 600), 520)
        XCTAssertEqual(CommandBarLayout.width(window: 40), 0)
        XCTAssertEqual(CommandBarLayout.top(window: 820), 820 * 0.18, accuracy: 0.001)
        XCTAssertEqual(CommandBarLayout.top(window: 0), 0)
    }

    func testSectionLabelsOnlyWhenMoreThanOneSection() {
        XCTAssertTrue(CommandBarLayout.sectionStarts([]).isEmpty)
        XCTAssertTrue(CommandBarLayout.sectionStarts(["Tabs", "Tabs", "Tabs"]).isEmpty)
        XCTAssertEqual(CommandBarLayout.sectionStarts(["Tabs", "Tabs", "History", "Commands"]), [0, 2, 3])
    }

    func testCommandListHeightCapsAtEightRows() {
        let row = ShellLayout.commandRowHeight, label = ShellLayout.commandSectionHeight, pad = ShellLayout.commandListPadding
        XCTAssertEqual(CommandBarLayout.listHeight([]), 0)
        // One section: no labels, padding above and below.
        XCTAssertEqual(CommandBarLayout.listHeight(Array(repeating: "Tabs", count: 3)), 3 * row + 2 * pad)
        XCTAssertEqual(CommandBarLayout.listHeight(Array(repeating: "Tabs", count: 12)), 8 * row + 2 * pad)
        // Two sections: the list opens with a label, so no top padding.
        XCTAssertEqual(CommandBarLayout.listHeight(["Tabs", "Tabs", "History"]), 3 * row + 2 * label + pad)
        // Labels past the eighth row scroll with their rows.
        let long = Array(repeating: "Tabs", count: 9) + ["History"]
        XCTAssertEqual(CommandBarLayout.listHeight(long), 8 * row + label + pad)
        XCTAssertEqual(ShellLayout.commandMaxRows, 8)
    }

    @MainActor
    func testPresentCommandBarSeedsTheURLSelectedInPlace() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(directory: directory)
        let seed = URL(string: "https://swift.org/documentation/")!
        app.presentCommandBar(seedURL: seed)
        XCTAssertTrue(app.commandBarPresented)
        XCTAssertFalse(app.commandBarCreatesTab, "The URL variant replaces the current page and selects the draft")
        XCTAssertEqual(app.commandBarDraft, seed.absoluteString)
        let request = app.commandBarFocusRequest
        let other = URL(string: "https://example.com/")!
        app.presentCommandBar(seedURL: other)
        XCTAssertEqual(app.commandBarDraft, other.absoluteString, "Reopening while shown reseeds")
        XCTAssertGreaterThan(app.commandBarFocusRequest, request, "Reopening refocuses so the text is selected again")
        app.dismissCommandBar()
        app.presentCommandBar()
        XCTAssertEqual(app.commandBarDraft, app.activeTab?.url?.absoluteString ?? "", "Without a seed it uses the active tab's URL")
        app.dismissCommandBar()
        app.focusAddress()
        XCTAssertTrue(app.commandBarPresented)
        XCTAssertFalse(app.commandBarCreatesTab)
    }

    func testFloatingChatInsetsFromThePageCard() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let inset = ShellLayout.windowGap * 2
        let frames = ShellContentLayout.frames(in: bounds, showAsk: true, preferredAskWidth: ShellLayout.chatWidth, floats: true)
        XCTAssertEqual(frames.page, bounds)
        XCTAssertEqual(frames.chat, CGRect(x: 1000 - 420 - inset, y: inset, width: 420, height: 800 - 2 * inset))
    }

    func testDockedChatSharesTheRowWithAGutter() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let frames = ShellContentLayout.frames(in: bounds, showAsk: true, preferredAskWidth: 400, floats: false)
        XCTAssertEqual(frames.page.width, 1000 - 400 - ShellLayout.windowGap)
        XCTAssertEqual(frames.chat, CGRect(x: 600, y: 0, width: 400, height: 800))
        XCTAssertEqual(frames.chat.minX - frames.page.maxX, ShellLayout.windowGap)
        let hidden = ShellContentLayout.frames(in: bounds, showAsk: false, preferredAskWidth: 400, floats: false)
        XCTAssertEqual(hidden.page, bounds)
        XCTAssertEqual(hidden.chat.width, 0)
    }

    func testChatWidthClampsToTheTokenRange() {
        let bounds = CGRect(x: 0, y: 0, width: 2000, height: 800)
        XCTAssertEqual(ShellContentLayout.frames(in: bounds, showAsk: true, preferredAskWidth: 900, floats: true).chat.width, ShellLayout.chatWidthRange.upperBound)
        XCTAssertEqual(ShellContentLayout.frames(in: bounds, showAsk: true, preferredAskWidth: 100, floats: true).chat.width, ShellLayout.chatWidthRange.lowerBound)
        var settings = Settings()
        settings.askWidth = 10_000
        XCTAssertEqual(settings.askWidth, Double(ShellLayout.chatWidthRange.upperBound))
        settings.askWidth = 0
        XCTAssertEqual(settings.askWidth, Double(ShellLayout.chatWidthRange.lowerBound))
        XCTAssertEqual(Settings().askWidth, Double(ShellLayout.chatWidth))
        XCTAssertEqual(ShellLayout.chatHeaderHeight, 44)
        XCTAssertEqual(ShellLayout.chipHeight, 24)
        XCTAssertEqual(ShellLayout.composerMinHeight, 40)
        XCTAssertEqual(ShellType.rowLineSpacing, ShellType.rowSize * 0.45, accuracy: 0.001)
    }

    func testToastAndSwitcherTokens() {
        XCTAssertEqual(ShellLayout.toastMaxWidth, 420)
        XCTAssertEqual(ShellLayout.toastHeight, 40)
        XCTAssertEqual(ShellLayout.toastInset, 24)
        XCTAssertEqual(ShellLayout.thumbnailSize, CGSize(width: 96, height: 60))
        XCTAssertEqual(ShellLayout.siteControlsWidth, 320)
        XCTAssertEqual(Motion.toastRise, 8)
    }

    func testMotionTableMatchesSpec() {
        XCTAssertEqual(Motion.collapse.curve, .spring(response: 0.30, dampingFraction: 0.75))
        XCTAssertEqual(Motion.peek.curve, .spring(response: 0.28, dampingFraction: 0.8))
        XCTAssertEqual(Motion.panel.curve, .spring(response: 0.32, dampingFraction: 0.8))
        XCTAssertEqual(Motion.commandIn.curve, .easeOut(duration: 0.12))
        XCTAssertEqual(Motion.commandOut.curve, .easeOut(duration: 0.09))
        XCTAssertEqual(Motion.toast.curve, .easeOut(duration: 0.16))
        XCTAssertEqual(Motion.hover.curve, .easeOut(duration: 0.10))
        XCTAssertEqual(Motion.spaceSwitch.curve, .easeOut(duration: 0.18))
        XCTAssertEqual(Motion.progress.curve, .easeOut(duration: 0.15))
        XCTAssertEqual(Motion.progressFade.curve, .easeOut(duration: 0.20))
        XCTAssertEqual(Motion.reducedCurve, .easeOut(duration: 0.12))
        XCTAssertEqual(Motion.commandScale, 0.98)
        XCTAssertEqual(Motion.panelOffset, 24)
    }

    @MainActor
    func testCommandSurfacesUseSpecColours() {
        let dark = Palette(mode: .dark, space: .iris)
        let light = Palette(mode: .light, space: .iris)
        func alpha(_ color: Color) -> CGFloat { NSColor(color).usingColorSpace(.sRGB)?.alphaComponent ?? -1 }
        XCTAssertEqual(alpha(dark.commandScrim), 0.20, accuracy: 0.01)
        XCTAssertEqual(alpha(light.commandScrim), 0.10, accuracy: 0.01)
        XCTAssertEqual(alpha(dark.commandShadow), 0.30, accuracy: 0.01)
        XCTAssertEqual(dark.commandShadowRadius, 32)
        XCTAssertEqual(dark.commandShadowY, 12)
        // Chips and bubbles stay visible on the white light-mode card.
        XCTAssertGreaterThan(alpha(light.elevFill), 0)
        XCTAssertNotEqual(NSColor(light.elevFill).usingColorSpace(.sRGB)?.redComponent, 1)
    }
}
