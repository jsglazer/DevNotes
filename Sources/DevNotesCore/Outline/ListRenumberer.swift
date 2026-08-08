import Foundation

/// Re-sequences ordered-list markers after lines have been re-ordered.
///
/// Pure line-array in, line-array out — no view state, no I/O — so the renumbering rules are
/// headless-testable the same way the rest of `OutlineEngine` is.
///
/// Rules, chosen so a move never rewrites more of the buffer than it has to:
/// - Only **runs** (maximal blocks of consecutive list lines, broken by any non-list line) that
///   intersect the moved lines are touched.
/// - Within a run, each indent depth carries its own sublist, and a sublist restarts whenever the
///   text steps back out to a shallower depth — so nested lists number independently.
/// - A sublist keeps its **lowest** existing number as its start value, then counts up from there.
///   Using the minimum rather than the first line's value is what makes a reorder come back as
///   `1. 2. 3.` instead of inheriting whichever item happened to land on top.
/// - A sublist whose numbers are all identical (the lazy `1. 1. 1.` Markdown style) is left alone.
enum ListRenumberer {
    /// A marker rewrite on one line, enough to carry a caret across the edit.
    struct Change {
        /// UTF-16 offset, within the line, of the first body character before the rewrite
        /// (indentation + old marker). A caret at or past this column moves with `delta`.
        let bodyStart: Int
        /// Signed UTF-16 change in the marker's length.
        let delta: Int
    }

    /// Renumbers every ordered-list run that intersects `touched`.
    /// Returns the rewritten lines plus the per-line marker changes (only for lines that changed).
    static func renumber(
        lines: [String],
        touching touched: ClosedRange<Int>
    ) -> (lines: [String], changes: [Int: Change]) {
        guard !lines.isEmpty else { return (lines, [:]) }
        let lower = max(0, touched.lowerBound)
        let upper = min(lines.count - 1, touched.upperBound)
        guard lower <= upper else { return (lines, [:]) }

        // Widen to whole runs so a move into the middle of a list renumbers the entire list.
        var start = lower
        while start > 0, isListItem(lines[start - 1]) { start -= 1 }
        var end = upper
        while end < lines.count - 1, isListItem(lines[end + 1]) { end += 1 }

        var result = lines
        var changes: [Int: Change] = [:]
        var index = start
        while index <= end {
            guard isListItem(result[index]) else {
                index += 1
                continue
            }
            var last = index
            while last + 1 <= end, isListItem(result[last + 1]) { last += 1 }
            renumberRun(index ... last, lines: &result, changes: &changes)
            index = last + 1
        }
        return (result, changes)
    }

    /// Whether a line is a bullet or numbered list item.
    private static func isListItem(_ line: String) -> Bool {
        let rest = LinePrefix.splitIndent(line).rest
        return LinePrefix.bulletMarkerLength(rest) != nil || LinePrefix.numberMarker(rest) != nil
    }

    /// One numbered line inside a run, tagged with the sublist it belongs to.
    private struct Item {
        let lineIndex: Int
        let sublist: Int
        let number: Int
    }

    private static func renumberRun(
        _ run: ClosedRange<Int>,
        lines: inout [String],
        changes: inout [Int: Change]
    ) {
        // Pass 1 — split the run into sublists keyed by indent depth. `active` maps a depth to the
        // sublist currently open there; stepping out to a shallower depth closes the deeper ones,
        // so the next nested list gets a fresh id (and restarts its numbering).
        var active: [Int: Int] = [:]
        var nextSublist = 0
        var items: [Item] = []
        for lineIndex in run {
            let (indent, rest) = LinePrefix.splitIndent(lines[lineIndex])
            let depth = indent.count
            active = active.filter { $0.key <= depth }
            guard let marker = LinePrefix.numberMarker(rest) else {
                // A bullet interrupts any ordered list open at its own depth.
                active[depth] = nil
                continue
            }
            let sublist: Int
            if let open = active[depth] {
                sublist = open
            } else {
                sublist = nextSublist
                nextSublist += 1
                active[depth] = sublist
            }
            items.append(Item(lineIndex: lineIndex, sublist: sublist, number: marker.number))
        }

        // Pass 2 — renumber each sublist from its lowest existing value, leaving the lazy
        // all-same-number style untouched.
        for sublist in 0 ..< nextSublist {
            let members = items.filter { $0.sublist == sublist }
            guard let start = members.map(\.number).min() else { continue }
            if members.allSatisfy({ $0.number == members[0].number }) { continue }
            for (offset, item) in members.enumerated() {
                let target = start + offset
                guard target != item.number else { continue }
                rewrite(line: item.lineIndex, to: target, lines: &lines, changes: &changes)
            }
        }
    }

    /// Replaces the numbered marker on `line` with `number`, recording the caret-carrying change.
    private static func rewrite(
        line: Int,
        to number: Int,
        lines: inout [String],
        changes: inout [Int: Change]
    ) {
        let (indent, rest) = LinePrefix.splitIndent(lines[line])
        guard let marker = LinePrefix.numberMarker(rest) else { return }
        let oldMarker = String(rest.prefix(marker.markerLength))
        let newMarker = "\(number). "
        lines[line] = indent + newMarker + String(rest.dropFirst(marker.markerLength))
        let indentLength = TextModel.utf16Length(indent)
        changes[line] = Change(
            bodyStart: indentLength + TextModel.utf16Length(oldMarker),
            delta: TextModel.utf16Length(newMarker) - TextModel.utf16Length(oldMarker)
        )
    }
}
