import XCTest
@testable import Graphene

final class GmailClientTests: XCTestCase {
    func testDecodesSupportedEntities() {
        XCTAssertEqual(GmailClient.decodeEntities("&amp;&quot;&#39;&lt;&gt;"), "&\"'<>")
    }

    func testDecodesEscapedEntitiesOnlyOnce() {
        XCTAssertEqual(
            GmailClient.decodeEntities("&amp;amp; &amp;quot; &amp;#39; &amp;lt; &amp;gt;"),
            "&amp; &quot; &#39; &lt; &gt;"
        )
        XCTAssertEqual(GmailClient.decodeEntities("&amp;lt;&lt;&amp;gt;&gt;"), "&lt;<&gt;>")
        XCTAssertEqual(GmailClient.decodeEntities("&amp;lt; 😀 café"), "&lt; 😀 café")
    }

    func testPreservesPlainTextAndUnrecognizedEntities() {
        for snippet in ["", "Plain text 😀 café", "&", "&amp", "&unknown; &#60; &nbsp;"] {
            XCTAssertEqual(GmailClient.decodeEntities(snippet), snippet)
        }
    }
}
