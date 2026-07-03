# DevNotes — Build Manifest

Ultra-fast, offline-first Markdown editor for macOS & iOS. Built to the Build-to Constraints in
`NewBuild/New-4-Code.filled.md`.

## Targeted toolchain / API versions
Recorded per the build instruction to confirm the platform APIs relied on. This is a native
Swift/Apple app — there are **no undocumented internal APIs** in play (see objection 1), so the
"confirm the internal API shape against the installed version" step maps to pinning the toolchain
and the OS APIs used:

- Swift 6.3.3 (strict concurrency, language mode v6) / Xcode 26.6 (build 17F113)
- macOS SDK 26.5, iOS SDK 26.5; deployment targets **macOS 14 / iOS 17** (TextKit 2 + Observation baseline)
- OS APIs used are all public & documented: `NSTextView`/`UITextView` (TextKit 2 via `usingTextLayoutManager:`),
  `NSFileVersion.unresolvedConflictVersionsOfItem(at:)`, `CKContainer`, `FileManager` ubiquity container.

## Files created

### `Sources/DevNotesCore` — pure domain logic (imports only Foundation; no AppKit/UIKit/SwiftUI/CloudKit, no I/O)
- `Text/TextSelection.swift` — UTF-16 selection value type + `TextEdit` result type (maps to `NSRange`).
- `Text/TextModel.swift` — line/column ↔ UTF-16 offset mapping used by the outline transforms.
- `Text/LinePrefix.swift` — deterministic parsing of indentation and list markers.
- `Outline/OutlineEngine.swift` — pure `(text, selection) -> (text, selection)`: bullet/number toggle+renumber, indent/outdent, move line up/down, heading level, Enter list-continuation.
- `Outline/OutlineCommand.swift` — the command enum + `apply(_:text:selection:)` the shell routes through.
- `Diff/LineDiff.swift` — generic LCS diff (deterministic tie-breaking).
- `Diff/DiffMergeEngine.swift` — inline (iOS) + side-by-side (macOS) + char-level highlight + 3-way merge blocks, all from one LCS.
- `Search/SearchEngine.swift` — regex + whole-word + case-sensitivity as pure `matches`/`matchRanges`/`filter`.
- `Style/StyleSanitizer.swift` — bounded style-token set; accepts only known tokens, rejects everything else.
- `Model/Note.swift` — `Note`, `NoteSummary` (derived cache projection), deterministic modified-date sort.
- `Model/Conflict.swift` — `NoteVersion`, `ConflictRecord`, `ConflictQueue` (pure FIFO offline conflict state machine).
- `Repository/NoteRepository.swift` — `NoteRepository` + `SyncService` protocols (no CloudKit in signatures).
- `Repository/InMemoryNoteRepository.swift` — in-memory fake used by the ENTIRE headless suite.

### `Sources/DevNotesApp` — OS shell (SwiftUI + TextKit 2 + CloudKit; injected, no singletons)
- `App/DevNotesApp.swift` — `@main`; composition root wiring `FileNoteStore` + lazy `CloudKitSyncService` into `AppModel`.
- `App/AppModel.swift` — app state; only place note I/O is initiated; debounced whole-note save; lazy sync start.
- `App/Platform.swift` — cross-platform font/color aliases + device name.
- `Editor/EditorViewModel.swift` — routes every edit through Core `OutlineEngine`; holds no outline logic.
- `Editor/MarkdownTextView.swift` — TextKit 2 `NSTextView`/`UITextView` representable (NOT a WebView).
- `Editor/StyleApplier.swift` — maps sanitised tokens → native attributed-string attributes (never CSS in a WebView).
- `Storage/FileNoteStore.swift` — `NoteRepository` over `.md` files (iCloud ubiquity container); `NSFileVersion` conflict capture.
- `Sync/CloudKitSyncService.swift` — `SyncService`; the ONLY file that imports CloudKit; container created lazily off the launch path.
- `Views/{ContentView,SidebarView,SearchBarView,EditorPane,EditorToolbar,MergeView,SettingsView}.swift` — UI; ⌘B collapse; side-by-side (macOS)/inline (iOS) merge; theme + bounded-CSS settings.

### `Tests`
- `DevNotesCoreTests/{OutlineEngine,OutlineCommand,DiffMergeEngine,SearchEngine,StyleSanitizer,Repository}Tests.swift` — 55 Swift Testing tests (headless gate).
- `DevNotesPerformanceTests/LaunchPerformanceTests.swift` — XCTMetric proxy for the launch/search budget.

### Build config
- `Package.swift`, `.swiftlint.yml`, `.swiftformat`.

## Verification
- `swift build` — **succeeds** (macOS).
- `swift test` — **55 unit tests in 7 suites pass; 2 XCTMetric performance tests pass.**
- No force-unwraps in committed `Sources`. Core imports only Foundation. No CloudKit reference in any `Views` file.

## Objections to Build-to Constraints
1. **The launch prompt's "undocumented Obsidian internals" bullet does not apply to this project.**
   The bullet directed confining `fileItems`/`setCollapsed`/the explorer view to a thin adapter and
   using `fileItems[path].setCollapsed`. DevNotes is a native Swift/SwiftUI macOS+iOS app — the audit
   (`New-1-Concept.md` §1) states explicitly there is "no overlap with the developer's existing Obsidian
   plugins." No Obsidian API exists in this codebase. I read this as generic pipeline boilerplate and built
   to the authoritative Swift Build-to Constraints; flagging rather than silently ignoring. **The spirit of
   the bullet was still honoured**: the one platform-specific/undocumented-ish surface here — CloudKit — is
   confined to a single adapter file (`CloudKitSyncService.swift`), so an API break is a one-file fix.
2. **XCUITest launch metric requires an Xcode app target, which SwiftPM cannot produce.** The true
   `XCTApplicationLaunchMetric` "< 1s launch-to-interactive" gate needs a signed app bundle + UI-test target.
   The Standing Convention mandates SwiftPM, so the headless suite guards a proxy (note-index build + search)
   with `XCTClockMetric`; the real launch metric belongs in the Xcode UI-test target wrapping this package.
3. **App Store shipping requires an Xcode project wrapper (entitlements/Info.plist) around this package.**
   CloudKit + iCloud ubiquity container need entitlements and signing that live in an `.xcodeproj`, not in
   `Package.swift`. Core logic + shell are complete and buildable as SwiftPM per the convention; the
   distribution wrapper is a packaging step, not a logic gap.

## Reviewer criteria — where each is satisfied (satisfied visibly in code)
- **"Zero UIKit or AppKit imports in the outline manipulation manager."** — `OutlineEngine.swift`
  (and all of `DevNotesCore`) imports only `Foundation`; verified by grep. Outline logic lives entirely
  in the pure core; the UI routes through `OutlineCommand.apply`.
- **"No direct CloudKit API calls or database fetch requests in any SwiftUI views."** — All storage/sync
  goes through the `NoteRepository`/`SyncService` protocols via `AppModel`. CloudKit is imported in exactly
  one file (`CloudKitSyncService.swift`); no `Views/*.swift` references CloudKit or performs a fetch (grep-verified).
- **"Custom CSS settings are sanitised and applied only to styling the text editor's text container."** —
  `StyleSanitizer.sanitize` accepts only the closed `StyleTokenKey` set with per-type value validation and
  rejects everything else; `StyleApplier` maps the resulting typed tokens onto the native attributed-string
  renderer's `typingAttributes`/`textStorage` — there is no WebView and no path for arbitrary CSS to execute.

## Deterministic test requirements — coverage
- **Outline module (bullet insertions, indent/outdent levels, line moves; final text + selection ranges):**
  `OutlineEngineTests` asserts both `text` and `selection` for bullet/number toggles, indent/outdent
  (tab + spaces, empty-line skip), move up/down (incl. no-op boundaries), Enter continuation, and headings.
- **Diffing engine (two conflicting versions → correct inline + side-by-side blocks):** `DiffMergeEngineTests`
  covers inline lines, side-by-side rows with char-level highlight segments, and 3-way merge classification.
