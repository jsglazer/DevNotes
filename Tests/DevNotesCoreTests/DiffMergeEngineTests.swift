import Testing
@testable import DevNotesCore

/// Deterministic tests for the diffing engine: two conflicting text versions must produce
/// correct highlighted inline (iOS) and side-by-side (macOS) diff blocks, from the same logic.
@Suite("DiffMergeEngine")
struct DiffMergeEngineTests {
    let engine = DiffMergeEngine()

    @Test("Inline diff marks unchanged / removed / added lines")
    func inlineDiff() {
        let lines = engine.inline(mine: "a\nb\nc", theirs: "a\nx\nc")
        #expect(lines == [
            InlineLine(kind: .unchanged, text: "a"),
            InlineLine(kind: .removed, text: "b"),
            InlineLine(kind: .added, text: "x"),
            InlineLine(kind: .unchanged, text: "c")
        ])
    }

    @Test("Side-by-side pairs a changed line and highlights the intra-line difference")
    func sideBySideChanged() {
        let rows = engine.sideBySide(mine: "a\nb\nc", theirs: "a\nx\nc")
        #expect(rows.count == 3)
        #expect(rows[0] == SideBySideRow(kind: .unchanged, left: "a", right: "a"))
        #expect(rows[1].kind == .changed)
        #expect(rows[1].left == "b")
        #expect(rows[1].right == "x")
        #expect(rows[1].leftSegments == [InlineSegment(kind: .deleted, text: "b")])
        #expect(rows[1].rightSegments == [InlineSegment(kind: .inserted, text: "x")])
        #expect(rows[2] == SideBySideRow(kind: .unchanged, left: "c", right: "c"))
    }

    @Test("Side-by-side emits removed-left and added-right rows for unpaired changes")
    func sideBySideUnpaired() {
        let removed = engine.sideBySide(mine: "a\nb", theirs: "a")
        #expect(removed.last == SideBySideRow(kind: .removedLeft, left: "b", right: nil))

        let added = engine.sideBySide(mine: "a", theirs: "a\nb")
        #expect(added.last == SideBySideRow(kind: .addedRight, left: nil, right: "b"))
    }

    @Test("Character diff coalesces same-kind runs")
    func characterDiff() {
        let segments = engine.characterDiff("cat", "cot")
        #expect(segments == [
            InlineSegment(kind: .equal, text: "c"),
            InlineSegment(kind: .deleted, text: "a"),
            InlineSegment(kind: .inserted, text: "o"),
            InlineSegment(kind: .equal, text: "t")
        ])
    }

    @Test("3-way merge with no base reports a genuine conflict")
    func mergeConflict() {
        let blocks = engine.merge(base: nil, mine: "a\nb", theirs: "a\nc")
        #expect(blocks == [.unchanged(["a"]), .conflict(mine: ["b"], theirs: ["c"])])
    }

    @Test("3-way merge classifies pure additions and removals")
    func mergeOneSided() {
        #expect(engine.merge(base: nil, mine: "a\nb", theirs: "a") == [.unchanged(["a"]), .mineOnly(["b"])])
        #expect(engine.merge(base: nil, mine: "a", theirs: "a\nb") == [.unchanged(["a"]), .theirsOnly(["b"])])
    }

    @Test("3-way merge auto-resolves when only one side diverged from base")
    func mergeAutoResolves() {
        // mine == base, so theirs' change is auto-takeable (no conflict).
        let blocks = engine.merge(base: "a\nb", mine: "a\nb", theirs: "a\nc")
        #expect(blocks == [.unchanged(["a"]), .theirsOnly(["c"])])
    }

    @Test("Identical versions produce a single unchanged block")
    func mergeIdentical() {
        #expect(engine.merge(base: "a\nb", mine: "a\nb", theirs: "a\nb") == [.unchanged(["a", "b"])])
    }
}
