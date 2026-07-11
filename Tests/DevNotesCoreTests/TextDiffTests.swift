import XCTest
@testable import DevNotesCore

final class TextDiffTests: XCTestCase {
    /// Applies the computed edit back to `old` and asserts it reproduces `new`.
    private func assertRoundTrip(_ old: String, _ new: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let edit = TextDiff.minimalEdit(from: old, to: new) else {
            XCTAssertEqual(old, new, "nil edit is only valid for equal strings", file: file, line: line)
            return
        }
        let applied = (old as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(applied, new, file: file, line: line)
    }

    func testEqualStringsProduceNoEdit() {
        XCTAssertNil(TextDiff.minimalEdit(from: "same", to: "same"))
        XCTAssertNil(TextDiff.minimalEdit(from: "", to: ""))
    }

    func testInsertionInMiddleIsZeroLengthRange() {
        let edit = TextDiff.minimalEdit(from: "ab", to: "a-b")
        XCTAssertEqual(edit?.range, NSRange(location: 1, length: 0))
        XCTAssertEqual(edit?.replacement, "-")
        assertRoundTrip("ab", "a-b")
    }

    func testListContinuationShapedEdit() {
        // Return at the end of a bullet: the engine appends "\n- ".
        let edit = TextDiff.minimalEdit(from: "- one", to: "- one\n- ")
        XCTAssertEqual(edit?.range, NSRange(location: 5, length: 0))
        XCTAssertEqual(edit?.replacement, "\n- ")
        assertRoundTrip("- one", "- one\n- ")
    }

    func testMarkerRemovalShapedEdit() {
        // Return on an empty bullet: the engine strips the marker.
        assertRoundTrip("- one\n- ", "- one\n")
        assertRoundTrip("1. a\n2. ", "1. a\n")
    }

    func testEditInsideRepeatedTextStaysMinimal() {
        let edit = TextDiff.minimalEdit(from: "aaaa", to: "aaaaa")
        XCTAssertEqual(edit?.range.length, 0)
        XCTAssertEqual(edit?.replacement, "a")
        assertRoundTrip("aaaa", "aaaaa")
    }

    func testBoundariesNeverSplitSurrogatePairs() {
        // 😀 (D83D DE00) → 😁 (D83D DE01) share their lead surrogate; the edit must still cover
        // whole characters.
        let edit = TextDiff.minimalEdit(from: "😀", to: "😁")
        XCTAssertEqual(edit?.range, NSRange(location: 0, length: 2))
        XCTAssertEqual(edit?.replacement, "😁")
        assertRoundTrip("😀", "😁")
        assertRoundTrip("note 😀\n", "note 😁\n")
    }

    func testFullReplacement() {
        assertRoundTrip("old", "brand new")
        assertRoundTrip("", "text")
        assertRoundTrip("text", "")
    }
}
