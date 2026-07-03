import Foundation

public enum RepositoryError: Error, Equatable, Sendable {
    case notFound(NoteID)
}

/// The storage boundary. The file-backed iCloud store and the in-memory test fake both
/// implement this; **no SwiftUI view ever fetches through anything but this protocol**, and
/// no CloudKit type appears in its signatures. Injected into the shell — never a singleton.
public protocol NoteRepository: Sendable {
    /// All notes as summaries, sorted most-recently-modified first.
    func summaries() async throws -> [NoteSummary]
    func load(_ id: NoteID) async throws -> Note
    func save(_ note: Note) async throws
    func delete(_ id: NoteID) async throws
}

public enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case offline
    case failed(String)
}

/// The sync boundary. Every iCloud/CloudKit operation sits behind this protocol so the whole
/// headless suite runs against an in-memory fake; real CloudKit is exercised only in tagged
/// device/integration tests excluded from the CI gate. Initialisation is lazy and off the
/// launch path.
public protocol SyncService: Sendable {
    func status() async -> SyncStatus
    func start() async
    func stop() async
    /// Conflicts captured since the last resolution, oldest first.
    func pendingConflicts() async -> [ConflictRecord]
    /// Records the user's merged result for a conflicted note and clears it from the queue.
    func resolve(_ id: NoteID, mergedBody: String) async throws
}
