# DevNotes

[![GitHub release](https://img.shields.io/github/v/release/jsglazer/DevNotes?logo=github)](https://github.com/jsglazer/DevNotes/releases) [![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org) [![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/jsglazer/DevNotes/blob/main/LICENSE) [![Made with Claude](https://img.shields.io/badge/Made_with-Claude-D97756?logo=anthropic)](https://claude.ai) [![Gemini Flash Antigravity](https://img.shields.io/badge/Gemini%20Flash-Antigravity-4f86f7?logo=google-gemini&logoColor=white)](https://github.com/google-gemini) [![CI](https://github.com/jsglazer/DevNotes/actions/workflows/ci.yml/badge.svg)](https://github.com/jsglazer/DevNotes/actions/workflows/ci.yml) [![CodeQL](https://github.com/jsglazer/DevNotes/actions/workflows/codeql.yml/badge.svg)](https://github.com/jsglazer/DevNotes/actions/workflows/codeql.yml) [![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/jsglazer/DevNotes/badge)](https://securityscorecards.dev/viewer/?uri=github.com/jsglazer/DevNotes)

DevNotes is an ultra-fast, lightweight, offline-first Markdown editor for macOS and iOS visually inspired by the early Drafts app. It features a sleek dark color scheme with blue highlights, a collapsible file list, regex-supported search, an in-editor find & replace bar, outline editing tools, and real-time iCloud synchronization via CloudKit with visual conflict resolution.

## Features

- **Drafts-Inspired Dark Theme:** Visual styling focuses on a clean dark mode with blue highlights to keep focus on writing.
- **Ultra-Fast Launch:** Boots to interactive state in under 1 second on Apple Silicon.
- **Collapsible Sidebar:** Toggle the note list (each row shows the note's name only, in a slightly larger bold font) using `Cmd-B` (also under the **View** menu). The list is ordered by modification date, with pinned notes hoisted to the top.
- **Opens Where You Left Off:** On launch DevNotes selects the note at the top of the (pin-first) list, gives the editor keyboard focus so you can type immediately, and places the caret at the **first** or **last** line — your choice in Settings.
- **Pin & Re-order Notes:** Right-click any note to **Pin to Top** or **Delete** it (deletes move the file to the system **Trash**, so they're recoverable). Pinned notes float above the date-sorted list and can be **dragged into any order**, and your pins **sync across devices** through iCloud key-value storage — pin on the Mac and it shows pinned on iPhone/iPad.
- **Live Markdown Syntax Coloring:** Markdown markers are colored in place as you type — heading lines take a color per level, markers and text alike (`#` red `#D8564F`, `##` orange `#E07D2C`, `###` yellow `#DAB22E`, `####`+ green `#89AC40`), list markers in blue, inline `` `code` `` in teal monospace, **bold**/*italic* delimiters highlighted, plus blockquotes and links — layered over your custom editor style without any WebView.
- **Line Numbers Everywhere:** A **line-number gutter** on both macOS and iOS. Toggle it (and **Wrap Text**) from the **View** menu on macOS or from **Settings** on iOS.
- **Auto-Continuing Lists:** Press **Return** in a bullet or numbered item and the next line continues the list automatically; pressing Return on an empty item exits the list.
- **Subtree Indenting:** Indenting a bullet with the caret on its line carries its nested children along — the whole sub-list shifts one level instead of orphaning the items beneath it.
- **Hanging List Indents:** When a bullet or numbered item wraps onto a second line, the continuation lines tuck under the item's text (past the marker) instead of falling back to the left margin, so long list items stay visually aligned.
- **Real Horizontal Rules:** A Markdown thematic break (`---`, `***`, or `___`) is drawn as an actual full-width rule line across the editor on both macOS and iOS, while the characters stay editable underneath.
- **Current-Line Highlight:** Optionally paint a background band behind the line the caret is on. Turn it on in **Settings** and pick a **separate colour for light and dark themes** with the built-in colour pickers.
- **Text Zoom:** Scale the note text and the file-list text up or down with **⌘+ / ⌘- / ⌘0** on macOS (also a **Settings** stepper, which is how you zoom on iOS). Window chrome and toolbars stay at their native size.
- **Insert Date & Time:** Press **⌃⌥D** to drop the current date and time at the caret. The format is a configurable `DateFormatter` pattern in **Settings** (default `yyyyMMdd-HHmmss`, e.g. `20260707-143022`).
- **View Menu Controls:** Toggle **Wrap Text**, the **line-number gutter**, and **Check Spelling While Typing**, and switch between **System / Light / Dark** themes.
- **Configurable Keyboard Shortcuts:** Every editor and navigation action is bound through a user-editable `~/.config/devnotes/keymap.json` (created on first launch, pre-filled with every bindable action so the file itself is the catalog). Defaults follow standard-macOS conventions — indent/outdent with **Tab / Shift-Tab**, move a line with **⌃⌥↑ / ⌃⌥↓**, jump notes with **⌥⌘↑ / ⌥⌘↓**, select to the top/bottom of a note with **⇧⌘↑ / ⇧⌘↓**, insert the date & time with **⌃⌥D**, and toggle wrap (**⇧⌘W**) and line numbers (**⇧⌘N**). **Settings → Keyboard Shortcuts** shows the full list and flags any bad edits.
- **Basic Spell Checking:** Continuous, in-line spell checking (red underlines) — on by default and toggleable from the **View** menu or **Settings**. It never rewrites your text: automatic correction, text substitutions, and grammar checking stay off so code and identifiers are left alone.
- **Follows the Caret:** The editor auto-scrolls to keep the cursor in view, so text typed at the bottom of the window is never clipped. Re-coloring never yanks the view, and a configurable **bottom padding** (Settings, default 120pt) keeps scroll-past-end room so the caret on the last line never sits against the window edge.
- **Export & Print:** From the **File** menu, export the open note as **Markdown** or **plain text**, or **Save as PDF** (rendered with your editor styling).
- **Regex Search:** Advanced search over the note list supporting regular expressions, whole-word filtering, and case-sensitivity.
- **In-Editor Find & Replace (macOS):** A Sublime-style find/replace bar over the open note — press **⌘F** to find or **⌘⌥F** to find and replace. It carries the same **regex**, **whole-word**, and **case-sensitive** toggles, walks matches with **⌘G / ⇧⌘G** (with a live "N of M" counter), highlights every match in the editor (the current one emphasized), and offers **Replace** and **Replace All** (regex mode expands `$1`-style capture-group references in the replacement).
- **Outline Editing Tools:** Built-in actions to toggle bullets and numbered lists (with continuous auto-formatting), indent and outdent lines, increment/decrement headings, and move lines up or down.
- **iPhone-Ready Editing:** A bold note-title bar above an always-visible top bar (with roomier, ~20%-larger controls), the **outline formatting tools pinned on-screen** rather than hidden behind a sheet, a dedicated key to dismiss the keyboard, and note-list/settings sheets tuned for a phone-sized layout.
- **iCloud CloudKit Sync:** Automatic background synchronization with offline storage support (degrades gracefully to local storage if iCloud is unavailable). A metadata-query monitor spots remote edits the moment iCloud learns about them and starts downloading immediately — no waiting for the system to materialize files on its own — and local edits are saved (and begin uploading) within 400ms of a typing pause.
- **Live External-Change Detection:** DevNotes watches its notes folder, so edits arriving from iCloud or another device refresh the list — and reload the open note when you have no unsaved edits — without you having to switch notes first.
- **Visual Conflict Merge:** Resolve sync conflicts using a side-by-side view on macOS and an inline view on iOS. Choosing a side clears the underlying file-version conflict on disk, so it can't resurface after a relaunch.
- **Version Indicator:** The current app version is shown in small text at the top-right of the main screen on both macOS and iOS.
- **Sanitized Custom CSS Styling:** Apply custom formatting to the editor text area via a safe, parsed set of CSS-like properties applied to the native TextKit 2 renderer.

## Architecture

 The project is structured as a Swift Package with two primary targets to enforce strict division of concerns:

1. **`DevNotesCore`:** A pure, platform-independent library containing all core domain logic. It has zero dependencies on AppKit, UIKit, SwiftUI, CloudKit, or file/network I/O, allowing for a fully deterministic and headless test suite.
   - **`Outline`:** Handles outline command applications (bullet/number toggling, indenting, moving lines, heading levels, and list continuations).
   - **`Diff` & `Merge`:** Implements Longest Common Subsequence (LCS) diffing, 3-way merge logic, and side-by-side/inline highlight generation.
   - **`Search`:** Evaluates regex, case sensitivity, and whole-word matching logic, and performs single/all match replacement (with capture-group templating) for the in-editor find & replace.
   - **`Style`:** Parses and sanitizes custom stylesheet configurations against a strict blocklist/allowlist.
   - **`Keymap`:** Defines the closed catalog of bindable actions, parses/serializes key chords, and merges a user's `keymap.json` over the built-in defaults (with duplicate/parse warnings) — all pure and headless-tested.
   - **`Model` & `Repository`:** Handles entities like `Note` and `Conflict` along with the in-memory fake repositories for testing.

2. **`DevNotesApp`:** The SwiftUI shell targets macOS and iOS, linking `DevNotesCore` and implementing native platform controls.
   - **`App` & `Storage`:** Implements `AppModel` and `FileNoteStore` for file-system storage under the iCloud ubiquity folder, wrapping `NSFileVersion` for conflict detection.
   - **`Editor`:** Builds a native TextKit 2 `NSTextView` / `UITextView` wrapper, avoiding WebViews for extreme efficiency, with a `MarkdownHighlighter` that colors syntax in place and Return routed through the pure outline engine for list continuation. On macOS an `EditorTextView` subclass resolves each key press against the loaded keymap (`DevNotesCore/Keymap`) before the field editor's defaults, so Tab-to-indent and the other bindings run through the same pure engine.
   - **`Sync`:** Encapsulates `CloudKitSyncService` (isolating CloudKit dependencies to a single file) and `UbiquityDownloadMonitor`, an `NSMetadataQuery` watcher that eagerly downloads remote iCloud changes as soon as their metadata arrives.

## Where Your Notes Live (iCloud Sync)

DevNotes stores each note as a single Markdown (`.md`) file inside its **own app-specific iCloud container** (`iCloud.com.jsglazer.DevNotes`), not in the general iCloud Drive folder. On macOS that path is:

```
~/Library/Mobile Documents/iCloud~com~jsglazer~DevNotes/Documents/
```

iCloud syncs those files between every signed-in device automatically (file-level ubiquitous sync); a metadata-query monitor accelerates that by triggering downloads of remote changes as soon as they become visible, and `CloudKitSyncService` sits on top only for conflict detection and, on device builds, push subscriptions. If iCloud is unavailable the app falls back to `~/Library/Application Support/DevNotes/` and keeps working offline, syncing when the connection returns.

**Why don't I see a `DevNotes` folder in iCloud Drive / Finder?** Two reasons, both expected:

1. The container directory is created **lazily the first time the signed app launches** while you're signed into iCloud — it won't exist before then.
2. An app's iCloud container is **hidden from the Finder iCloud Drive UI by default**. Surfacing it as a browsable folder requires declaring `NSUbiquitousContainers` with `NSUbiquitousContainerIsDocumentScopePublic = true` in the app's `Info.plist`. DevNotes doesn't do this — sync still works exactly the same; the files simply live under the app-specific Mobile Documents path above (which you can still open directly in Finder with **Go → Go to Folder…**) rather than appearing in the iCloud Drive sidebar.

## Getting Started

### Prerequisites

- Swift 6.0 / Xcode 15+ (Xcode 26.6 / Swift 6.3.3 recommended)
- macOS 14.0+ / iOS 17.0+
- XcodeGen (optional, for regenerating the Xcode project file)

### Generating the Xcode Project

An Xcode wrapper is required to build the app with iCloud entitlements and signing. You can generate or regenerate the project file using XcodeGen:

```bash
xcodegen generate
```

This reads the `project.yml` configuration and creates `DevNotes.xcodeproj`.

### Building and Running

You can build the project from the terminal via Swift Package Manager:

```bash
# Build the package
swift build

# Run unit and performance tests
swift test
```

For full App Store packaging, signing, and iCloud capability support, open `DevNotes.xcodeproj` in Xcode, select your Apple Developer Team ID in the signing settings, and build the target.

## Editor Style: How To Use It

The **Editor Style** box in Settings lets you restyle the writing area without touching a config file — and without the risk of real CSS. You write one `token: value` declaration per line (semicolons also work as separators). Only the tokens in the catalog below are honoured; **anything else is quietly ignored and never executed** — this is a sanitized token set applied to the native TextKit 2 renderer, not a stylesheet run in a WebView.

**How to apply a style:**

1. Open **DevNotes → Settings** (`Cmd-,`) and select the **Editor Style** tab. (Settings is organized into three tabs — **General**, **Keyboard Shortcuts**, and **Editor Style** — so each pane fits without scrolling or clipping.)
2. Type or paste declarations into the outlined **Editor Style** box, or click **Insert Example** to drop in a starter stylesheet.
3. Changes apply live as you type. Any line DevNotes couldn't use is listed in orange with the reason (e.g. `unknown token`, `invalid value`), so you always know what was skipped.

### Examples

**Minimal — bump the size and soften the text color:**

```css
font-size: 16
text-color: #d0d0d0
```

**Comfortable reading — larger type with generous spacing:**

```css
font-family: "SF Pro Text"
font-size: 17
line-spacing: 6
paragraph-spacing: 14
heading-color: #3b82f6
```

**Dracula-inspired dark theme:**

```css
font-family: "Courier New"
font-size: 15px
font-weight: regular
text-color: #f8f8f2
background-color: #282a36
accent-color: #bd93f9
line-spacing: 6
paragraph-spacing: 14
heading1-size: 26
heading2-size: 22
heading3-size: 18
heading-color: #ff79c6
```

**High-contrast large print:**

```css
font-size: 22
font-weight: semibold
text-color: #ffffff
heading-color: #ffd166
line-spacing: 8
```

## CSS Customization Catalog

DevNotes supports personalizing the text area rendering using a sanitized CSS-like syntax. These settings are applied directly to the native TextKit 2 text container (not a WebView) for optimal performance and safety. Any properties or syntax not matching the exact keys below will be safely rejected by the sanitization engine.

| CSS Property | Supported Values | Description | Example |
|---|---|---|---|
| `font-family` | System font names | Sets the typeface family used in the text area. | `font-family: Menlo` |
| `font-size` | Numeric values with units (`px`, `pt`, `em`, `rem`) | Sets the baseline font size (between 1 and 400). | `font-size: 14pt` |
| `font-weight` | Name (`thin`, `light`, `regular`, `medium`, `semibold`, `bold`, `heavy`, `black`) or Number (`1`–`1000`) | Configures the thickness of the typeface. | `font-weight: semibold` |
| `text-color` | Hexadecimal color code (`#rgb`, `#rrggbb`, `#rrggbbaa`) | Configures the default text color. | `text-color: #e0e0e0` |
| `background-color` | Hexadecimal color code (`#rgb`, `#rrggbb`, `#rrggbbaa`) | Configures the text area background. | `background-color: #121212` |
| `accent-color` | Hexadecimal color code (`#rgb`, `#rrggbb`, `#rrggbbaa`) | Configures UI accent coloring. | `accent-color: #007aff` |
| `line-spacing` | Positive numeric values | Configures space between lines of text. | `line-spacing: 4` |
| `paragraph-spacing` | Positive numeric values | Configures space between paragraphs. | `paragraph-spacing: 12` |
| `heading1-size` | Positive numeric values | Font size for Level 1 headings (`#`). | `heading1-size: 24` |
| `heading2-size` | Positive numeric values | Font size for Level 2 headings (`##`). | `heading2-size: 20` |
| `heading3-size` | Positive numeric values | Font size for Level 3 headings (`###`). | `heading3-size: 18` |
| `heading-color` | Hexadecimal color code (`#rgb`, `#rrggbb`, `#rrggbbaa`) | Accepted for compatibility, but currently superseded in the editor by the fixed per-level heading colors (see Features). | `heading-color: #3b82f6` |

### CSS Example

Here is a full styling stylesheet configuration you can paste into the DevNotes settings pane:

```css
font-family: "Courier New";
font-size: 15px;
font-weight: regular;
text-color: #f8f8f2;
background-color: #282a36;
accent-color: #bd93f9;
line-spacing: 6;
paragraph-spacing: 14;
heading1-size: 26;
heading2-size: 22;
heading3-size: 18;
heading-color: #ff79c6;
```
