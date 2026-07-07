import Foundation

/// Pure parsing of a single line's leading whitespace and list marker. No regex engine,
/// no state — deterministic character scanning so the outline transforms stay trivial.
enum LinePrefix {
    /// Splits a line into its leading whitespace (spaces/tabs) and the remainder.
    static func splitIndent(_ line: String) -> (indent: String, rest: String) {
        var indentEnd = line.startIndex
        while indentEnd < line.endIndex, line[indentEnd] == " " || line[indentEnd] == "\t" {
            indentEnd = line.index(after: indentEnd)
        }
        return (String(line[line.startIndex ..< indentEnd]), String(line[indentEnd...]))
    }

    /// Depth of a line's leading indentation, counted in whitespace characters (each tab or space
    /// counts as one). Used to decide which following lines are a bullet's nested descendants.
    static func indentDepth(_ line: String) -> Int {
        splitIndent(line).indent.count
    }

    /// Length (in Characters) of a bullet marker at the start of `rest` — a `-`, `*` or `+`
    /// followed by exactly one space (e.g. `"- "`). `nil` if `rest` is not a bullet item.
    static func bulletMarkerLength(_ rest: String) -> Int? {
        guard let first = rest.first, first == "-" || first == "*" || first == "+" else { return nil }
        let afterMarker = rest.index(after: rest.startIndex)
        guard afterMarker < rest.endIndex, rest[afterMarker] == " " else { return nil }
        return 2
    }

    /// Parses a numbered marker (`"12. "`) at the start of `rest`, returning the marker's
    /// Character length and its value. `nil` if `rest` is not a numbered item.
    static func numberMarker(_ rest: String) -> (markerLength: Int, number: Int)? {
        var idx = rest.startIndex
        var digits = ""
        while idx < rest.endIndex, rest[idx].isNumber {
            digits.append(rest[idx])
            idx = rest.index(after: idx)
        }
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        guard idx < rest.endIndex, rest[idx] == "." else { return nil }
        idx = rest.index(after: idx)
        guard idx < rest.endIndex, rest[idx] == " " else { return nil }
        // digits + "." + " "
        return (digits.count + 2, value)
    }

    /// Whether `line` carries a bullet marker after its indentation.
    static func isBulleted(_ line: String) -> Bool {
        bulletMarkerLength(splitIndent(line).rest) != nil
    }

    /// Whether `line` carries a numbered marker after its indentation.
    static func isNumbered(_ line: String) -> Bool {
        numberMarker(splitIndent(line).rest) != nil
    }
}
