import Foundation

/// Deterministic, in-memory implementation of `NoteRepository` and `SyncService` used by the
/// ENTIRE headless test suite. An `actor` so it is `Sendable` and free of data races; it holds
/// no clock, no filesystem, no network — callers pass in any dates, so tests are repeatable.
public actor InMemoryNoteRepository: NoteRepository, SyncService {
    private var notes: [NoteID: Note]
    private var conflicts: ConflictQueue
    private var currentStatus: SyncStatus
    /// Merged bodies recorded via `resolve`, exposed for test assertions.
    public private(set) var resolvedBodies: [NoteID: String] = [:]

    public init(notes: [Note] = [], conflicts: [ConflictRecord] = [], status: SyncStatus = .idle) {
        self.notes = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        self.conflicts = ConflictQueue(conflicts)
        self.currentStatus = status
    }

    // MARK: NoteRepository

    public func summaries() async throws -> [NoteSummary] {
        NoteSummary.sortedByModified(notes.values.map(NoteSummary.init))
    }

    public func load(_ id: NoteID) async throws -> Note {
        guard let note = notes[id] else { throw RepositoryError.notFound(id) }
        return note
    }

    public func save(_ note: Note) async throws {
        notes[note.id] = note
    }

    public func delete(_ id: NoteID) async throws {
        guard notes.removeValue(forKey: id) != nil else { throw RepositoryError.notFound(id) }
    }

    // MARK: SyncService

    public func status() async -> SyncStatus { currentStatus }
    public func start() async { currentStatus = .syncing }
    public func stop() async { currentStatus = .idle }

    public func pendingConflicts() async -> [ConflictRecord] { conflicts.pending }

    public func resolve(_ id: NoteID, mergedBody: String) async throws {
        guard conflicts.resolve(id) else { throw RepositoryError.notFound(id) }
        resolvedBodies[id] = mergedBody
        if var note = notes[id] {
            note.body = mergedBody
            notes[id] = note
        }
    }

    // MARK: Test seams

    /// Injects a conflict, as the sync engine would on detecting a divergent record.
    public func injectConflict(_ conflict: ConflictRecord) {
        conflicts.enqueue(conflict)
    }

    public func setStatus(_ status: SyncStatus) {
        currentStatus = status
    }
}
