import XCTest
@testable import Graphene

final class GmailParseFromTests: XCTestCase {
    func testNameAndAddress() {
        XCTAssertEqual(GmailClient.parseFrom("\"Ada Lovelace\" <ada@example.com>").0, "Ada Lovelace")
        XCTAssertEqual(GmailClient.parseFrom("\"Ada Lovelace\" <ada@example.com>").1, "ada@example.com")
        XCTAssertEqual(GmailClient.parseFrom(" ada@example.com ").1, "ada@example.com")
    }

    /// A `>` before the `<` used to build an inverted range and trap while loading the inbox.
    func testClosingBracketBeforeOpeningDoesNotCrash() {
        let (name, address) = GmailClient.parseFrom("a>b <ada@example.com>")
        XCTAssertEqual(name, "a>b")
        XCTAssertEqual(address, "ada@example.com")

        let (n2, a2) = GmailClient.parseFrom("weird> <unterminated")
        XCTAssertEqual(n2, "")
        XCTAssertEqual(a2, "weird> <unterminated")

        XCTAssertEqual(GmailClient.parseFrom(">x<").1, ">x<")
    }
}
