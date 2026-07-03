import Foundation

/// A selection or caret in a text buffer, expressed in **UTF-16 code units** so it maps
/// directly onto `NSRange` used by `NSTextView` / `UITextView` — no conversion in the shell.
///
/// A zero-length selection is a caret. This is a pure value type: it never touches a view.
public struct TextSelection: Equatable, Hashable, Sendable {
    /// Start offset in UTF-16 code units from the beginning of the buffer.
    public var location: Int
    /// Length in UTF-16 code units. Zero means a caret.
    public var length: Int

    public init(location: Int, length: Int = 0) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    /// A caret at `offset`.
    public static func caret(_ offset: Int) -> TextSelection {
        TextSelection(location: offset, length: 0)
    }

    /// The exclusive end offset (`location + length`).
    public var end: Int { location + length }

    /// Whether this selection is a caret (no selected text).
    public var isCaret: Bool { length == 0 }
}

/// The value returned by every outline transform: the new text and the new selection.
/// Returning the selection (rather than mutating a view) is what makes cursor behaviour
/// headless-testable rather than manual-QA-only.
public struct TextEdit: Equatable, Sendable {
    public var text: String
    public var selection: TextSelection

    public init(text: String, selection: TextSelection) {
        self.text = text
        self.selection = selection
    }
}
