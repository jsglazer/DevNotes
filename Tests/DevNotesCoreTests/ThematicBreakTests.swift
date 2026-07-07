import Testing
@testable import DevNotesCore

/// Tests the single definition of "is this line a horizontal rule?" that both the syntax
/// highlighter and the editor's rule drawing depend on.
@Suite("Markdown.isThematicBreak")
struct ThematicBreakTests {
    @Test("Three or more of the same marker are a rule", arguments: ["---", "***", "___", "----", "- - -", "  ***  "])
    func recognisesRules(_ line: String) {
        #expect(Markdown.isThematicBreak(line))
    }

    @Test("Non-rules are rejected", arguments: ["--", "- item", "-", "**bold**", "-_-", "a---", "", "# heading"])
    func rejectsNonRules(_ line: String) {
        #expect(Markdown.isThematicBreak(line) == false)
    }
}
