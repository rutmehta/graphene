import XCTest
@testable import Graphene

final class GmailClientTests: XCTestCase {
    func testDecodesSupportedEntities() {
        XCTAssertEqual(GmailClient.decodeEntities("&amp;&quot;&#39;&lt;&gt;"), "&\"'<>")
    }

    func testDecodesNestedEntitiesOnlyOnce() {
        XCTAssertEqual(
            GmailClient.decodeEntities("&amp;lt; &amp;gt; &amp;quot; &amp;#39; &amp;amp; &amp;amp;lt;"),
            "&lt; &gt; &quot; &#39; &amp; &amp;lt;"
        )
    }

    func testPreservesOtherTextAndUnicode() {
        XCTAssertEqual(GmailClient.decodeEntities(""), "")
        XCTAssertEqual(GmailClient.decodeEntities("Plain 👩🏽‍💻 café text"), "Plain 👩🏽‍💻 café text")
        XCTAssertEqual(
            GmailClient.decodeEntities("📬 &lt;café&gt; &amp;lt; 👩🏽‍💻 &quot;hi&quot;"),
            "📬 <café> &lt; 👩🏽‍💻 \"hi\""
        )
        XCTAssertEqual(
            GmailClient.decodeEntities("&unknown; &#60; &AMP; &amp &lt &&gt;"),
            "&unknown; &#60; &AMP; &amp &lt &>"
        )
    }
}
