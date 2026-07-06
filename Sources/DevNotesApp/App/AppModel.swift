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
    static let spellCheck = "devnotes.spellCheck"
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

    /// Directory to watch for external file changes (iCloud downloads, edits from another device).
    /// `nil` disables watching (tests/previews that pass an in-memory repository).
    @ObservationIgnored private let watchDirectory: URL?
    @ObservationIgnored private var watcher: DirectoryWatcher?

    /// When true, an `NSMetadataQuery` monitor eagerly downloads remote iCloud changes so they
    /// land much sooner than waiting for the system to materialise them (sync speed).
    @ObservationIgnored private let watchUbiquity: Bool
    @ObservationIgnored private var ubiquityMonitor: UbiquityDownloadMonitor?

    /// True while the open note has edits not yet flushed to disk. Guards the external-change
    /// reload so an incoming file event can never clobber what the user is typing.
    @ObservationIgnored private var hasUnsavedEdits = false

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

    /// Continuous spell checking (red squiggles) in the editor. Defaults ON; toggled from the View
    /// menu and Settings. A basic checker only — no autocorrect/substitutions are enabled.
    public var spellCheck = true { didSet { defaults.set(spellCheck, forKey: PreferenceKey.spellCheck) } }

    /// User-configurable keyboard shortcuts, loaded once at launch from `~/.config/devnotes/keymap.json`
    /// (seeded with the defaults on first run). The View menu, editor key handling, and the Settings
    /// shortcut list all read from this single table.
    public private(set) var keymap: Keymap = .defaults
    /// Non-fatal problems found while loading the keymap file (unknown actions, bad/duplicate
    /// chords), surfaced read-only in Settings.
    public private(set) var keymapWarnings: [String] = []

    /// Sidebar collapse state, owned here so both the ⌘B toolbar button and the View menu drive
    /// the same source of truth.
    public var columnVisibility: NavigationSplitViewVisibility = .all

    /// Notes the user pinned to the top of the list. Stored as raw file names.
    public private(set) var pinnedIDs: Set<String> = []

    public private(set) var conflicts: [ConflictRecord] = []
    public let editor = EditorViewModel()

    /// In-editor Find/Replace state (macOS). The bar binds to this; the action methods below read
    /// it plus the live editor text. `var` (though never reassigned) so `@Bindable` can form
    /// writable key paths through it for the bar's `$model.find.query` bindings.
    public var find = FindState()

    private var saveTask: Task<Void, Never>?

    public init(
        repository: NoteRepository,
        sync: SyncService,
        defaults: UserDefaults = .standard,
        watchDirectory: URL? = nil,
        watchUbiquity: Bool = false
    ) {
        self.repository = repository
        self.sync = sync
        self.defaults = defaults
        self.watchDirectory = watchDirectory
        self.watchUbiquity = watchUbiquity
        loadPreferences()
        (keymap, keymapWarnings) = KeymapStore.load()
        editor.setOnChange { [weak self] _ in
            self?.hasUnsavedEdits = true
            self?.scheduleSave()
        }
    }

    /// The open note's display title (first non-empty line, heading markers stripped), derived
    /// live from the editor text so it tracks edits. Empty when no note is open.
    public var activeTitle: String {
        guard selectedID != nil else { return "" }
        let now = Date()
        return Note(id: NoteID(""), body: editor.text, createdAt: now, modifiedAt: now).title
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
        // Spell check defaults ON, so only override when the user has explicitly stored a value.
        if defaults.object(forKey: PreferenceKey.spellCheck) != nil {
            spellCheck = defaults.bool(forKey: PreferenceKey.spellCheck)
        }
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
        startWatchingIfNeeded()
    }

    /// Begins watching the notes directory for external changes so edits landing from iCloud (or
    /// another device) surface without the user having to switch notes. Idempotent.
    private func startWatchingIfNeeded() {
        guard watcher == nil, let watchDirectory else { return }
        let box = DirectoryWatcher(url: watchDirectory) { [weak self] in
            Task { @MainActor in await self?.handleExternalChange() }
        }
        box.start()
        watcher = box

        // Eagerly pull remote iCloud edits down (metadata arrives well before the daemon would
        // download on its own); the directory watcher above then sees the file land.
        if watchUbiquity, ubiquityMonitor == nil {
            let monitor = UbiquityDownloadMonitor { [weak self] in
                Task { @MainActor in await self?.handleExternalChange() }
            }
            monitor.start()
            ubiquityMonitor = monitor
        }
    }

    /// Responds to an external change on the notes directory: refresh the list, and reload the
    /// open note from disk when it changed and the user has no unsaved edits (never clobbering
    /// in-progress typing).
    private func handleExternalChange() async {
        await refresh()
        guard hasUnsavedEdits == false, let id = selectedID,
              let note = try? await repository.load(id) else { return }
        if note.body != editor.text {
            let clamped = min(editor.selection.location, (note.body as NSString).length)
            editor.load(text: note.body, selection: .caret(clamped))
        }
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
        // `load` (not a plain `editor.text =`) so opening a note doesn't schedule a save and
        // re-sort the list — the file's modified date must change only on a real edit.
        editor.load(text: note.body, selection: caretForOpen(in: note.body))
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

    /// Extends the selection from the document start to the current caret/anchor (Shift-⌘-↑).
    public func selectToTop() {
        editor.selection = DevNotesCore.TextSelection(location: 0, length: editor.selection.end)
    }

    /// Extends the selection from the current caret/anchor to the document end (Shift-⌘-↓).
    public func selectToBottom() {
        let length = (editor.text as NSString).length
        let start = editor.selection.location
        editor.selection = DevNotesCore.TextSelection(location: start, length: max(0, length - start))
    }

    // MARK: - Keymap dispatch

    /// Runs a keymap action, returning true when it was handled (so the caller can consume the key
    /// event). Editor-local actions route through the pure `OutlineEngine` via `editor`; navigation
    /// and view toggles mutate app state. Called on the main actor from the editor's key handling.
    @discardableResult
    public func perform(_ action: KeymapAction) -> Bool {
        switch action {
        case .indent: editor.run(.indent)
        case .unindent: editor.run(.outdent)
        case .moveLineUp: editor.run(.moveLineUp)
        case .moveLineDown: editor.run(.moveLineDown)
        case .selectToTop: selectToTop()
        case .selectToBottom: selectToBottom()
        case .wrapText: wrapText.toggle()
        case .showLineNumbers: showLineNumbers.toggle()
        case .nextNote: Task { await selectNext() }
        case .previousNote: Task { await selectPrevious() }
        }
        return true
    }

    public func newNote() async {
        let id = NoteID("\(UUID().uuidString).md")
        let now = Date()
        let note = Note(id: id, body: "", createdAt: now, modifiedAt: now)
        try? await repository.save(note)
        await refresh()
        await select(id)
        // Pull keyboard focus into the (now empty) editor so the caret is live immediately.
        // Without this the "+" button keeps first-responder status and the first keystrokes only
        // beep with no visible caret — the intermittent "can't type in a new note" report.
        editor.requestFocus()
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

    /// Debounced whole-note save (the sync unit is the whole note, written on pause). 400ms:
    /// long enough to coalesce a typing burst, short enough that iCloud upload starts promptly
    /// after a pause — halved from 800ms as part of the Update06 sync-speed work.
    private func scheduleSave() {
        saveTask?.cancel()
        let id = selectedID
        let body = editor.text
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard Task.isCancelled == false, let self, let id else { return }
            await self.persist(id: id, body: body)
        }
    }

    private func persist(id: NoteID, body: String) async {
        let now = Date()
        let existing = try? await repository.load(id)
        let note = Note(id: id, body: body, createdAt: existing?.createdAt ?? now, modifiedAt: now)
        try? await repository.save(note)
        // Only clear the unsaved flag if no newer edit slipped in while we were writing.
        if body == editor.text { hasUnsavedEdits = false }
        await refresh()
    }

    // MARK: - Find & replace (macOS in-editor bar)

    /// Opens the Find bar (with the replace row when `replace` is true), seeds matches over the
    /// open note, and points the cursor at the first match at or after the caret.
    public func openFind(replace: Bool) {
        guard selectedID != nil else { return }
        find.isPresented = true
        if replace { find.showReplace = true }
        refreshFindMatches(preferredLocation: editor.selection.location)
    }

    public func closeFind() {
        find.isPresented = false
        editor.requestFocus()
    }

    /// Recomputes the match list for the current query/options over the open note.
    public func refreshFindMatches(preferredLocation: Int? = nil) {
        find.refresh(in: editor.text, preferredLocation: preferredLocation)
        selectCurrentMatch()
    }

    public func findNext() {
        guard find.matches.isEmpty == false else { return }
        find.advance(by: 1)
        selectCurrentMatch()
    }

    public func findPrevious() {
        guard find.matches.isEmpty == false else { return }
        find.advance(by: -1)
        selectCurrentMatch()
    }

    /// Replaces the current match, then advances the cursor onto the next occurrence.
    public func replaceCurrent() {
        guard find.currentIndex >= 0,
              let result = SearchEngine.replaceMatch(
                  at: find.currentIndex,
                  in: editor.text,
                  query: find.query,
                  options: find.options,
                  replacement: find.replacement
              )
        else { return }
        editor.text = result.text
        // Recompute over the rewritten text; keeping the same index lands on the following match.
        find.refresh(in: editor.text)
        find.clampIndex()
        selectCurrentMatch()
    }

    /// Replaces every match in the open note in one edit.
    public func replaceAll() {
        guard find.query.isEmpty == false else { return }
        let replaced = SearchEngine.replaceAll(
            in: editor.text,
            query: find.query,
            options: find.options,
            replacement: find.replacement
        )
        guard replaced != editor.text else { return }
        editor.text = replaced
        refreshFindMatches(preferredLocation: editor.selection.location)
    }

    /// Selects (and scrolls to) the current match in the editor without stealing focus from the
    /// find field — the editor surface honours the selection change on its next update pass.
    private func selectCurrentMatch() {
        guard let match = find.currentMatch else { return }
        editor.selection = match
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
