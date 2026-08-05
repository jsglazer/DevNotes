import XCTest
@testable import DevNotesCore

final class BackupNamingTests: XCTestCase {
    private func summary(_ id: String, _ title: String) -> NoteSummary {
        NoteSummary(id: NoteID(id), title: title, body: title, modifiedAt: Date())
    }

    func testNamesArchivedFilesAfterTheirTitles() {
        let entries = BackupNaming.entries(for: [
            summary("\(UUID().uuidString).md", "Inbox"),
            summary("\(UUID().uuidString).md", "Release Checklist")
        ])
        XCTAssertEqual(entries.map(\.fileName), ["Inbox.md", "Release Checklist.md"])
    }

    func testKeepsTheOriginalFileNameInEachEntry() {
        let id = "\(UUID().uuidString).md"
        let entries = BackupNaming.entries(for: [summary(id, "Inbox")])
        XCTAssertEqual(entries.first?.id, id)
    }

    func testDisambiguatesNotesSharingATitle() {
        let entries = BackupNaming.entries(for: [
            summary("a.md", "Notes"),
            summary("b.md", "Notes"),
            summary("c.md", "notes")
        ])
        XCTAssertEqual(entries.map(\.fileName), ["Notes.md", "Notes 2.md", "notes 3.md"])
    }

    func testReplacesPathSeparatorsAndCollapsesWhitespace() {
        XCTAssertEqual(BackupNaming.baseName(title: "2026/08: Q3   plan", id: "x.md"), "2026-08- Q3 plan")
    }

    func testStripsLeadingDotsSoTheFileIsNotHidden() {
        XCTAssertEqual(BackupNaming.baseName(title: ".hidden", id: "x.md"), "hidden")
    }

    func testCapsVeryLongTitles() {
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(BackupNaming.baseName(title: long, id: "x.md").count, 80)
    }

    func testFallsBackToTheOnDiskNameWhenTheTitleYieldsNothing() {
        XCTAssertEqual(BackupNaming.baseName(title: "///", id: "9F1C.md"), "---")
        XCTAssertEqual(BackupNaming.baseName(title: "   ", id: "9F1C.md"), "9F1C")
    }

    func testManifestMapsEveryArchivedFileBackToItsOriginal() {
        let entries = [
            BackupNaming.Entry(id: "uuid-1.md", fileName: "Inbox.md"),
            BackupNaming.Entry(id: "uuid-2.md", fileName: "Notes.md")
        ]
        let manifest = BackupNaming.manifest(for: entries, archiveName: "DevNotes-Backup-1", created: "now")
        XCTAssertTrue(manifest.contains("Inbox.md\tuuid-1.md"))
        XCTAssertTrue(manifest.contains("Notes.md\tuuid-2.md"))
        XCTAssertTrue(manifest.contains("DevNotes-Backup-1"))
    }
}
