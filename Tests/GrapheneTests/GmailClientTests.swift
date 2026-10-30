import XCTest
@testable import Graphene

final class GmailClientTests: XCTestCase {
    func testParseFromFallsBackForMalformedBrackets() {
        for raw in [
            "Sender >sender@example.com<",
            "Sender > <sender@example.com>",
            "Sender <sender@example.com",
            "Sender sender@example.com>",
            "<",
            ">",
        ] {
            let (name, address) = GmailClient.parseFrom("  \(raw)  ")
            XCTAssertEqual(name, "", raw)
            XCTAssertEqual(address, raw, raw)
        }
    }

    func testParseFromPreservesSupportedHeaders() {
        let cases: [(raw: String, name: String, address: String)] = [
            ("Sender <sender@example.com>", "Sender", "sender@example.com"),
            ("\"Sender Name\" <sender@example.com>", "Sender Name", "sender@example.com"),
            ("<sender@example.com>", "", "sender@example.com"),
            ("  sender@example.com  ", "", "sender@example.com"),
            ("Sender <>", "Sender", ""),
            ("", "", ""),
        ]
        for test in cases {
            let (name, address) = GmailClient.parseFrom(test.raw)
            XCTAssertEqual(name, test.name, test.raw)
            XCTAssertEqual(address, test.address, test.raw)
        }
    }
}
