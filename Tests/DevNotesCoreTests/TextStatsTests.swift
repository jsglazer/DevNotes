import XCTest
@testable import DevNotesCore

final class TextStatsTests: XCTestCase {
    func testEmptyBufferIsOneLineNoWords() {
        let stats = TextStats("")
        XCTAssertEqual(stats.words, 0)
        XCTAssertEqual(stats.lines, 1)
    }

    func testCountsWordsAcrossWhitespaceRuns() {
        let stats = TextStats("  the  quick\tbrown \n fox ")
        XCTAssertEqual(stats.words, 4)
    }

    func testLineCountIsNewlinesPlusOne() {
        XCTAssertEqual(TextStats("a\nb\nc").lines, 3)
        XCTAssertEqual(TextStats("single line").lines, 1)
        XCTAssertEqual(TextStats("trailing\n").lines, 2)
    }

    func testWhitespaceOnlyBufferHasNoWords() {
        let stats = TextStats("   \n\t  \n")
        XCTAssertEqual(stats.words, 0)
        XCTAssertEqual(stats.lines, 3)
    }
}
