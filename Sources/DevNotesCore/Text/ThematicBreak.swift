import Foundation

/// Small, pure Markdown-line predicates that both the app's syntax highlighter and the editor's
/// rule-drawing share, so "what counts as a horizontal rule?" has exactly one definition.
public enum Markdown {
    /// Whether `line` is a CommonMark **thematic break** (horizontal rule): three or more matching
    /// `-`, `*`, or `_` characters, with any amount of interior/edge whitespace and nothing else.
    /// So `---`, `***`, `___`, and `- - -` all qualify, but `--`, `---text`, and a `- ` bullet do not.
    public static func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else { return false }
        let markers = trimmed.filter { $0 != " " && $0 != "\t" }
        guard markers.count >= 3 else { return false }
        return markers.allSatisfy { $0 == first }
    }
}
