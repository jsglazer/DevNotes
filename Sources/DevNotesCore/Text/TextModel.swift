import Foundation

/// Splits a buffer into logical lines and maps between line/column and UTF-16 offsets.
///
/// All offsets are UTF-16 code units so they map straight onto `NSRange`. This is an
/// internal implementation detail of the outline transforms; it does no I/O and holds no
/// view state, so it is fully headless-testable.
struct TextModel: Equatable {
    /// Line contents, without their trailing newline. `components(separatedBy: "\n")`
    /// yields `count == newlines + 1`, so an empty buffer is a single empty line.
    private(set) var lines: [String]

    init(_ text: String) {
        lines = text.components(separatedBy: "\n")
    }

    init(lines: [String]) {
        self.lines = lines.isEmpty ? [""] : lines
    }

    /// The reassembled buffer.
    var text: String { lines.joined(separator: "\n") }

    /// UTF-16 length of a string.
    static func utf16Length(_ s: String) -> Int { (s as NSString).length }

    /// UTF-16 offset of the first character of line `index`.
    func lineStart(_ index: Int) -> Int {
        var offset = 0
        var i = 0
        while i < index && i < lines.count {
            offset += Self.utf16Length(lines[i]) + 1 // +1 for the "\n" separator
            i += 1
        }
        return offset
    }

    /// Line index that contains `offset`. Offsets on a newline boundary belong to the
    /// line that the newline terminates (the earlier line).
    func lineIndex(ofOffset offset: Int) -> Int {
        var running = 0
        for i in 0 ..< lines.count {
            let len = Self.utf16Length(lines[i])
            if offset <= running + len { return i }
            running += len + 1
        }
        return max(0, lines.count - 1)
    }

    /// Inclusive `first...last` line indices touched by `selection`.
    ///
    /// A range whose end sits exactly at the start of a line does NOT pull that trailing
    /// line in (uses `end - 1`), matching how editors treat full-line selections.
    func lineRange(for selection: TextSelection) -> ClosedRange<Int> {
        let first = lineIndex(ofOffset: selection.location)
        if selection.isCaret {
            return first ... first
        }
        let last = lineIndex(ofOffset: max(selection.location, selection.end - 1))
        return first ... max(first, last)
    }

    /// A selection that covers whole lines `range`, from the first line's start through the
    /// last line's final character (newline excluded).
    func selectionCovering(_ range: ClosedRange<Int>) -> TextSelection {
        let start = lineStart(range.lowerBound)
        let endLine = min(range.upperBound, lines.count - 1)
        let end = lineStart(endLine) + Self.utf16Length(lines[endLine])
        return TextSelection(location: start, length: end - start)
    }
}
