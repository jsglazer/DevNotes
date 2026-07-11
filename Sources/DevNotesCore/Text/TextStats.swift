import Foundation

/// Pure word/line counts for the editor's bottom status bar. Headless and side-effect free so the
/// UI layer holds no counting logic and the behaviour is unit-testable.
public struct TextStats: Equatable, Sendable {
    /// Whitespace-separated, non-empty tokens.
    public let words: Int
    /// Logical lines — newline count + 1, matching `TextModel`'s line split (an empty buffer is a
    /// single line).
    public let lines: Int

    public init(words: Int, lines: Int) {
        self.words = words
        self.lines = lines
    }

    /// Counts `text` in one pass over the buffer.
    public init(_ text: String) {
        words = text.split(whereSeparator: { $0.isWhitespace }).count
        lines = text.components(separatedBy: "\n").count
    }
}
