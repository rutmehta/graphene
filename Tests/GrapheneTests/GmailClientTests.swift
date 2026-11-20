import XCTest
@testable import Graphene

final class GmailClientTests: XCTestCase {
    private func listInbox(_ scenario: String) async throws -> [MailItem] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InboxURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await GmailClient.listInbox(accessToken: scenario, session: session)
    }

    func testMetadataAuthorizationFailureReachesCaller() async throws {
        do {
            _ = try await listInbox("unauthorized")
            XCTFail("A metadata 401 must reach the caller so it can refresh the token")
        } catch GmailError.unauthorized {
            // MailStore handles this error by refreshing once and retrying.
        }
    }

    func testMetadataHTTPFailureReachesCaller() async throws {
        do {
            _ = try await listInbox("unavailable")
            XCTFail("Failed metadata requests must not look like an empty inbox")
        } catch GmailError.http(let status) {
            XCTAssertEqual(status, 503)
        }
    }

    func testMetadataNetworkFailureReachesCaller() async throws {
        do {
            _ = try await listInbox("offline")
            XCTFail("Network errors must not look like an empty inbox")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }
    }

    func testLaterMetadataFailureDoesNotReturnPartialSuccess() async throws {
        do {
            _ = try await listInbox("partial")
            XCTFail("A later metadata failure must not return a successful partial inbox")
        } catch GmailError.http(let status) {
            XCTAssertEqual(status, 503)
        }
    }

    func testSuccessfulMetadataFetchesReturnMessagesInOrder() async throws {
        let items = try await listInbox("success")
        XCTAssertEqual(items.map(\.id), ["first", "second"])
        XCTAssertEqual(items.map(\.subject), ["Test message", "Test message"])
        XCTAssertEqual(items.map(\.address), ["ana@example.org", "ana@example.org"])
    }

    func testEmptyInboxRemainsASuccess() async throws {
        let items = try await listInbox("empty")
        XCTAssertTrue(items.isEmpty)
    }
}

/// Stateless fixtures scoped to each test's session; no Gmail requests or credentials.
private final class InboxURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.host == "gmail.googleapis.com" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let scenario = request.value(forHTTPHeaderField: "Authorization")
        let status: Int
        let body: String
        if url.path == "/gmail/v1/users/me/messages" {
            status = 200
            body = scenario == "Bearer empty" ? #"{"messages":[]}"# :
                #"{"messages":[{"id":"first"},{"id":"second"}]}"#
        } else {
            if scenario == "Bearer offline" {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            if scenario == "Bearer unauthorized" { status = 401 }
            else if scenario == "Bearer unavailable" || (scenario == "Bearer partial" && url.lastPathComponent == "second") { status = 503 }
            else { status = 200 }
            body = #"{"payload":{"headers":[{"name":"From","value":"Ana <ana@example.org>"},{"name":"Subject","value":"Test message"}]}}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
