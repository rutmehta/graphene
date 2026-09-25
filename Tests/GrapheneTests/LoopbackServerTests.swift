import XCTest
@testable import Graphene

final class LoopbackServerTests: XCTestCase {
    func testOneShotListenerRejectsSecondStart() throws {
        let server = LoopbackServer()
        defer { server.stop() }
        XCTAssertGreaterThan(try server.start(), 0)
        XCTAssertThrowsError(try server.start())
    }

    func testCallbackReturnsCodeAndClosesListener() async throws {
        let server = LoopbackServer()
        let port = try server.start()
        defer { server.stop() }
        let url = URL(string: "http://127.0.0.1:\(port)/?code=wp9-test-code")!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        async let response = session.data(from: url)
        let received = await server.waitForCode(timeout: 2)
        let (_, result) = try await response
        XCTAssertEqual((result as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(received, "wp9-test-code")
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.25
        do {
            _ = try await session.data(for: request)
            XCTFail("A completed one-shot listener must not accept another connection")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cannotConnectToHost)
        }
    }

    func testTimeoutReturnsWithoutCallback() async throws {
        let server = LoopbackServer()
        _ = try server.start()
        defer { server.stop() }
        let code = await server.waitForCode(timeout: 0.05)
        XCTAssertNil(code)
    }

    func testLateTimeoutAfterSuccessfulCallbackDoesNotResumeAgain() async throws {
        weak var released: LoopbackServer?
        do {
            let server = LoopbackServer()
            released = server
            let port = try server.start()
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            async let response = session.data(from: URL(string: "http://127.0.0.1:\(port)/?code=fixture")!)
            let code = await server.waitForCode(timeout: 0.2)
            _ = try await response
            XCTAssertEqual(code, "fixture")
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(released)
    }

    func testStopAndRepeatedWaitCompleteExactlyOnce() async throws {
        let server = LoopbackServer()
        _ = try server.start()
        async let pending = server.waitForCode(timeout: 1)
        server.stop(); server.stop()
        let first = await pending
        let second = await server.waitForCode(timeout: 0.01)
        XCTAssertNil(first)
        XCTAssertNil(second)
    }
}
