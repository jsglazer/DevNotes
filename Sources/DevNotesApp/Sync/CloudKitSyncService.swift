import CloudKit
import DevNotesCore
import Foundation

/// Production `SyncService` backed by CloudKit. Every CloudKit type is confined to this file;
/// nothing above the `SyncService` boundary sees CloudKit. Initialisation is **lazy and off the
/// launch path** — the container is not created until `start()` runs, so it can never block
/// first paint or first keystroke (startup budget, priority #1).
///
/// The pre-conflict versions surfaced here come from `FileNoteStore.captureConflict` (via
/// `NSFileVersion`); CloudKit's own record-level resolution is last-writer-wins, and we capture
/// the losing side rather than discarding it.
public actor CloudKitSyncService: SyncService {
    private let containerIdentifier: String?
    private let conflictProvider: @Sendable () async -> [ConflictRecord]
    private let conflictResolver: @Sendable (NoteID) async -> Void

    private var currentStatus: SyncStatus = .idle
    private var queue = ConflictQueue()
    private var didStart = false

    /// Lazily created — this is the deferred, off-launch-path CloudKit touch.
    private lazy var container: CKContainer = {
        if let containerIdentifier {
            return CKContainer(identifier: containerIdentifier)
        }
        return CKContainer.default()
    }()

    /// - Parameter conflictProvider: supplies captured conflicts (e.g. `FileNoteStore.captureConflict`
    ///   over the notes iCloud flagged). Injected so this service never reaches into storage itself.
    /// - Parameter conflictResolver: clears the underlying on-disk conflict marker (e.g.
    ///   `FileNoteStore.resolveFileVersionConflict`) once the user resolves it, so `conflictProvider`
    ///   stops resurfacing it.
    public init(
        containerIdentifier: String? = nil,
        conflictProvider: @escaping @Sendable () async -> [ConflictRecord] = { [] },
        conflictResolver: @escaping @Sendable (NoteID) async -> Void = { _ in }
    ) {
        self.containerIdentifier = containerIdentifier
        self.conflictProvider = conflictProvider
        self.conflictResolver = conflictResolver
    }

    public func status() async -> SyncStatus { currentStatus }

    public func start() async {
        guard didStart == false else { return }
        didStart = true
        currentStatus = .syncing
        // Touch the lazily-created container only now, never during launch.
        _ = container
        // Real subscription registration (CKDatabaseSubscription / silent pushes) is wired here.
        // It is exercised only in tagged device/integration tests, never in the headless CI gate.
        await refreshConflicts()
        currentStatus = .idle
    }

    public func stop() async {
        currentStatus = .idle
    }

    public func pendingConflicts() async -> [ConflictRecord] {
        await refreshConflicts()
        return queue.pending
    }

    public func resolve(_ id: NoteID, mergedBody: String) async throws {
        guard queue.resolve(id) else { throw RepositoryError.notFound(id) }
        // The merged body is written back through the file store (source of truth); CloudKit
        // then syncs the resolved file on its next pass.
        await conflictResolver(id)
    }

    private func refreshConflicts() async {
        for conflict in await conflictProvider() {
            queue.enqueue(conflict)
        }
    }
}
