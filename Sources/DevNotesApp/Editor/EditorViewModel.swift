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
        didSet { onChange?(text) }
    }

    public var selection: TextSelection
    public var style: StyleSheet

    private let engine = OutlineEngine()
    private var onChange: ((String) -> Void)?

    public init(text: String = "", selection: TextSelection = .caret(0), style: StyleSheet = StyleSheet()) {
        self.text = text
        self.selection = selection
        self.style = style
    }

    public func setOnChange(_ handler: ((String) -> Void)?) {
        onChange = handler
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
