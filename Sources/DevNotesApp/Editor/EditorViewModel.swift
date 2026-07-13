import DevNotesCore
import Foundation
import Observation

/// UI-facing state for the open note's editor. It owns the live `text` and `selection` and runs
/// every outline command through the pure Core `OutlineEngine` — the view layer holds **no**
/// outline logic. `onChange` lets the app model debounce-persist edits.
@MainActor
@Observable
public final class EditorViewModel {
    public var text: String {
        didSet { if isLoadingContent == false { onChange?(text) } }
    }

    public var selection: TextSelection
    public var style: StyleSheet

    /// Monotonic counter the editor surface observes: each bump asks the `NSTextView` to become
    /// first responder. Bumped when a note is created/opened so the caret is live and typing lands
    /// immediately — without it a freshly created note could leave focus on the toolbar, so keys
    /// only beeped.
    public private(set) var focusRequest = 0

    private let engine = OutlineEngine()
    private var onChange: ((String) -> Void)?

    /// True only while a note is being loaded for display. Assigning `text` during a load must NOT
    /// notify `onChange` — otherwise merely *opening* a note schedules a save, which bumps the
    /// file's modified date and re-sorts the list even though the user changed nothing.
    private var isLoadingContent = false

    /// Bumped every time `load` replaces the text wholesale (opening/switching notes, an external
    /// file change landing) as opposed to an in-place edit. The editor surface uses this to tell a
    /// note switch — which must reset the `NSTextView`/`UITextView` undo stack — from a same-note,
    /// model-driven edit (outline command, find/replace) that should still register on it.
    public private(set) var loadGeneration = 0

    public init(text: String = "", selection: TextSelection = .caret(0), style: StyleSheet = StyleSheet()) {
        self.text = text
        self.selection = selection
        self.style = style
    }

    public func setOnChange(_ handler: ((String) -> Void)?) {
        onChange = handler
    }

    /// Asks the editor surface to take keyboard focus on the next update pass.
    public func requestFocus() {
        focusRequest += 1
    }

    /// Loads note content for display WITHOUT triggering `onChange`/save. Use this whenever the
    /// text is being populated from disk (opening a note, or an external file change landing) so
    /// viewing a note never marks it modified.
    public func load(text: String, selection: TextSelection) {
        isLoadingContent = true
        self.text = text
        self.selection = selection
        isLoadingContent = false
        loadGeneration += 1
    }

    /// Replaces the current selection (or inserts at the caret) with `string`, leaving the caret
    /// just after the inserted text. Routes through `text`, so it schedules a save like any edit.
    public func insert(_ string: String) {
        let ns = text as NSString
        let range = NSRange(location: selection.location, length: selection.length)
        text = ns.replacingCharacters(in: range, with: string)
        selection = .caret(selection.location + (string as NSString).length)
    }

    /// Runs a parameterless outline command (bullet, indent, move-line, Enter, …).
    public func run(_ command: OutlineCommand) {
        apply(engine.apply(command, text: text, selection: selection))
    }

    /// Sets the heading level on the current line(s).
    public func setHeading(_ level: Int) {
        apply(engine.setHeading(level: level, text: text, selection: selection))
    }

    private func apply(_ edit: TextEdit) {
        text = edit.text
        selection = edit.selection
    }
}
