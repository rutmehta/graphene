import XCTest
@testable import Graphene

final class GmailClientTests: XCTestCase {
    func testDecodesSupportedEntities() {
        XCTAssertEqual(GmailClient.decodeEntities("&amp;&quot;&#39;&lt;&gt;"), "&\"'<>")
        XCTAssertEqual(GmailClient.decodeEntities("Before &lt;tag&gt; &amp; after"), "Before <tag> & after")
    }

    func testDecodesEscapedEntitiesOnlyOnce() {
        XCTAssertEqual(GmailClient.decodeEntities("&amp;lt;"), "&lt;")
        XCTAssertEqual(GmailClient.decodeEntities("&amp;amp;&amp;quot;&amp;#39;&amp;gt;"), "&amp;&quot;&#39;&gt;")
        XCTAssertEqual(GmailClient.decodeEntities("&amp;amp;lt;"), "&amp;lt;")
        XCTAssertEqual(GmailClient.decodeEntities("&lt; &amp;lt; &gt; &amp;gt;"), "< &lt; > &gt;")
    }

    func testPreservesUnknownAndIncompleteEntities() {
        let snippet = "&& &unknown; &#60; &AMP; &amp &lt &; &"
        XCTAssertEqual(GmailClient.decodeEntities(snippet), snippet)
        XCTAssertEqual(GmailClient.decodeEntities(""), "")
        XCTAssertEqual(GmailClient.decodeEntities("Plain preview"), "Plain preview")
    }

    func testPreservesUnicodeAroundEntities() {
        XCTAssertEqual(GmailClient.decodeEntities("📬 café &amp;lt;你好&gt;"), "📬 café &lt;你好>")
    }
}
