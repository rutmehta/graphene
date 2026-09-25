import XCTest
import WebKit
@testable import Graphene

/// WebKit decides server trust; Graphene only maps WebKit's certificate failures to a clear,
/// fail-closed message and leaves every other error alone.
final class CertificateErrorTests: XCTestCase {
    func testCertificateErrorsMapToTheUntrustedMessage() {
        let codes = [NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
                     NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid]
        for code in codes {
            let error = NSError(domain: NSURLErrorDomain, code: code, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://www.example.com/path")!])
            let mapped = WKWebEngine.presentable(error, host: "elsewhere.invalid") as NSError
            XCTAssertEqual(mapped.localizedDescription, "www.example.com's certificate isn't trusted, so Graphene didn't load the page.", "code \(code)")
            XCTAssertEqual(mapped.code, code)
            XCTAssertFalse(mapped.localizedDescription.contains("HSTS"))
        }
        // Without a failing URL, the host the engine was loading names the site.
        let bare = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
        XCTAssertEqual(WKWebEngine.presentable(bare, host: "www.example.com").localizedDescription,
                       "www.example.com's certificate isn't trusted, so Graphene didn't load the page.")
    }

    func testOtherErrorsKeepTheirOwnDescription() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
        XCTAssertEqual(WKWebEngine.presentable(offline, host: "www.example.com").localizedDescription, "The Internet connection appears to be offline.")
        let other = NSError(domain: "Graphene", code: NSURLErrorServerCertificateUntrusted, userInfo: [NSLocalizedDescriptionKey: "Something else"])
        XCTAssertEqual(WKWebEngine.presentable(other).localizedDescription, "Something else")
    }

    /// A TLS failure that carries the peer's trust is how WebKit reports a certificate issued for
    /// another host (www.msnbc.msn.com, live); without the trust it keeps its own description.
    func testTLSFailureWithPeerTrustIsACertificateRejection() throws {
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, try XCTUnwrap(Data(base64Encoded: Self.selfSigned)) as CFData))
        var trust: SecTrust?
        SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, "www.example.com" as CFString), &trust)
        let rejected = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed, userInfo: [
            NSURLErrorFailingURLErrorKey: URL(string: "https://www.example.com/")!, NSURLErrorFailingURLPeerTrustErrorKey: try XCTUnwrap(trust)])
        XCTAssertEqual(WKWebEngine.presentable(rejected).localizedDescription, "www.example.com's certificate isn't trusted, so Graphene didn't load the page.")
        let plain = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed, userInfo: [NSLocalizedDescriptionKey: "A TLS error caused the secure connection to fail."])
        XCTAssertEqual(WKWebEngine.presentable(plain).localizedDescription, "A TLS error caused the secure connection to fail.")
    }

    /// Opt-in (`GRAPHENE_LIVE_WEB=1`); needs the network. WebKit, not a bare
    /// `SecTrustEvaluateWithError` pre-check, decides trust: valid sites load (including one whose
    /// server omits its intermediate, which WebKit fetches), and a host whose certificate is issued
    /// for another name fails closed with the plain message.
    @MainActor func testLiveCertificatesAreDecidedByWebKit() async throws {
        guard ProcessInfo.processInfo.environment["GRAPHENE_LIVE_WEB"] == "1" else { throw XCTSkip("Opt-in live web test (GRAPHENE_LIVE_WEB=1)") }
        for site in ["https://www.apple.com", "https://incomplete-chain.badssl.com"] {
            let (engine, recorder) = try await load(site)
            XCTAssertTrue(recorder.errors.isEmpty, "\(site) reported errors: \(recorder.errors)")
            XCTAssertNotNil(recorder.finished, "\(site) finished loading")
            XCTAssertNotNil(engine.certificateSummary, "\(site) has certificate details")
        }
        // www.msnbc.msn.com serves a certificate for *.azureedge.net only (checked with openssl and
        // curl), so every browser rejects it. It must fail closed and name the host, not HSTS.
        let (_, recorder) = try await load("https://www.msnbc.msn.com")
        XCTAssertNil(recorder.finished)
        XCTAssertEqual(recorder.errors.last?.localizedDescription, "www.msnbc.msn.com's certificate isn't trusted, so Graphene didn't load the page.")
    }

    @MainActor private func load(_ site: String) async throws -> (WKWebEngine, FailureRecorder) {
        let engine = WKWebEngine()
        let recorder = FailureRecorder()
        engine.delegate = recorder
        engine.webView.frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        engine.load(URL(string: site)!)
        let deadline = Date().addingTimeInterval(45)
        try await Task.sleep(for: .milliseconds(500))
        while Date() < deadline, recorder.finished == nil, recorder.errors.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        print("LIVE \(site) -> finished:", recorder.finished?.absoluteString ?? "nil",
              "errors:", recorder.errors.map { "\(($0 as NSError).code): \($0.localizedDescription)" },
              "certificate:", engine.certificateSummary?.replacingOccurrences(of: "\n", with: " | ") ?? "nil")
        engine.webView.stopLoading()
        return (engine, recorder)
    }

    /// A self-signed DER certificate for www.example.com, only to build a `SecTrust` value.
    static let selfSigned = "MIICEjCCAXugAwIBAgIUWL0zC3TYxAZRNnT9TX1GBTRfj7IwDQYJKoZIhvcNAQELBQAwGjEYMBYGA1UEAwwPd3d3LmV4YW1wbGUuY29tMCAXDTI2MDkyNTEyNTAyOFoYDzIxMjYwOTAxMTI1MDI4WjAaMRgwFgYDVQQDDA93d3cuZXhhbXBsZS5jb20wgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBAMHAsbucfIJPqCuKLOvOC4Vv8Csg7xijXeKjPXybOP7V13MV/6StfvhKcIcH9Nm8pEqSgUQHlnxBYGj5onbdGCdYkT0rzc8vfFCnJxsV2dFClynvjPDdYyGqPIV5RPN7NGkq1alZpusRl0EKFbD4PK5DPkppvaTC3fqRZVSvz7ynAgMBAAGjUzBRMB0GA1UdDgQWBBTl690n4DQW1qqtFE5Ch1jlkmKzuzAfBgNVHSMEGDAWgBTl690n4DQW1qqtFE5Ch1jlkmKzuzAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4GBABzh0Ivagyk+hcwj8XjhN2DPySMVrt2m109wD+4/4iAY9tkc+/lF4ehp9VJAELmtgtUM1y+aUO6BM6AO2PSvu1ZFrjPsleXexywUZNdnuePvbRBnEZRCb8lojMd4soDWp6FrL6OfUZ2RJKaovSGtx691Qn/q78IKYwfzxvYxonf4"
}

@MainActor
private final class FailureRecorder: WebEngineDelegate {
    var errors: [Error] = []
    var finished: URL?
    func engineDidStartNavigation(_ engine: WebEngine, url: URL?) {}
    func engineDidCommit(_ engine: WebEngine, url: URL?) {}
    func engineDidFinish(_ engine: WebEngine, url: URL?, title: String?) { finished = url }
    func engine(_ engine: WebEngine, didFail error: Error) { if (error as NSError).code != NSURLErrorCancelled { errors.append(error) } }
    func engineDidChangeState(_ engine: WebEngine) {}
    func engine(_ engine: WebEngine, requestNewTabFor url: URL, activate: Bool) {}
    func engine(_ engine: WebEngine, didCaptureAnnotation annotation: CapturedAnnotation) {}
    func engine(_ engine: WebEngine, didCopyText text: String, url: URL?) {}
    func engine(_ engine: WebEngine, didChangePageDarkness dark: Bool) {}
}
