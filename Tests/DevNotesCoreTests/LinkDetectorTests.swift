import DevNotesCore
import XCTest

final class LinkDetectorTests: XCTestCase {
    func testFindsBareURLUnderOffset() {
        let text = "see https://example.com/docs for details"
        XCTAssertEqual(
            LinkDetector.url(in: text, at: 10)?.absoluteString,
            "https://example.com/docs"
        )
    }

    func testFindsMarkdownLinkAddress() {
        let text = "read the [docs](https://example.com/docs) first"
        // Offset inside the address part of `[text](url)`.
        let offset = (text as NSString).range(of: "example.com").location
        XCTAssertEqual(
            LinkDetector.url(in: text, at: offset)?.absoluteString,
            "https://example.com/docs"
        )
    }

    func testReturnsNilOutsideAnyLink() {
        let text = "see https://example.com for details"
        XCTAssertNil(LinkDetector.url(in: text, at: 1))
        XCTAssertNil(LinkDetector.url(in: text, at: (text as NSString).length))
    }

    func testHandlesEmptyAndOutOfRangeOffsets() {
        XCTAssertNil(LinkDetector.url(in: "", at: 0))
        XCTAssertNil(LinkDetector.url(in: "https://example.com", at: -1))
        XCTAssertNil(LinkDetector.url(in: "https://example.com", at: 500))
    }
}
