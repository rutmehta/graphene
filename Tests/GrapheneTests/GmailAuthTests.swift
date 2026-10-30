import XCTest
import Security
@testable import Graphene

final class GmailAuthTests: XCTestCase {
    func testRandomURLSafeThrowsWhenSecureRandomFails() {
        XCTAssertThrowsError(try GmailAuth.randomURLSafe(64) { _ in errSecAllocate }) { error in
            guard case GmailAuthError.randomGenerationFailed(let status) = error else {
                return XCTFail("Expected randomGenerationFailed, got \(error)")
            }
            XCTAssertEqual(status, errSecAllocate)
        }
    }

    func testRandomURLSafeUsesFilledBytes() throws {
        let verifier = try GmailAuth.randomURLSafe(3) { bytes in
            bytes = [0xFB, 0xFF, 0xFE]
            return errSecSuccess
        }
        XCTAssertEqual(verifier, "-__-")
    }

    func testRandomURLSafeDefaultProducesPKCEVerifier() throws {
        let verifier = try GmailAuth.randomURLSafe(64)
        // 64 bytes → 86 base64url characters, within RFC 7636's 43...128 range.
        XCTAssertEqual(verifier.count, 86)
        XCTAssertNotEqual(verifier, GmailAuth.base64URL(Data(count: 64)))
        XCTAssertNil(verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }
}
