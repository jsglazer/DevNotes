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
    /// Return to wherever the caret last was in that note (per-note, persisted).
    case lastPosition
}

/// UserDefaults keys for the small set of persisted UI preferences. Notes themselves are never
/// stored here — only view/editor preferences.
private enum PreferenceKey {
    static let theme = "devnotes.theme"
    static let styleInput = "devnotes.styleInput"
    static let openJump = "devnotes.openJump"
    static let openOnLaunch = "devnotes.openOnLaunchID"
    static let wrapText = "devnotes.wrapText"
    static let showLineNumbers = "devnotes.showLineNumbers"
    static let spellCheck = "devnotes.spellCheck"
    static let pinned = "devnotes.pinnedIDs"
    static let dateFormat = "devnotes.dateFormat"
    static let bottomPadding = "devnotes.bottomPadding"
    static let zoom = "devnotes.zoom"
    static let highlightCurrentLine = "devnotes.highlightCurrentLine"
    static let currentLineLight = "devnotes.currentLineLight"
    static let currentLineDark = "devnotes.currentLineDark"
    static let similarHighlightColor = "devnotes.similarHighlightColor"
    static let similarColorLight = "devnotes.similarColorLight"
    static let similarColorDark = "devnotes.similarColorDark"
    static let openLinksOnLongPress = "devnotes.openLinksOnLongPress"
    static let caretPositions = "devnotes.caretPositions"
}

/// Zoom bounds and step for the editor/sidebar text scale (⌘+ / ⌘- / ⌘0).
private enum Zoom {
    static let min = 0.6
    static let max = 3.0
    static let step = 0.1
    static let normal = 1.0
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

    /// Raw file name of the note to open automatically on launch. Empty means "the note at the top
    /// of the list" (the historic behaviour); a stored ID whose file no longer exists also falls
    /// back to the top of the list, so a deleted pick never leaves the app on a blank editor.
    public var openOnLaunchID: String = "" { didSet { defaults.set(openOnLaunchID, forKey: PreferenceKey.openOnLaunch) } }
    public var wrapText = true { didSet { defaults.set(wrapText, forKey: PreferenceKey.wrapText) } }
    public var showLineNumbers = false { didSet { defaults.set(showLineNumbers, forKey: PreferenceKey.showLineNumbers) } }

    /// Continuous spell checking (red squiggles) in the editor. Defaults ON; toggled from the View
    /// menu and Settings. A basic checker only — no autocorrect/substitutions are enabled.
    public var spellCheck = true { didSet { defaults.set(spellCheck, forKey: PreferenceKey.spellCheck) } }

    /// `DateFormatter` pattern used by the Insert Date & Time action (⌃⌥D). Default produces e.g.
    /// `20260707-143022`. Any Unicode date pattern the user types in Settings is honoured verbatim.
    public var dateFormat = "yyyyMMdd-HHmmss" { didSet { defaults.set(dateFormat, forKey: PreferenceKey.dateFormat) } }

    /// Extra empty space below the last line of the editor (points), so the caret can sit clear of
    /// the window's bottom edge and the last lines are scrollable up into view. Configured in Settings.
    public var bottomPadding: Double = 120 { didSet { defaults.set(bottomPadding, forKey: PreferenceKey.bottomPadding) } }

    /// Text-zoom multiplier applied to the editor content area only (the note text). The sidebar
    /// file list and window chrome/toolbars stay at native size. Driven by ⌘+ / ⌘- / ⌘0. Persisted
    /// so the last zoom survives relaunch.
    public var zoom: Double = Zoom.normal { didSet { defaults.set(zoom, forKey: PreferenceKey.zoom) } }

    /// Whether the editor paints a background band behind the caret's line. The band colour is
    /// theme-specific (`currentLineColorLight` / `currentLineColorDark`), each a `#rrggbb(aa)` hex.
    public var highlightCurrentLine = false { didSet { defaults.set(highlightCurrentLine, forKey: PreferenceKey.highlightCurrentLine) } }
    public var currentLineColorLight = "#FFF6C2" { didSet { defaults.set(currentLineColorLight, forKey: PreferenceKey.currentLineLight) } }
    public var currentLineColorDark = "#3A3B22" { didSet { defaults.set(currentLineColorDark, forKey: PreferenceKey.currentLineDark) } }

    /// Whether the "Highlight Similar" toolbar button is active. While true, every occurrence of
    /// the currently selected text is highlighted across the open note. Session-only (like Find's
    /// `isPresented`) — it always starts off on launch.
    public var highlightSimilarActive = false
    /// Background colours painted over occurrences the "Highlight Similar" button finds — one per
    /// theme (a colour bright enough for light mode washed the text out in dark mode). Persisted as
    /// `#rrggbb` hex, same as the current-line colours.
    public var similarColorLight = "#FFE08A" { didSet { defaults.set(similarColorLight, forKey: PreferenceKey.similarColorLight) } }
    public var similarColorDark = "#6E5A1E" { didSet { defaults.set(similarColorDark, forKey: PreferenceKey.similarColorDark) } }

    /// When true (default), a long press on a URL in the note opens it in the browser (iOS — the
    /// text view is editable, so links aren't tappable any other way).
    public var openLinksOnLongPress = true { didSet { defaults.set(openLinksOnLongPress, forKey: PreferenceKey.openLinksOnLongPress) } }

    /// Per-note last caret offset (keyed by raw file name), backing the "Where I left off" On-Open
    /// jump. Recorded when switching notes and when the app resigns active.
    @ObservationIgnored private var caretPositions: [String: Int] = [:]

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

    /// Notes the user pinned to the top of the list, in the user's chosen display order (drag to
    /// re-order). Stored as raw file names. Mirrored to iCloud key-value storage so pins set on one
    /// device appear on the others.
    public private(set) var pinnedIDs: [String] = []

    /// iCloud key-value store backing the pinned list, so pins sync Mac ⇄ iPhone/iPad. Small,
    /// eventually-consistent; the on-disk `UserDefaults` copy is the local fallback when iCloud is
    /// unavailable.
    @ObservationIgnored private let kvStore = NSUbiquitousKeyValueStore.default

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
        // Pull pins that arrive from another device. The notification fires off the main thread, so
        // hop back before touching @MainActor state.
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.applyExternalPinChange() }
        }
        kvStore.synchronize()
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
        openOnLaunchID = defaults.string(forKey: PreferenceKey.openOnLaunch) ?? ""
        if defaults.object(forKey: PreferenceKey.wrapText) != nil {
            wrapText = defaults.bool(forKey: PreferenceKey.wrapText)
        }
        showLineNumbers = defaults.bool(forKey: PreferenceKey.showLineNumbers)
        // Spell check defaults ON, so only override when the user has explicitly stored a value.
        if defaults.object(forKey: PreferenceKey.spellCheck) != nil {
            spellCheck = defaults.bool(forKey: PreferenceKey.spellCheck)
        }
        if let raw = defaults.string(forKey: PreferenceKey.dateFormat), raw.isEmpty == false {
            dateFormat = raw
        }
        if defaults.object(forKey: PreferenceKey.bottomPadding) != nil {
            bottomPadding = defaults.double(forKey: PreferenceKey.bottomPadding)
        }
        if defaults.object(forKey: PreferenceKey.zoom) != nil {
            zoom = clampZoom(defaults.double(forKey: PreferenceKey.zoom))
        }
        highlightCurrentLine = defaults.bool(forKey: PreferenceKey.highlightCurrentLine)
        if let raw = defaults.string(forKey: PreferenceKey.currentLineLight), raw.isEmpty == false {
            currentLineColorLight = raw
        }
        if let raw = defaults.string(forKey: PreferenceKey.currentLineDark), raw.isEmpty == false {
            currentLineColorDark = raw
        }
        // Migration: a single similar-highlight colour stored by earlier versions seeds the
        // light-theme colour; the dark colour keeps its default until the user picks one.
        if let raw = defaults.string(forKey: PreferenceKey.similarColorLight)
            ?? defaults.string(forKey: PreferenceKey.similarHighlightColor), raw.isEmpty == false {
            similarColorLight = raw
        }
        if let raw = defaults.string(forKey: PreferenceKey.similarColorDark), raw.isEmpty == false {
            similarColorDark = raw
        }
        if defaults.object(forKey: PreferenceKey.openLinksOnLongPress) != nil {
            openLinksOnLongPress = defaults.bool(forKey: PreferenceKey.openLinksOnLongPress)
        }
        caretPositions = (defaults.dictionary(forKey: PreferenceKey.caretPositions) as? [String: Int]) ?? [:]
        // iCloud copy wins when present (it's the cross-device source of truth); otherwise fall back
        // to the local list so a first launch offline still shows the device's own pins.
        if let cloud = kvStore.array(forKey: PreferenceKey.pinned) as? [String] {
            pinnedIDs = Self.deduped(cloud)
        } else {
            pinnedIDs = Self.deduped(defaults.stringArray(forKey: PreferenceKey.pinned) ?? [])
        }
    }

    /// Force-pulls the latest cross-device pin list from iCloud and adopts it. Called when the app
    /// returns to the foreground: the live `didChangeExternallyNotification` is only delivered while
    /// the app is running, so a pin set on another device while this one was backgrounded or closed
    /// would otherwise not surface until a later relaunch. `synchronize()` re-primes the store and
    /// any freshly-pulled value is adopted here (and via the notification when it lands).
    public func refreshPinsFromCloud() {
        kvStore.synchronize()
        applyExternalPinChange()
    }

    /// Adopts a pinned list that landed from another device via iCloud, keeping the local defaults
    /// copy in step. No-op when it matches what we already show.
    private func applyExternalPinChange() {
        guard let cloud = kvStore.array(forKey: PreferenceKey.pinned) as? [String] else { return }
        let deduped = Self.deduped(cloud)
        guard deduped != pinnedIDs else { return }
        pinnedIDs = deduped
        defaults.set(deduped, forKey: PreferenceKey.pinned)
    }

    /// Removes duplicates while preserving first-seen order.
    private static func deduped(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func clampZoom(_ value: Double) -> Double {
        min(Zoom.max, max(Zoom.min, value))
    }

    /// Notes to show: search-filtered, then pinned notes hoisted to the top in the user's chosen
    /// pin order (drag-to-reorder). Unpinned notes keep the modified-date order the repository
    /// produced.
    public var visibleSummaries: [NoteSummary] {
        let filtered = SearchEngine.filter(summaries, query: searchQuery, options: searchOptions)
        let order = pinnedIndex
        let pinned = filtered
            .filter { order[$0.id.rawValue] != nil }
            .sorted { (order[$0.id.rawValue] ?? 0) < (order[$1.id.rawValue] ?? 0) }
        let rest = filtered.filter { order[$0.id.rawValue] == nil }
        return pinned + rest
    }

    /// Fast lookup of a note's position within the pinned list (nil when unpinned).
    private var pinnedIndex: [String: Int] {
        Dictionary(uniqueKeysWithValues: pinnedIDs.enumerated().map { ($1, $0) })
    }

    public func isPinned(_ id: NoteID) -> Bool { pinnedIDs.contains(id.rawValue) }

    /// Count of currently-visible pinned rows (the reorderable prefix of `visibleSummaries`).
    public var visiblePinnedCount: Int {
        let order = pinnedIndex
        return SearchEngine.filter(summaries, query: searchQuery, options: searchOptions)
            .filter { order[$0.id.rawValue] != nil }
            .count
    }

    public var styleSheet: StyleSheet {
        StyleSanitizer.sanitize(styleInput)
    }

    // MARK: - Lifecycle

    /// Fast path: only loads the file list. Does NOT touch CloudKit.
    public func bootstrap() async {
        await refresh()
        editor.style = styleSheet
        await selectInitialNote()
        // Land the caret live in the opened note (top of the pin list, at the top/bottom the
        // On-Open setting chooses) so the user can type immediately without a click.
        if selectedID != nil { editor.requestFocus() }
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

    /// On launch, open the note the user chose in Settings (`openOnLaunchID`) when it still exists,
    /// otherwise fall back to the note at the top of the list. Never overrides an already-open note.
    public func selectInitialNote() async {
        guard selectedID == nil else { return }
        if openOnLaunchID.isEmpty == false,
           summaries.contains(where: { $0.id.rawValue == openOnLaunchID }) {
            await select(NoteID(openOnLaunchID))
            return
        }
        await selectFirstIfNeeded()
    }

    /// Lazily starts sync after first paint; safe to call more than once.
    public func startSyncIfNeeded() async {
        await sync.start()
        conflicts = await sync.pendingConflicts()
    }

    public func refresh() async {
        summaries = (try? await repository.summaries()) ?? []
        // Drop pins whose files no longer exist so the list can't grow stale forever (order kept).
        let live = Set(summaries.map(\.id.rawValue))
        let pruned = pinnedIDs.filter { live.contains($0) }
        if pruned != pinnedIDs { setPinned(pruned) }
    }

    // MARK: - Selection & editing

    public func select(_ id: NoteID) async {
        // Leaving a note: remember where the caret was (for "Where I left off"), and delete the
        // file outright when the user emptied it — empty notes are never kept on disk.
        if let previous = selectedID, previous != id {
            rememberCaret(for: previous)
            await deleteIfEmpty(previous)
        }
        selectedID = id
        guard let note = try? await repository.load(id) else { return }
        // `load` (not a plain `editor.text =`) so opening a note doesn't schedule a save and
        // re-sort the list — the file's modified date must change only on a real edit.
        editor.load(text: note.body, selection: openSelection(for: id, in: note.body))
        editor.style = styleSheet
    }

    /// The selection a freshly opened note lands on: the first sidebar-search match when a query is
    /// active (so search jumps straight to the matching line), else the Settings jump preference.
    private func openSelection(for id: NoteID, in body: String) -> DevNotesCore.TextSelection {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty == false,
           let match = SearchEngine.matchRanges(body, query: query, options: searchOptions).first {
            return match
        }
        return caretForOpen(in: body, id: id)
    }

    /// Resolves the initial caret for a freshly opened note per the Settings jump preference.
    private func caretForOpen(in body: String, id: NoteID) -> DevNotesCore.TextSelection {
        let length = (body as NSString).length
        switch openJump {
        case .firstLine:
            return .caret(0)
        case .lastLine:
            return .caret(length)
        case .lastPosition:
            return .caret(min(caretPositions[id.rawValue] ?? 0, length))
        }
    }

    /// Records the current note's caret offset (called from the shell when the app resigns active,
    /// so the position survives relaunch even without a note switch).
    public func rememberCurrentCaret() {
        guard let id = selectedID else { return }
        rememberCaret(for: id)
    }

    private func rememberCaret(for id: NoteID) {
        caretPositions[id.rawValue] = editor.selection.location
        defaults.set(caretPositions, forKey: PreferenceKey.caretPositions)
    }

    /// Deletes `id` from disk when the editor left it empty (whitespace-only). Notes emptied by the
    /// user are removed rather than saved as empty files.
    private func deleteIfEmpty(_ id: NoteID) async {
        guard editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              summaries.contains(where: { $0.id == id }) else { return }
        try? await repository.delete(id)
        caretPositions[id.rawValue] = nil
        defaults.set(caretPositions, forKey: PreferenceKey.caretPositions)
        if pinnedIDs.contains(id.rawValue) {
            setPinned(pinnedIDs.filter { $0 != id.rawValue })
        }
        await refresh()
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
        case .insertDateTime: insertDateTime()
        }
        return true
    }

    /// Inserts the current date/time at the caret, formatted with the user's `dateFormat`.
    public func insertDateTime() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        editor.insert(formatter.string(from: Date()))
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
            setPinned(pinnedIDs.filter { $0 != id.rawValue })
        }
        await refresh()
    }

    // MARK: - Pinning

    public func togglePin(_ id: NoteID) {
        let raw = id.rawValue
        if pinnedIDs.contains(raw) {
            setPinned(pinnedIDs.filter { $0 != raw })
        } else {
            // New pins land at the end of the pinned group; the user drags to re-order.
            setPinned(pinnedIDs + [raw])
        }
    }

    /// Re-orders the pinned rows from a drag in the sidebar. `source`/`destination` are offsets into
    /// the visible list, whose reorderable prefix is the currently-visible pinned rows; moves that
    /// stray outside that prefix are ignored so a pinned note can't be dragged into the unpinned
    /// group (or vice-versa).
    public func movePinned(from source: IndexSet, to destination: Int) {
        let pinnedCount = visiblePinnedCount
        guard source.allSatisfy({ $0 < pinnedCount }), destination <= pinnedCount else { return }
        var visibleOrder = Array(visibleSummaries.prefix(pinnedCount)).map(\.id.rawValue)
        visibleOrder.move(fromOffsets: source, toOffset: destination)
        // Preserve any pinned IDs hidden by the current search filter, appended after the visible ones.
        let visibleSet = Set(visibleOrder)
        let hidden = pinnedIDs.filter { visibleSet.contains($0) == false }
        setPinned(visibleOrder + hidden)
    }

    private func setPinned(_ ids: [String]) {
        let ordered = Self.deduped(ids)
        pinnedIDs = ordered
        defaults.set(ordered, forKey: PreferenceKey.pinned)
        // Mirror to iCloud so the other devices pick the change up.
        kvStore.set(ordered, forKey: PreferenceKey.pinned)
        kvStore.synchronize()
    }

    // MARK: - Zoom

    public func zoomIn() { zoom = clampZoom(rounded2(zoom + Zoom.step)) }
    public func zoomOut() { zoom = clampZoom(rounded2(zoom - Zoom.step)) }
    public func zoomReset() { zoom = Zoom.normal }

    /// Rounds to two decimals so a run of ⌘+/⌘- keeps clean 0.1 steps (no float drift like 1.2000001).
    private func rounded2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    // MARK: - Current-line highlight

    /// The current-line band colour resolved for `scheme`, or nil when the highlight is off or the
    /// stored hex can't be parsed. Passed to the editor surface, which paints the band natively.
    public func currentLineColor(for scheme: ColorScheme) -> PlatformColor? {
        guard highlightCurrentLine else { return nil }
        let hex = scheme == .dark ? currentLineColorDark : currentLineColorLight
        return PlatformColor(hex: hex)
    }

    // MARK: - Highlight Similar

    public func toggleHighlightSimilar() {
        highlightSimilarActive.toggle()
    }

    /// Every occurrence of the current selection's text in the open note, or empty when the
    /// highlight is off or the selection is empty/blank. Recomputed live as the selection changes
    /// while the highlight is active, so moving the caret to a new word updates what's painted.
    public var similarMatches: [DevNotesCore.TextSelection] {
        guard highlightSimilarActive, editor.selection.isCaret == false else { return [] }
        let ns = editor.text as NSString
        guard editor.selection.end <= ns.length else { return [] }
        let selected = ns.substring(with: NSRange(location: editor.selection.location, length: editor.selection.length))
        guard selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return [] }
        return SearchEngine.matchRanges(editor.text, query: selected, options: SearchOptions(caseSensitive: false))
    }

    /// The "Highlight Similar" background colour for the active theme, or nil when the highlight
    /// is off.
    public func similarHighlightColor(for scheme: ColorScheme) -> PlatformColor? {
        guard highlightSimilarActive else { return nil }
        return PlatformColor(hex: scheme == .dark ? similarColorDark : similarColorLight)
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
        // Never write an empty file: a note the user emptied is deleted from disk instead. The
        // selection is kept — typing again simply recreates the file on the next save.
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? await repository.delete(id)
            if pinnedIDs.contains(id.rawValue) {
                setPinned(pinnedIDs.filter { $0 != id.rawValue })
            }
            if body == editor.text { hasUnsavedEdits = false }
            await refresh()
            return
        }
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

    // MARK: - Backup

    /// The suggested file name for a backup zip: `DevNotes-Backup-<DTG>.zip` (date-time group).
    public var backupFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "DevNotes-Backup-\(formatter.string(from: Date()))"
    }

    /// Zips the whole notes directory and returns the archive's bytes, or nil when there is no
    /// on-disk directory (in-memory repository) or the coordination fails. Uses the
    /// `NSFileCoordinator` `.forUploading` read, which materialises a directory as a zip without
    /// any third-party archiver.
    public func createBackupData() -> Data? {
        guard let directory = watchDirectory else { return nil }
        var data: Data?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: directory,
            options: .forUploading,
            error: &coordinationError
        ) { zippedURL in
            data = try? Data(contentsOf: zippedURL)
        }
        return data
    }

    // MARK: - Conflicts

    /// The full on-disk path for a note, or nil when there's no watched directory (tests/previews
    /// using an in-memory repository). Surfaced in the conflict-resolution header so it's clear
    /// exactly which file — and, since the notes directory is the iCloud ubiquity container in
    /// production, which sync location — is being reconciled.
    public func fullPath(for id: NoteID) -> String? {
        watchDirectory?.appendingPathComponent(id.rawValue).path
    }

    public func resolveConflict(_ id: NoteID, mergedBody: String) async {
        try? await sync.resolve(id, mergedBody: mergedBody)
        let note = Note(id: id, body: mergedBody, createdAt: Date(), modifiedAt: Date())
        try? await repository.save(note)
        conflicts = await sync.pendingConflicts()
        await refresh()
    }
}
