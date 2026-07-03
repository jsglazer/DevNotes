import DevNotesCore
import Foundation

/// The source of truth: one Markdown (`.md`) file per note. Implements the Core `NoteRepository`
/// boundary over a directory (the app's iCloud ubiquity container in production, or any local
/// directory in tests/previews). Conflict capture uses `NSFileVersion`.
///
/// This is an OS-service adapter, deliberately the thinnest possible shell: it does file I/O and
/// nothing else. It holds **no CloudKit types** — sync is a separate service — so the "no DB
/// fetch/CloudKit in views" boundary is trivially upheld, and note content only ever originates
/// here (never in a derived cache).
public actor FileNoteStore: NoteRepository {
    private let directory: URL
    // Each access resolves the process-wide `FileManager.default` inside the actor's isolation,
    // so no non-Sendable instance ever crosses an isolation boundary.
    private var fileManager: FileManager { .default }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Resolves the iCloud ubiquity container's Documents directory, falling back to a local
    /// Application Support directory when iCloud is unavailable (offline-first).
    public static func makeDefault() -> FileNoteStore {
        let fileManager = FileManager.default
        let directory: URL
        if let ubiquity = fileManager.url(forUbiquityContainerIdentifier: nil) {
            directory = ubiquity.appendingPathComponent("Documents", isDirectory: true)
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            directory = support.appendingPathComponent("DevNotes", isDirectory: true)
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return FileNoteStore(directory: directory)
    }

    private func url(for id: NoteID) -> URL {
        directory.appendingPathComponent(id.rawValue)
    }

    public func summaries() async throws -> [NoteSummary] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        var summaries: [NoteSummary] = []
        for fileURL in contents where fileURL.pathExtension == "md" {
            guard let body = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let modified = (try? fileURL.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            let note = Note(
                id: NoteID(fileURL.lastPathComponent),
                body: body,
                createdAt: modified,
                modifiedAt: modified
            )
            summaries.append(NoteSummary(note))
        }
        return NoteSummary.sortedByModified(summaries)
    }

    public func load(_ id: NoteID) async throws -> Note {
        let fileURL = url(for: id)
        guard let body = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw RepositoryError.notFound(id)
        }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        let values = try? fileURL.resourceValues(forKeys: keys)
        return Note(
            id: id,
            body: body,
            createdAt: values?.creationDate ?? .distantPast,
            modifiedAt: values?.contentModificationDate ?? .distantPast
        )
    }

    public func save(_ note: Note) async throws {
        let fileURL = url(for: note.id)
        try note.body.data(using: .utf8)?.write(to: fileURL, options: [.atomic])
    }

    /// Deletes a note by moving its file to the system Trash (recoverable) rather than erasing it.
    /// Falls back to a hard remove only if the platform has no Trash (e.g. a sandbox without the
    /// user-selected-files entitlement), so a delete always succeeds.
    public func delete(_ id: NoteID) async throws {
        let fileURL = url(for: id)
        guard fileManager.fileExists(atPath: fileURL.path) else { throw RepositoryError.notFound(id) }
        #if os(macOS)
        do {
            try fileManager.trashItem(at: fileURL, resultingItemURL: nil)
        } catch {
            try fileManager.removeItem(at: fileURL)
        }
        #else
        try fileManager.removeItem(at: fileURL)
        #endif
    }

    // MARK: - Conflict capture

    /// Captures the pre-conflict versions iCloud recorded for a note, so they can be surfaced
    /// to the merge UI rather than silently discarded. Returns `nil` when there is no conflict.
    public func captureConflict(for id: NoteID) -> ConflictRecord? {
        let fileURL = url(for: id)
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL),
              let theirsVersion = versions.first,
              let currentBody = try? String(contentsOf: fileURL, encoding: .utf8),
              let theirsBody = try? String(contentsOf: theirsVersion.url, encoding: .utf8)
        else { return nil }

        let mine = NoteVersion(body: currentBody, modifiedAt: Date(), deviceName: Platform.deviceName)
        let theirs = NoteVersion(
            body: theirsBody,
            modifiedAt: theirsVersion.modificationDate ?? Date(),
            deviceName: theirsVersion.localizedNameOfSavingComputer ?? "Other device"
        )
        return ConflictRecord(id: id, base: nil, mine: mine, theirs: theirs)
    }
}
