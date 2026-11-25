import XCTest
@testable import Graphene

final class OmniboxRoutingTests: XCTestCase {
    func testExplicitSchemesAreCaseInsensitive() throws {
        for input in ["HTTP://example.com/CaseSensitive?key=Value", "HTTPS://example.com/CaseSensitive?key=Value", "GrApHeNe://settings"] {
            guard case let .navigate(url) = Omnibox.resolve(input) else {
                XCTFail("Expected navigation for \(input)"); continue
            }
            XCTAssertEqual(url, try XCTUnwrap(URL(string: input)))
            XCTAssertFalse(Omnibox.isQuestion(input))
        }
    }

    func testLocalhostSupportsPortsPathsQueriesAndFragments() {
        for input in ["localhost", "localhost:8080", "LOCALHOST:8080/path", "localhost/path", "localhost?query=value", "localhost#section"] {
            guard case let .navigate(url) = Omnibox.resolve(input) else {
                XCTFail("Expected local navigation for \(input)"); continue
            }
            XCTAssertEqual(url.scheme, "http")
            XCTAssertEqual(url.host?.lowercased(), "localhost")
            XCTAssertEqual(url.absoluteString, "http://" + input)
        }
    }

    func testLocalhostPrefixDoesNotForceRemoteDomainsOntoHTTP() {
        for input in ["localhost.example.com", "localhost.example.com:8080/path", "localhosting.example/path"] {
            guard case let .navigate(url) = Omnibox.resolve(input) else {
                XCTFail("Expected domain navigation for \(input)"); continue
            }
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.absoluteString, "https://" + input)
        }
    }

    func testLocalhostSearchTermsRemainSearches() {
        for input in ["localhosting", "localhost tutorial", "localhost:8080 tutorial"] {
            guard case let .search(_, query) = Omnibox.resolve(input) else {
                XCTFail("Expected search for \(input)"); continue
            }
            XCTAssertEqual(query, input)
        }
    }
}
