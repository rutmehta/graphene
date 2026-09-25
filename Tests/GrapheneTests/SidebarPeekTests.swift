import XCTest
@testable import Graphene

final class SidebarPeekTests: XCTestCase {
    func testArmsOnlyInsideTheEdgeZone() {
        XCTAssertTrue(SidebarPeekRule.shouldArm(x: 0, y: 400, windowHeight: 820))
        XCTAssertTrue(SidebarPeekRule.shouldArm(x: 8, y: 819, windowHeight: 820))
        XCTAssertTrue(SidebarPeekRule.shouldArm(x: -8, y: 10, windowHeight: 820), "overshoot past the window edge still arms")
        XCTAssertFalse(SidebarPeekRule.shouldArm(x: 9, y: 400, windowHeight: 820))
        XCTAssertFalse(SidebarPeekRule.shouldArm(x: -9, y: 400, windowHeight: 820))
        XCTAssertFalse(SidebarPeekRule.shouldArm(x: 2, y: -1, windowHeight: 820))
        XCTAssertFalse(SidebarPeekRule.shouldArm(x: 2, y: 821, windowHeight: 820))
    }
    func testHidesPastThePanelOrOutsideTheWindow() {
        let w = ShellLayout.sidebarDefault
        XCTAssertFalse(SidebarPeekRule.shouldHide(x: w, y: 400, windowHeight: 820, sidebarWidth: w))
        XCTAssertFalse(SidebarPeekRule.shouldHide(x: w + ShellLayout.windowGap + SidebarPeekRule.hideSlack, y: 400, windowHeight: 820, sidebarWidth: w))
        XCTAssertTrue(SidebarPeekRule.shouldHide(x: w + ShellLayout.windowGap + SidebarPeekRule.hideSlack + 1, y: 400, windowHeight: 820, sidebarWidth: w))
        XCTAssertTrue(SidebarPeekRule.shouldHide(x: 50, y: -1, windowHeight: 820, sidebarWidth: w))
        XCTAssertTrue(SidebarPeekRule.shouldHide(x: 50, y: 900, windowHeight: 820, sidebarWidth: w))
    }
    func testDwellIsShorterThanTheOldStripDelay() {
        XCTAssertLessThanOrEqual(SidebarPeekRule.dwell, .milliseconds(200))
    }
}
