import XCTest
@testable import Graphene

final class GmailEntityTests: XCTestCase {
    func testEscapedEntitiesDecodeOnce() {
        XCTAssertEqual(GmailClient.decodeEntities("&amp;lt;b&amp;gt;"), "&lt;b&gt;")
        XCTAssertEqual(GmailClient.decodeEntities("&amp;amp;"), "&amp;")
    }

    func testSnippetEntitiesDecode() {
        XCTAssertEqual(GmailClient.decodeEntities("Tom &amp; Jerry &lt;tj@x.com&gt; said &quot;hi&quot; &#39;ok&#39;"),
                       "Tom & Jerry <tj@x.com> said \"hi\" 'ok'")
        XCTAssertEqual(GmailClient.decodeEntities("a & b &unknown; &"), "a & b &unknown; &")
    }
}
