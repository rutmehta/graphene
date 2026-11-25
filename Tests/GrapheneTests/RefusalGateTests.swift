import XCTest
@testable import Graphene

final class RefusalGateTests: XCTestCase {
    func testCannedRefusalsAreRecognised() {
        for text in ["I cannot fulfill that request.", "I can’t assist with that.", "Sorry, I can't help with that.",
                     "  I'm unable to summarize this page.\n", "I am not able to provide a summary of this content."] {
            XCTAssertTrue(RefusalGate.isRefusal(text), text)
        }
    }
    func testGroundedAnswersAreNotRefusals() {
        for text in ["I cannot find that in the sources.", "The site says it cannot comply with older browsers.",
                     "Example Domain is reserved for documentation.", ""] {
            XCTAssertFalse(RefusalGate.isRefusal(text), text)
        }
        let long = "I cannot fulfill " + String(repeating: "every part of this, but here is what the page does say about the topic. ", count: 3)
        XCTAssertFalse(RefusalGate.isRefusal(long), "A long answer that mentions a limit is still an answer")
    }
    func testShortRefusalIsHeldAndNeverShown() {
        var gate = RefusalGate()
        XCTAssertNil(gate.receive("I cannot"))
        XCTAssertNil(gate.receive("I cannot fulfill that request."))
        XCTAssertEqual(gate.finish(), .refused)
        XCTAssertFalse(gate.released)
    }
    func testShortAnswerIsReleasedWhole() {
        var gate = RefusalGate()
        XCTAssertNil(gate.receive("Example Domain"))
        XCTAssertNil(gate.receive("Example Domain is for documentation."))
        XCTAssertEqual(gate.finish(), .text("Example Domain is for documentation."))
    }
    func testLongAnswerStreamsOnceItPassesTheHoldLimit() {
        var gate = RefusalGate()
        let opening = String(repeating: "a", count: RefusalGate.holdLimit)
        XCTAssertNil(gate.receive(opening))
        XCTAssertEqual(gate.receive(opening + "bc"), opening + "bc")
        XCTAssertTrue(gate.released)
        XCTAssertEqual(gate.receive(opening + "bcd"), "d")
        XCTAssertNil(gate.receive(opening + "bcd"))
        XCTAssertEqual(gate.finish(), .text(""))
    }
}
