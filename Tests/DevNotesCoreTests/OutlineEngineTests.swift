import Testing
@testable import DevNotesCore

/// Deterministic tests for the outline manipulation module: bullet insertions, indent/outdent
/// levels, and line moves on mock markdown text, verifying BOTH final text and selection ranges.
@Suite("OutlineEngine")
struct OutlineEngineTests {
    let engine = OutlineEngine()

    // MARK: Bullet

    @Test("Bullet added to a caret line, caret follows the inserted marker")
    func bulletAddCaret() {
        let result = engine.toggleBullet(text: "hello", selection: .caret(0))
        #expect(result.text == "- hello")
        #expect(result.selection == .caret(2))
    }

    @Test("Bullet toggled off removes the marker and pulls the caret back")
    func bulletRemoveCaret() {
        let result = engine.toggleBullet(text: "- hello", selection: .caret(2))
        #expect(result.text == "hello")
        #expect(result.selection == .caret(0))
    }

    @Test("Bullet across a two-line selection bullets both and covers the new lines")
    func bulletAddRange() {
        let result = engine.toggleBullet(text: "a\nb", selection: TextSelection(location: 0, length: 3))
        #expect(result.text == "- a\n- b")
        #expect(result.selection == TextSelection(location: 0, length: 7))
    }

    @Test("Bullet is a round-trip")
    func bulletRoundTrip() {
        let on = engine.toggleBullet(text: "a\nb", selection: TextSelection(location: 0, length: 3))
        let off = engine.toggleBullet(text: on.text, selection: on.selection)
        #expect(off.text == "a\nb")
    }

    // MARK: Number

    @Test("Numbering a selection assigns sequential markers")
    func numberAddRange() {
        let result = engine.toggleNumber(text: "a\nb", selection: TextSelection(location: 0, length: 3))
        #expect(result.text == "1. a\n2. b")
        #expect(result.selection == TextSelection(location: 0, length: 9))
    }

    @Test("A bulleted line converts cleanly to numbered")
    func numberConvertsBullet() {
        let result = engine.toggleNumber(text: "- a\n- b", selection: TextSelection(location: 0, length: 7))
        #expect(result.text == "1. a\n2. b")
    }

    @Test("Numbering toggles off")
    func numberRemove() {
        let result = engine.toggleNumber(text: "1. a\n2. b", selection: TextSelection(location: 0, length: 9))
        #expect(result.text == "a\nb")
    }

    // MARK: Indent / outdent

    @Test("Indent a caret line inserts a tab and shifts the caret")
    func indentCaret() {
        let result = engine.indent(text: "abc", selection: .caret(1))
        #expect(result.text == "\tabc")
        #expect(result.selection == .caret(2))
    }

    @Test("Range indent skips empty lines")
    func indentRangeSkipsEmpty() {
        let result = engine.indent(text: "a\n\nb", selection: TextSelection(location: 0, length: 4))
        #expect(result.text == "\ta\n\n\tb")
        #expect(result.selection == TextSelection(location: 0, length: 6))
    }

    @Test("Outdent removes a leading tab")
    func outdentTab() {
        let result = engine.outdent(text: "\tabc", selection: .caret(3))
        #expect(result.text == "abc")
        #expect(result.selection == .caret(2))
    }

    @Test("Outdent removes up to indentWidth leading spaces")
    func outdentSpaces() {
        let result = engine.outdent(text: "      abc", selection: .caret(6))
        #expect(result.text == "  abc")
    }

    @Test("Indent then outdent is a round-trip")
    func indentOutdentRoundTrip() {
        let indented = engine.indent(text: "abc", selection: .caret(0))
        let outdented = engine.outdent(text: indented.text, selection: indented.selection)
        #expect(outdented.text == "abc")
    }

    // MARK: Move lines

    @Test("Move line up swaps with the line above and carries the caret")
    func moveUp() {
        let result = engine.moveLineUp(text: "a\nb\nc", selection: .caret(2))
        #expect(result.text == "b\na\nc")
        #expect(result.selection == .caret(0))
    }

    @Test("Move line down swaps with the line below and carries the caret")
    func moveDown() {
        let result = engine.moveLineDown(text: "a\nb\nc", selection: .caret(0))
        #expect(result.text == "b\na\nc")
        #expect(result.selection == .caret(2))
    }

    @Test("Move up at the top is a no-op")
    func moveUpTopNoOp() {
        let result = engine.moveLineUp(text: "a\nb", selection: .caret(0))
        #expect(result.text == "a\nb")
        #expect(result.selection == .caret(0))
    }

    @Test("Move down at the bottom is a no-op")
    func moveDownBottomNoOp() {
        let result = engine.moveLineDown(text: "a\nb", selection: .caret(2))
        #expect(result.text == "a\nb")
    }

    // MARK: Headings

    @Test("Setting a heading level adds the marker")
    func headingAdd() {
        let result = engine.setHeading(level: 2, text: "Title", selection: .caret(0))
        #expect(result.text == "## Title")
    }

    @Test("Changing heading level replaces the existing marker")
    func headingReplace() {
        let result = engine.setHeading(level: 1, text: "### Title", selection: .caret(4))
        #expect(result.text == "# Title")
    }

    @Test("Heading level 0 clears the marker")
    func headingClear() {
        let result = engine.setHeading(level: 0, text: "## Title", selection: .caret(0))
        #expect(result.text == "Title")
    }

    // MARK: Enter continuation

    @Test("Enter on a bullet item continues the bullet")
    func enterContinuesBullet() {
        let result = engine.insertNewline(text: "- item", selection: .caret(6))
        #expect(result.text == "- item\n- ")
        #expect(result.selection == .caret(9))
    }

    @Test("Enter on a numbered item increments the number")
    func enterContinuesNumber() {
        let result = engine.insertNewline(text: "1. a", selection: .caret(4))
        #expect(result.text == "1. a\n2. ")
        #expect(result.selection == .caret(8))
    }

    @Test("Enter on an empty list item exits the list")
    func enterExitsEmptyList() {
        let result = engine.insertNewline(text: "- ", selection: .caret(2))
        #expect(result.text == "")
        #expect(result.selection == .caret(0))
    }

    @Test("Enter on a plain line inserts a plain newline")
    func enterPlainLine() {
        let result = engine.insertNewline(text: "hello", selection: .caret(5))
        #expect(result.text == "hello\n")
        #expect(result.selection == .caret(6))
    }
}
