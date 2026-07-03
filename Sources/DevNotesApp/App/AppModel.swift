import DevNotesCore
import Foundation
import Observation
import SwiftUI

public enum AppTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The composition root and app-wide state. It owns the injected `NoteRepository` and
/// `SyncService` (no singletons) and is the ONLY place note I/O is initiated — SwiftUI views
/// bind to this and never fetch through anything else. Sync is started lazily, off the launch
/// path. Saves are the whole note, debounced (never per-keystroke).
@MainActor
@Observable
public final class AppModel {
    private let repository: NoteRepository
    private let sync: SyncService

    public private(set) var summaries: [NoteSummary] = []
    public var selectedID: NoteID?
    public var searchQuery = ""
    public var searchOptions = SearchOptions()
    public var styleInput = ""
    public var theme: AppTheme = .dark
    public private(set) var conflicts: [ConflictRecord] = []
    public let editor = EditorViewModel()

    private var saveTask: Task<Void, Never>?

    public init(repository: NoteRepository, sync: SyncService) {
        self.repository = repository
        self.sync = sync
        editor.setOnChange { [weak self] _ in self?.scheduleSave() }
    }

    /// Notes to show, filtered by the search bar. Order (modified-date) is preserved.
    public var visibleSummaries: [NoteSummary] {
        SearchEngine.filter(summaries, query: searchQuery, options: searchOptions)
    }

    public var styleSheet: StyleSheet {
        StyleSanitizer.sanitize(styleInput)
    }

    // MARK: - Lifecycle

    /// Fast path: only loads the file list. Does NOT touch CloudKit.
    public func bootstrap() async {
        await refresh()
        editor.style = styleSheet
    }

    /// Lazily starts sync after first paint; safe to call more than once.
    public func startSyncIfNeeded() async {
        await sync.start()
        conflicts = await sync.pendingConflicts()
    }

    public func refresh() async {
        summaries = (try? await repository.summaries()) ?? []
    }

    // MARK: - Selection & editing

    public func select(_ id: NoteID) async {
        selectedID = id
        guard let note = try? await repository.load(id) else { return }
        editor.text = note.body
        editor.selection = .caret(0)
        editor.style = styleSheet
    }

    public func newNote() async {
        let id = NoteID("\(UUID().uuidString).md")
        let now = Date()
        let note = Note(id: id, body: "", createdAt: now, modifiedAt: now)
        try? await repository.save(note)
        await refresh()
        await select(id)
    }

    public func deleteSelected() async {
        guard let id = selectedID else { return }
        try? await repository.delete(id)
        selectedID = nil
        editor.text = ""
        await refresh()
    }

    /// Debounced whole-note save (the sync unit is the whole note, written on pause).
    private func scheduleSave() {
        saveTask?.cancel()
        let id = selectedID
        let body = editor.text
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard Task.isCancelled == false, let self, let id else { return }
            await self.persist(id: id, body: body)
        }
    }

    private func persist(id: NoteID, body: String) async {
        let now = Date()
        let existing = try? await repository.load(id)
        let note = Note(id: id, body: body, createdAt: existing?.createdAt ?? now, modifiedAt: now)
        try? await repository.save(note)
        await refresh()
    }

    // MARK: - Conflicts

    public func resolveConflict(_ id: NoteID, mergedBody: String) async {
        try? await sync.resolve(id, mergedBody: mergedBody)
        let note = Note(id: id, body: mergedBody, createdAt: Date(), modifiedAt: Date())
        try? await repository.save(note)
        conflicts = await sync.pendingConflicts()
        await refresh()
    }
}
