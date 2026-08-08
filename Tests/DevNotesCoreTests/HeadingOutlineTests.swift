import Testing
@testable import DevNotesCore

@Suite("HeadingOutline")
struct HeadingOutlineTests {
    @Test("A note with no headings produces an empty outline")
    func noHeadings() {
        #expect(HeadingOutline.extract(from: "just some\nplain text").isEmpty)
    }

    @Test("Flat H1s produce sibling headings in document order")
    func flatSiblings() {
        let outline = HeadingOutline.extract(from: "# One\nbody\n# Two\nbody")
        #expect(outline.map(\.text) == ["One", "Two"])
        #expect(outline.allSatisfy { $0.children.isEmpty })
    }

    @Test("A lower-level heading nests under the preceding higher-level heading")
    func nesting() {
        let text = "# Title\n## Sub A\ntext\n## Sub B\ntext"
        let outline = HeadingOutline.extract(from: text)
        #expect(outline.map(\.text) == ["Title"])
        #expect(outline[0].children.map(\.text) == ["Sub A", "Sub B"])
    }

    @Test("A heading nests under the nearest lower level even when a level is skipped")
    func skippedLevel() {
        let text = "# Title\n### Deep\ntext"
        let outline = HeadingOutline.extract(from: text)
        #expect(outline.map(\.text) == ["Title"])
        #expect(outline[0].children.map(\.text) == ["Deep"])
        #expect(outline[0].children.map(\.level) == [3])
    }

    @Test("A heading's selection is a caret at the start of its line")
    func selectionIsCaretAtLineStart() {
        let text = "intro\n## Heading"
        let outline = HeadingOutline.extract(from: text)
        #expect(outline.map(\.selection) == [.caret(6)])
    }

    @Test("A marker with no text after it is not a heading")
    func requiresText() {
        #expect(HeadingOutline.extract(from: "###\nbody").isEmpty)
    }
}
