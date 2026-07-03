import Foundation
import Testing
@testable import DevNotesCore

@Suite("ConflictQueue")
struct ConflictQueueTests {
    private func conflict(_ id: String) -> ConflictRecord {
        let version = NoteVersion(body: id, modifiedAt: .init(timeIntervalSince1970: 0), deviceName: "test")
        return ConflictRecord(id: NoteID(id), base: nil, mine: version, theirs: version)
    }

    @Test("Conflicts resolve FIFO")
    func fifoOrder() {
        var queue = ConflictQueue()
        queue.enqueue(conflict("a"))
        queue.enqueue(conflict("b"))
        #expect(queue.count == 2)
        #expect(queue.current?.id == NoteID("a"))
        #expect(queue.resolveCurrent()?.id == NoteID("a"))
        #expect(queue.current?.id == NoteID("b"))
    }

    @Test("Re-queuing the same note updates in place, does not duplicate")
    func deduplicates() {
        var queue = ConflictQueue([conflict("a"), conflict("b")])
        var updated = conflict("a")
        updated.mine = NoteVersion(body: "changed", modifiedAt: .init(timeIntervalSince1970: 5), deviceName: "mac")
        queue.enqueue(updated)
        #expect(queue.count == 2)
        #expect(queue.current?.mine.body == "changed")
    }

    @Test("Resolving a specific id removes it")
    func resolveById() {
        var queue = ConflictQueue([conflict("a"), conflict("b")])
        let removed = queue.resolve(NoteID("a"))
        let removedAgain = queue.resolve(NoteID("a"))
        #expect(removed)
        #expect(removedAgain == false)
        #expect(queue.pending.map(\.id) == [NoteID("b")])
    }
}

@Suite("InMemoryNoteRepository")
struct InMemoryNoteRepositoryTests {
    private func note(_ id: String, _ body: String, modified: TimeInterval) -> Note {
        Note(
            id: NoteID(id),
            body: body,
            createdAt: .init(timeIntervalSince1970: 0),
            modifiedAt: .init(timeIntervalSince1970: modified)
        )
    }

    @Test("Summaries come back sorted most-recently-modified first")
    func summariesSorted() async throws {
        let repo = InMemoryNoteRepository(notes: [
            note("old", "old", modified: 1),
            note("new", "new", modified: 3),
            note("mid", "mid", modified: 2)
        ])
        let summaries = try await repo.summaries()
        #expect(summaries.map(\.id) == [NoteID("new"), NoteID("mid"), NoteID("old")])
    }

    @Test("Save then load round-trips")
    func saveLoad() async throws {
        let repo = InMemoryNoteRepository()
        let saved = note("n1", "# Title\nbody", modified: 5)
        try await repo.save(saved)
        let loaded = try await repo.load(NoteID("n1"))
        #expect(loaded == saved)
        #expect(loaded.title == "Title")
    }

    @Test("Loading a missing note throws notFound")
    func loadMissing() async {
        let repo = InMemoryNoteRepository()
        await #expect(throws: RepositoryError.notFound(NoteID("ghost"))) {
            try await repo.load(NoteID("ghost"))
        }
    }

    @Test("Injected conflicts surface and clear on resolve")
    func conflictLifecycle() async throws {
        let repo = InMemoryNoteRepository(notes: [note("n1", "mine", modified: 5)])
        let version = NoteVersion(body: "x", modifiedAt: .init(timeIntervalSince1970: 5), deviceName: "mac")
        await repo.injectConflict(ConflictRecord(id: NoteID("n1"), base: nil, mine: version, theirs: version))
        let pending = await repo.pendingConflicts()
        #expect(pending.map(\.id) == [NoteID("n1")])

        try await repo.resolve(NoteID("n1"), mergedBody: "merged")
        let remaining = await repo.pendingConflicts()
        #expect(remaining.isEmpty)
        let loaded = try await repo.load(NoteID("n1"))
        #expect(loaded.body == "merged")
    }

    @Test("Sync status transitions through start and stop")
    func syncStatus() async {
        let repo = InMemoryNoteRepository()
        #expect(await repo.status() == .idle)
        await repo.start()
        #expect(await repo.status() == .syncing)
        await repo.stop()
        #expect(await repo.status() == .idle)
    }
}
