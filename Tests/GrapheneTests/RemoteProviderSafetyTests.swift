import XCTest
@testable import Graphene

final class RemoteProviderSafetyTests: XCTestCase {
    func testUnsafeEndpointsAreRejectedBeforeBuildingAuthenticatedRequest() {
        let endpoints = [
            "http://api.example.org/v1",
            "http://localhost.example.org/v1",
            "http://127.0.0.1.example.org/v1",
            "ftp://api.example.org/v1",
            "file:///tmp/provider",
            "/v1",
            "https://user:password@api.example.org/v1",
            "https://user@api.example.org/v1",
            "https://api.example.org/v1?key=example",
            "https://api.example.org/v1#fragment"
        ]
        for kind in [ProviderKind.compatible, .anthropic] {
            for endpoint in endpoints {
                XCTAssertThrowsError(try RemoteProvider.request(kind: kind, baseURL: endpoint, model: "test-model", key: "test-key", messages: []), endpoint) { error in
                    XCTAssertTrue(error is ProviderFailure, endpoint)
                }
            }
        }
    }

    func testEmptyModelsAreRejectedForBothRemoteProviders() {
        for kind in [ProviderKind.compatible, .anthropic] {
            for model in ["", " ", "\n\t"] {
                XCTAssertThrowsError(try RemoteProvider.request(kind: kind, baseURL: "https://api.example.org/v1", model: model, key: "test-key", messages: [])) { error in
                    XCTAssertTrue(error is ProviderFailure)
                }
            }
        }
    }

    func testApprovedTransportsKeepProviderSpecificCredentialsAndPaths() throws {
        for base in ["https://api.example.org/v1", "http://localhost:11434/v1", "http://127.0.0.1:11434/v1"] {
            for kind in [ProviderKind.compatible, .anthropic] {
                let request = try RemoteProvider.request(kind: kind, baseURL: base, model: "test-model", key: "test-key", messages: [])
                let path = kind == .anthropic ? "/messages" : "/chat/completions"
                XCTAssertEqual(request.url?.absoluteString, base + path)
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
                if kind == .anthropic {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
                    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                } else {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                    XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
                }
            }
        }
        let local = try RemoteProvider.request(kind: .compatible, baseURL: "http://localhost:11434/v1", model: "local", key: "", messages: [])
        XCTAssertNil(local.value(forHTTPHeaderField: "Authorization"))
    }
}
