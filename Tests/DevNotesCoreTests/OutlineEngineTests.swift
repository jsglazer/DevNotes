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

    @Test("Caret indent carries the bullet's nested children")
    func indentCaretCarriesChildren() {
        // Caret on the parent "- a"; "\t- b" and "\t- c" are deeper, so they move too.
        let result = engine.indent(text: "- a\n\t- b\n\t- c", selection: .caret(0))
        #expect(result.text == "\t- a\n\t\t- b\n\t\t- c")
        #expect(result.selection == .caret(1))
    }

    @Test("Caret indent stops at a sibling at the same depth")
    func indentCaretStopsAtSibling() {
        // Only the parent and its one child move; the second top-level bullet stays put.
        let result = engine.indent(text: "- a\n\t- b\n- c", selection: .caret(1))
        #expect(result.text == "\t- a\n\t\t- b\n- c")
        #expect(result.selection == .caret(2))
    }

    @Test("Caret indent stops at a blank line separating list blocks")
    func indentCaretStopsAtBlankLine() {
        let result = engine.indent(text: "- a\n\n\t- b", selection: .caret(0))
        #expect(result.text == "\t- a\n\n\t- b")
    }

    @Test("Caret indent with no children still indents just the one line")
    func indentCaretNoChildren() {
        let result = engine.indent(text: "- a\n- b", selection: .caret(0))
        #expect(result.text == "\t- a\n- b")
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

    // MARK: Move lines inside an ordered list

    @Test("Moving a numbered item up re-sequences the list markers")
    func moveUpRenumbers() {
        let result = engine.moveLineUp(text: "1. a\n2. b\n3. c", selection: .caret(5))
        #expect(result.text == "1. b\n2. a\n3. c")
        #expect(result.selection == .caret(0))
    }

    @Test("Moving a numbered item down re-sequences the list markers")
    func moveDownRenumbers() {
        let result = engine.moveLineDown(text: "1. a\n2. b\n3. c", selection: .caret(0))
        #expect(result.text == "1. b\n2. a\n3. c")
        #expect(result.selection == .caret(5))
    }

    @Test("Renumbering keeps the caret on its own text as the marker widens")
    func moveKeepsCaretAcrossWideningMarker() {
        let sourceLines = (1 ... 10).map { "\($0). item\($0)" }
        let text = sourceLines.joined(separator: "\n")
        // Caret on the "i" of "item9" — line index 8, column 3 (all lines here are ASCII).
        let line9Start = sourceLines[0 ..< 8].reduce(0) { $0 + $1.count + 1 }
        let result = engine.moveLineDown(text: text, selection: .caret(line9Start + 3))
        let lines = result.text.components(separatedBy: "\n")
        #expect(lines[8] == "9. item10")
        #expect(lines[9] == "10. item9")
        // The marker widened to "10. ", so the caret follows its text out to column 4.
        let expected = lines[0 ..< 9].reduce(0) { $0 + $1.count + 1 } + 4
        #expect(result.selection == .caret(expected))
    }

    @Test("Moving a whole-line block keeps the same lines selected after renumbering")
    func moveBlockKeepsSelection() {
        let result = engine.moveLineDown(text: "1. a\n2. b\n3. c", selection: TextSelection(location: 0, length: 9))
        #expect(result.text == "1. c\n2. a\n3. b")
        #expect(result.selection == TextSelection(location: 5, length: 9))
    }

    @Test("A nested ordered sublist renumbers independently of its parent")
    func moveRenumbersNestedIndependently() {
        let text = "1. a\n\t1. x\n\t2. y\n2. b"
        let result = engine.moveLineUp(text: text, selection: .caret(12))
        #expect(result.text == "1. a\n\t1. y\n\t2. x\n2. b")
    }

    @Test("The lazy all-ones numbering style survives a move")
    func moveLeavesLazyNumberingAlone() {
        let result = engine.moveLineDown(text: "1. a\n1. b\n1. c", selection: .caret(0))
        #expect(result.text == "1. b\n1. a\n1. c")
    }

    @Test("A list that starts at a number other than one keeps its start value")
    func moveKeepsListStartValue() {
        let result = engine.moveLineDown(text: "5. a\n6. b\n7. c", selection: .caret(0))
        #expect(result.text == "5. b\n6. a\n7. c")
    }

    @Test("Moving a list item across a blank line renumbers both lists")
    func moveAcrossBlankLineRenumbersBothLists() {
        let text = "1. a\n2. b\n\n1. x\n2. y"
        // Caret on "2. b" (line 1), moved down past the blank line.
        let result = engine.moveLineDown(text: text, selection: .caret(5))
        #expect(result.text == "1. a\n\n1. b\n2. x\n3. y")
    }

    @Test("Moving a plain line inside a list leaves the untouched neighbours alone")
    func moveNonListLineDoesNotRenumberFarLists() {
        let text = "1. a\n2. b\n\nplain\nnote"
        // Caret on "plain" (line 3) — the list two lines above must not be rewritten.
        let result = engine.moveLineDown(text: text, selection: .caret(11))
        #expect(result.text == "1. a\n2. b\n\nnote\nplain")
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
