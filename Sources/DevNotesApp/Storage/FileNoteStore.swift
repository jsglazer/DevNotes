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
    /// The notes directory (iCloud ubiquity container in production, a local dir in tests). Exposed
    /// as `nonisolated` so the composition root can hand it to a `DirectoryWatcher` without awaiting
    /// the actor; it is an immutable `Sendable` value, so this is safe.
    public nonisolated let directory: URL

    /// True when `directory` lives in the iCloud ubiquity container, so the composition root can
    /// decide whether ubiquity-specific machinery (metadata-query download triggering) applies.
    public nonisolated let isUbiquitous: Bool

    // Each access resolves the process-wide `FileManager.default` inside the actor's isolation,
    // so no non-Sendable instance ever crosses an isolation boundary.
    private var fileManager: FileManager { .default }

    /// Summaries already built for files whose modification date hasn't changed since, keyed by
    /// file name. `summaries()` runs after every debounced save and every directory event, so
    /// without this every keystroke-pause re-read the full body of *every* note in the folder.
    private var summaryCache: [String: (modified: Date, summary: NoteSummary)] = [:]

    public init(directory: URL, isUbiquitous: Bool = false) {
        self.directory = directory
        self.isUbiquitous = isUbiquitous
    }

    /// Resolves the iCloud ubiquity container's Documents directory, falling back to a local
    /// Application Support directory when iCloud is unavailable (offline-first).
    public static func makeDefault() -> FileNoteStore {
        let fileManager = FileManager.default
        let directory: URL
        let isUbiquitous: Bool
        if let ubiquity = fileManager.url(forUbiquityContainerIdentifier: nil) {
            directory = ubiquity.appendingPathComponent("Documents", isDirectory: true)
            isUbiquitous = true
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            directory = support.appendingPathComponent("DevNotes", isDirectory: true)
            isUbiquitous = false
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return FileNoteStore(directory: directory, isUbiquitous: isUbiquitous)
    }

    private func url(for id: NoteID) -> URL {
        // IDs originate from file names, but harden anyway: keeping only the last path component
        // means an ID containing separators or `..` can never address a file outside `directory`.
        directory.appendingPathComponent((id.rawValue as NSString).lastPathComponent)
    }

    public func summaries() async throws -> [NoteSummary] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        var summaries: [NoteSummary] = []
        var seen: Set<String> = []
        for fileURL in contents where fileURL.pathExtension == "md" {
            let name = fileURL.lastPathComponent
            let modified = (try? fileURL.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            seen.insert(name)
            if let cached = summaryCache[name], cached.modified == modified {
                summaries.append(cached.summary)
                continue
            }
            guard let body = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let note = Note(id: NoteID(name), body: body, createdAt: modified, modifiedAt: modified)
            let summary = NoteSummary(note)
            summaryCache[name] = (modified, summary)
            summaries.append(summary)
        }
        // Drop cache entries for files that no longer exist so the cache can't grow stale.
        summaryCache = summaryCache.filter { seen.contains($0.key) }
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

    /// Marks the on-disk file-version conflict for `id` as resolved once the user has picked a
    /// side. Without this, `NSFileVersion.unresolvedConflictVersionsOfItem` keeps reporting the
    /// same conflict on every subsequent `captureConflict` call — including after a relaunch —
    /// so the merge sheet would resurface indefinitely.
    public func resolveFileVersionConflict(for id: NoteID) {
        let fileURL = url(for: id)
        if let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) {
            for version in versions { version.isResolved = true }
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: fileURL)
    }
}
