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

/// Where the caret lands when a note is opened (Settings-controlled).
public enum OpenJump: String, CaseIterable, Sendable {
    case firstLine
    case lastLine
}

/// UserDefaults keys for the small set of persisted UI preferences. Notes themselves are never
/// stored here — only view/editor preferences.
private enum PreferenceKey {
    static let theme = "devnotes.theme"
    static let styleInput = "devnotes.styleInput"
    static let openJump = "devnotes.openJump"
    static let wrapText = "devnotes.wrapText"
    static let showLineNumbers = "devnotes.showLineNumbers"
    static let pinned = "devnotes.pinnedIDs"
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
    @ObservationIgnored private let defaults: UserDefaults

    public private(set) var summaries: [NoteSummary] = []
    public var selectedID: NoteID?
    public var searchQuery = ""
    public var searchOptions = SearchOptions()
    public var styleInput = "" { didSet { defaults.set(styleInput, forKey: PreferenceKey.styleInput) } }
    public var theme: AppTheme = .dark { didSet { defaults.set(theme.rawValue, forKey: PreferenceKey.theme) } }

    /// View/editor preferences surfaced in the View menu and honoured by the editor surface.
    public var openJump: OpenJump = .firstLine { didSet { defaults.set(openJump.rawValue, forKey: PreferenceKey.openJump) } }
    public var wrapText = true { didSet { defaults.set(wrapText, forKey: PreferenceKey.wrapText) } }
    public var showLineNumbers = false { didSet { defaults.set(showLineNumbers, forKey: PreferenceKey.showLineNumbers) } }

    /// Sidebar collapse state, owned here so both the ⌘B toolbar button and the View menu drive
    /// the same source of truth.
    public var columnVisibility: NavigationSplitViewVisibility = .all

    /// Notes the user pinned to the top of the list. Stored as raw file names.
    public private(set) var pinnedIDs: Set<String> = []

    public private(set) var conflicts: [ConflictRecord] = []
    public let editor = EditorViewModel()

    private var saveTask: Task<Void, Never>?

    public init(repository: NoteRepository, sync: SyncService, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.sync = sync
        self.defaults = defaults
        loadPreferences()
        editor.setOnChange { [weak self] _ in self?.scheduleSave() }
    }

    private func loadPreferences() {
        if let raw = defaults.string(forKey: PreferenceKey.theme), let value = AppTheme(rawValue: raw) {
            theme = value
        }
        styleInput = defaults.string(forKey: PreferenceKey.styleInput) ?? ""
        if let raw = defaults.string(forKey: PreferenceKey.openJump), let value = OpenJump(rawValue: raw) {
            openJump = value
        }
        if defaults.object(forKey: PreferenceKey.wrapText) != nil {
            wrapText = defaults.bool(forKey: PreferenceKey.wrapText)
        }
        showLineNumbers = defaults.bool(forKey: PreferenceKey.showLineNumbers)
        pinnedIDs = Set(defaults.stringArray(forKey: PreferenceKey.pinned) ?? [])
    }

    /// Notes to show: search-filtered, then pinned notes hoisted to the top (each group keeps the
    /// modified-date order the repository already produced).
    public var visibleSummaries: [NoteSummary] {
        let filtered = SearchEngine.filter(summaries, query: searchQuery, options: searchOptions)
        let pinned = filtered.filter { pinnedIDs.contains($0.id.rawValue) }
        let rest = filtered.filter { pinnedIDs.contains($0.id.rawValue) == false }
        return pinned + rest
    }

    public func isPinned(_ id: NoteID) -> Bool { pinnedIDs.contains(id.rawValue) }

    public var styleSheet: StyleSheet {
        StyleSanitizer.sanitize(styleInput)
    }

    // MARK: - Lifecycle

    /// Fast path: only loads the file list. Does NOT touch CloudKit.
    public func bootstrap() async {
        await refresh()
        editor.style = styleSheet
        await selectFirstIfNeeded()
    }

    /// On open, land on the note at the top of the list so the user starts editing immediately.
    public func selectFirstIfNeeded() async {
        guard selectedID == nil, let first = visibleSummaries.first else { return }
        await select(first.id)
    }

    /// Lazily starts sync after first paint; safe to call more than once.
    public func startSyncIfNeeded() async {
        await sync.start()
        conflicts = await sync.pendingConflicts()
    }

    public func refresh() async {
        summaries = (try? await repository.summaries()) ?? []
        // Drop pins whose files no longer exist so the set can't grow stale forever.
        let live = Set(summaries.map(\.id.rawValue))
        let pruned = pinnedIDs.intersection(live)
        if pruned != pinnedIDs { setPinned(pruned) }
    }

    // MARK: - Selection & editing

    public func select(_ id: NoteID) async {
        selectedID = id
        guard let note = try? await repository.load(id) else { return }
        editor.text = note.body
        editor.selection = caretForOpen(in: note.body)
        editor.style = styleSheet
    }

    /// Resolves the initial caret for a freshly opened note per the Settings jump preference.
    private func caretForOpen(in body: String) -> DevNotesCore.TextSelection {
        switch openJump {
        case .firstLine:
            return .caret(0)
        case .lastLine:
            return .caret((body as NSString).length)
        }
    }

    /// Moves selection to the note one row **up** in the visible list (Shift-⌘-↑). No-ops at the
    /// top. With nothing selected yet, lands on the first note so the shortcut always does something.
    public func selectPrevious() async {
        let list = visibleSummaries
        guard let current = selectedID,
              let index = list.firstIndex(where: { $0.id == current }) else {
            if let first = list.first { await select(first.id) }
            return
        }
        guard index > 0 else { return }
        await select(list[index - 1].id)
    }

    /// Moves selection to the note one row **down** in the visible list (Shift-⌘-↓). No-ops at the
    /// bottom. With nothing selected yet, lands on the first note.
    public func selectNext() async {
        let list = visibleSummaries
        guard let current = selectedID,
              let index = list.firstIndex(where: { $0.id == current }) else {
            if let first = list.first { await select(first.id) }
            return
        }
        guard index < list.count - 1 else { return }
        await select(list[index + 1].id)
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
        await delete(id)
    }

    /// Deletes a specific note (used by the sidebar context menu). The file store moves it to the
    /// system Trash rather than erasing it, so a mistaken delete is recoverable.
    public func delete(_ id: NoteID) async {
        try? await repository.delete(id)
        if selectedID == id {
            selectedID = nil
            editor.text = ""
        }
        if pinnedIDs.contains(id.rawValue) {
            setPinned(pinnedIDs.subtracting([id.rawValue]))
        }
        await refresh()
    }

    // MARK: - Pinning

    public func togglePin(_ id: NoteID) {
        let raw = id.rawValue
        if pinnedIDs.contains(raw) {
            setPinned(pinnedIDs.subtracting([raw]))
        } else {
            setPinned(pinnedIDs.union([raw]))
        }
    }

    private func setPinned(_ ids: Set<String>) {
        pinnedIDs = ids
        defaults.set(Array(ids), forKey: PreferenceKey.pinned)
    }

    // MARK: - Sidebar

    public func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
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
