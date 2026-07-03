import XCTest
@testable import DevNotesCore

/// Performance tests guarding the "launch-to-interactive < 1s" budget (priority #1).
///
/// The TRUE launch metric is `XCTApplicationLaunchMetric`, which needs an app bundle and
/// therefore lives in the Xcode UI-test target (SwiftPM cannot produce the bundle). That test is
/// documented in `BUILD-MANIFEST.md`. Here we guard the headless proxy: the work on the launch
/// path (building and sorting the note index) must stay fast and, critically, must never touch
/// CloudKit — the whole point of the derived-cache / lazy-sync design.
final class LaunchPerformanceTests: XCTestCase {
    private func makeNotes(_ count: Int) -> [Note] {
        (0 ..< count).map { index in
            Note(
                id: NoteID("note-\(index).md"),
                body: "# Note \(index)\nsome body text for note number \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
    }

    /// The launch-path work: load summaries and sort them by modified date.
    func testNoteIndexBuildIsFast() throws {
        let repository = InMemoryNoteRepository(notes: makeNotes(2000))
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = expectation(description: "summaries")
            Task {
                _ = try? await repository.summaries()
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5)
        }
    }

    /// Filtering the index (search) must stay interactive as the library grows.
    func testSearchFilterIsFast() {
        let summaries = makeNotes(2000).map(NoteSummary.init)
        measure {
            _ = SearchEngine.filter(summaries, query: "note number 1", options: SearchOptions())
        }
    }
}
