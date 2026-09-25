import XCTest
@testable import Graphene

final class PageToolbarTests: XCTestCase {
    func testToolbarHeightAndLeadingInset() {
        XCTAssertEqual(ShellLayout.pageToolbarHeight, 32)
        XCTAssertLessThanOrEqual(ShellLayout.controlSize, ShellLayout.pageToolbarHeight)
        // Expanded sidebar: the nav group starts 8 into the card.
        XCTAssertEqual(PageToolbarGeometry.leadingInset(reservesTrafficLights: false, cardOriginX: 224), 8)
        // Collapsed: the card sits at windowGap, and the group starts at x = 84 in the window.
        let inset = PageToolbarGeometry.leadingInset(reservesTrafficLights: true, cardOriginX: ShellLayout.windowGap)
        XCTAssertEqual(ShellLayout.windowGap + inset, ShellLayout.trafficReserve)
        // Without the page gutter the card starts at the window edge; the reserve still holds.
        XCTAssertEqual(PageToolbarGeometry.leadingInset(reservesTrafficLights: true, cardOriginX: 0), ShellLayout.trafficReserve)
        // The third traffic light's right edge stays left of the first control.
        let lastLightEdge = ShellLayout.trafficLightLeading + 2 * ShellLayout.trafficLightSpacing + 7
        XCTAssertLessThan(lastLightEdge, ShellLayout.trafficReserve)
    }

    func testAddressWidthCapsAtSixtyPercentOfCard() {
        XCTAssertEqual(PageToolbarGeometry.addressMaxWidth(cardWidth: 1000), 600)
        XCTAssertEqual(PageToolbarGeometry.addressMaxWidth(cardWidth: 0), 0)
    }

    func testProgressMapping() {
        XCTAssertEqual(PageToolbarGeometry.progressFraction(isLoading: true, progress: 0), PageToolbarGeometry.minimumProgress)
        XCTAssertEqual(PageToolbarGeometry.progressFraction(isLoading: true, progress: 0.42), 0.42, accuracy: 0.0001)
        XCTAssertEqual(PageToolbarGeometry.progressFraction(isLoading: true, progress: 1.4), 1)
        // A finished load fills the bar, then fades out.
        XCTAssertEqual(PageToolbarGeometry.progressFraction(isLoading: false, progress: 0.3), 1)
        XCTAssertEqual(PageToolbarGeometry.progressOpacity(isLoading: true), 1)
        XCTAssertEqual(PageToolbarGeometry.progressOpacity(isLoading: false), 0)
        XCTAssertEqual(PageToolbarGeometry.progressEase, 0.15)
        XCTAssertEqual(PageToolbarGeometry.progressFade, 0.2)
    }

    func testAddressParts() throws {
        let parts = try XCTUnwrap(AddressParts(url: URL(string: "https://www.example.com/docs/page?q=1#top")))
        XCTAssertEqual(parts.host, "example.com")
        XCTAssertEqual(parts.rest, "/docs/page?q=1#top")
        XCTAssertTrue(parts.secure)
        let root = try XCTUnwrap(AddressParts(url: URL(string: "http://localhost:8080/")))
        XCTAssertEqual(root.host, "localhost")
        XCTAssertEqual(root.rest, ":8080")
        XCTAssertFalse(root.secure)
        XCTAssertNil(AddressParts(url: nil))
        let about = try XCTUnwrap(AddressParts(url: URL(string: "about:blank")))
        XCTAssertEqual(about.host, "about:blank")
        XCTAssertEqual(about.rest, "")
    }

    func testSplitCardsAreSeparatedByWindowGap() {
        let lengths = SplitCardGeometry.paneLengths(total: 1008, fractions: [0.5, 0.5, 0.5], count: 2)
        XCTAssertEqual(lengths, [500, 500])
        XCTAssertEqual(lengths.reduce(0, +) + ShellLayout.windowGap, 1008)
        let three = SplitCardGeometry.paneLengths(total: 1216, fractions: [0.5, 0.5], count: 3)
        XCTAssertEqual(three.count, 3)
        XCTAssertEqual(three.reduce(0, +) + 2 * ShellLayout.windowGap, 1216, accuracy: 0.001)
        XCTAssertEqual(three[0], 604)
        XCTAssertEqual(SplitCardGeometry.paneLengths(total: 800, fractions: [], count: 1), [800])
        XCTAssertEqual(SplitCardGeometry.paneLengths(total: 800, fractions: [], count: 0), [])
        XCTAssertEqual(SplitCardGeometry.firstPaneLength(available: 4, fraction: 0.5), 0)
    }

    func testPeekCardGeometry() {
        XCTAssertEqual(PeekGeometry.cardSize(in: CGSize(width: 1200, height: 800)), CGSize(width: 900, height: 720))
        XCTAssertEqual(PeekGeometry.cardSize(in: CGSize(width: 600, height: 500)), CGSize(width: 520, height: 420))
        XCTAssertEqual(ShellLayout.littleArcSize, CGSize(width: 760, height: 560))
    }

    func testAddressPlacementDefaultsOnPageAndDecodesOldSettings() throws {
        XCTAssertEqual(Settings().addressPlacement, .onPage)
        let old = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.addressPlacement, .onPage)
        var settings = Settings()
        settings.addressPlacement = .sidebar
        let round = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(round.addressPlacement, .sidebar)
    }
}
