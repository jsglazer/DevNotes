import Testing
@testable import DevNotesCore

@Suite("OutlineCommand dispatch")
struct OutlineCommandTests {
    let engine = OutlineEngine()

    @Test("apply routes each command to the matching transform")
    func dispatch() {
        #expect(engine.apply(.toggleBullet, text: "a", selection: .caret(0)).text == "- a")
        #expect(engine.apply(.indent, text: "a", selection: .caret(0)).text == "\ta")
        #expect(engine.apply(.moveLineDown, text: "a\nb", selection: .caret(0)).text == "b\na")
        #expect(engine.apply(.insertNewline, text: "- x", selection: .caret(3)).text == "- x\n- ")
    }
}
