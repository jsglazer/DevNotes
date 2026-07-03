import Foundation

/// Pure outline transforms: `(text, selection) -> (text, selection)`.
///
/// Every operation RETURNS the new selection rather than mutating a text view — that is what
/// makes cursor/selection behaviour headless-testable instead of manual-QA-only. This type
/// imports only `Foundation`: **zero AppKit / UIKit / SwiftUI / CloudKit**, and it performs no
/// file or network I/O.
///
/// Selection semantics (documented so tests are legible):
/// - A **range** selection over a block op (bullet, number, indent, outdent) returns a selection
///   that covers the same whole lines after the edit ("operate on these lines, keep them selected").
/// - A **caret** shifts by the change to its line's leading marker/indentation, clamped so it
///   never lands left of its line start.
public struct OutlineEngine: Sendable {
    /// One indentation level inserted by `indent`. Default is a tab.
    public let indentUnit: String
    /// How many leading spaces `outdent` will strip when a line is space-indented.
    public let indentWidth: Int

    public init(indentUnit: String = "\t", indentWidth: Int = 4) {
        self.indentUnit = indentUnit
        self.indentWidth = indentWidth
    }

    // MARK: - Bullet list

    /// Toggles a `- ` bullet on every line the selection touches. If all touched lines are
    /// already bulleted they are un-bulleted; otherwise a bullet is added to each (numbered
    /// lines are converted to bullets).
    public func toggleBullet(text: String, selection: TextSelection) -> TextEdit {
        let model = TextModel(text)
        let range = model.lineRange(for: selection)
        let allBulleted = range.allSatisfy { LinePrefix.isBulleted(model.lines[$0]) }
        return applyPrefixOp(text: text, selection: selection) { _, line in
            let (indent, rest) = LinePrefix.splitIndent(line)
            if allBulleted {
                guard let markerLen = LinePrefix.bulletMarkerLength(rest) else { return (line, 0) }
                let marker = String(rest.prefix(markerLen))
                let newLine = indent + String(rest.dropFirst(markerLen))
                return (newLine, -TextModel.utf16Length(marker))
            }
            if LinePrefix.bulletMarkerLength(rest) != nil { return (line, 0) }
            if let number = LinePrefix.numberMarker(rest) {
                let oldMarker = String(rest.prefix(number.markerLength))
                let newLine = indent + "- " + String(rest.dropFirst(number.markerLength))
                return (newLine, TextModel.utf16Length("- ") - TextModel.utf16Length(oldMarker))
            }
            return (indent + "- " + rest, TextModel.utf16Length("- "))
        }
    }

    // MARK: - Numbered list

    /// Toggles a numbered list on the touched lines. When numbering, lines are assigned
    /// sequential values `1.`, `2.`, `3.` … from the top of the selection (renumbering as it
    /// goes); when all touched lines are already numbered they are un-numbered.
    public func toggleNumber(text: String, selection: TextSelection) -> TextEdit {
        let model = TextModel(text)
        let range = model.lineRange(for: selection)
        let first = range.lowerBound
        let allNumbered = range.allSatisfy { LinePrefix.isNumbered(model.lines[$0]) }
        return applyPrefixOp(text: text, selection: selection) { index, line in
            let (indent, rest) = LinePrefix.splitIndent(line)
            if allNumbered {
                guard let number = LinePrefix.numberMarker(rest) else { return (line, 0) }
                let marker = String(rest.prefix(number.markerLength))
                let newLine = indent + String(rest.dropFirst(number.markerLength))
                return (newLine, -TextModel.utf16Length(marker))
            }
            // Strip any existing bullet/number marker, then apply the sequential number.
            var stripped = rest
            var oldMarker = ""
            if let bulletLen = LinePrefix.bulletMarkerLength(rest) {
                oldMarker = String(rest.prefix(bulletLen))
                stripped = String(rest.dropFirst(bulletLen))
            } else if let number = LinePrefix.numberMarker(rest) {
                oldMarker = String(rest.prefix(number.markerLength))
                stripped = String(rest.dropFirst(number.markerLength))
            }
            let newMarker = "\(index - first + 1). "
            let newLine = indent + newMarker + stripped
            return (newLine, TextModel.utf16Length(newMarker) - TextModel.utf16Length(oldMarker))
        }
    }

    // MARK: - Indent / outdent

    /// Inserts one indentation level at the start of each touched line. Empty lines are left
    /// untouched for range selections (so a block indent leaves no trailing-whitespace lines),
    /// but a caret on an empty line still indents so the user can indent-then-type.
    public func indent(text: String, selection: TextSelection) -> TextEdit {
        let isCaret = selection.isCaret
        return applyPrefixOp(text: text, selection: selection) { _, line in
            if !isCaret, line.isEmpty { return (line, 0) }
            return (indentUnit + line, TextModel.utf16Length(indentUnit))
        }
    }

    /// Removes one indentation level from the start of each touched line: a leading tab, or up
    /// to `indentWidth` leading spaces. Lines with no leading whitespace are unchanged.
    public func outdent(text: String, selection: TextSelection) -> TextEdit {
        applyPrefixOp(text: text, selection: selection) { _, line in
            guard let first = line.first else { return (line, 0) }
            if first == "\t" {
                return (String(line.dropFirst()), -TextModel.utf16Length("\t"))
            }
            if first == " " {
                var removed = 0
                var idx = line.startIndex
                while idx < line.endIndex, line[idx] == " ", removed < indentWidth {
                    removed += 1
                    idx = line.index(after: idx)
                }
                return (String(line[idx...]), -removed)
            }
            return (line, 0)
        }
    }

    // MARK: - Move line up / down

    /// Moves the block of touched lines up by one line. No-op (unchanged input) at the top.
    public func moveLineUp(text: String, selection: TextSelection) -> TextEdit {
        let model = TextModel(text)
        let range = model.lineRange(for: selection)
        let first = range.lowerBound
        let last = range.upperBound
        guard first > 0 else { return TextEdit(text: text, selection: selection) }
        var lines = model.lines
        let block = Array(lines[first ... last])
        let above = lines[first - 1]
        lines.removeSubrange((first - 1) ... last)
        lines.insert(contentsOf: block + [above], at: first - 1)
        let newModel = TextModel(lines: lines)
        let shift = newModel.lineStart(first - 1) - model.lineStart(first)
        let newSelection = TextSelection(location: selection.location + shift, length: selection.length)
        return TextEdit(text: newModel.text, selection: newSelection)
    }

    /// Moves the block of touched lines down by one line. No-op (unchanged input) at the bottom.
    public func moveLineDown(text: String, selection: TextSelection) -> TextEdit {
        let model = TextModel(text)
        let range = model.lineRange(for: selection)
        let first = range.lowerBound
        let last = range.upperBound
        guard last < model.lines.count - 1 else { return TextEdit(text: text, selection: selection) }
        var lines = model.lines
        let block = Array(lines[first ... last])
        let below = lines[last + 1]
        lines.removeSubrange(first ... (last + 1))
        lines.insert(contentsOf: [below] + block, at: first)
        let newModel = TextModel(lines: lines)
        let shift = newModel.lineStart(first + 1) - model.lineStart(first)
        let newSelection = TextSelection(location: selection.location + shift, length: selection.length)
        return TextEdit(text: newModel.text, selection: newSelection)
    }

    // MARK: - Heading level

    /// Sets the Markdown heading level (`1...6`) on each touched line, replacing any existing
    /// heading marker. `level == 0` clears the heading, returning the line to a paragraph.
    public func setHeading(level: Int, text: String, selection: TextSelection) -> TextEdit {
        let clamped = max(0, min(6, level))
        return applyPrefixOp(text: text, selection: selection) { _, line in
            let (indent, rest) = LinePrefix.splitIndent(line)
            var body = Substring(rest)
            var oldMarkerLength = 0
            while body.first == "#" {
                body = body.dropFirst()
                oldMarkerLength += 1
            }
            if oldMarkerLength > 0, body.first == " " {
                body = body.dropFirst()
                oldMarkerLength += 1
            }
            let newMarker = clamped == 0 ? "" : String(repeating: "#", count: clamped) + " "
            let newLine = indent + newMarker + String(body)
            return (newLine, TextModel.utf16Length(newMarker) - oldMarkerLength)
        }
    }

    // MARK: - List continuation on Enter

    /// Inserts a newline, continuing a list marker when the caret's line is a list item.
    /// On an **empty** list item (marker with no text) a caret Enter exits the list, clearing
    /// the marker instead of adding another. Any selected range is replaced by the newline.
    public func insertNewline(text: String, selection: TextSelection) -> TextEdit {
        let ns = text as NSString
        let model = TextModel(text)
        let lineIndex = model.lineIndex(ofOffset: selection.location)
        let line = model.lines[lineIndex]
        let (indent, rest) = LinePrefix.splitIndent(line)

        var newMarker = ""
        var emptyListItem = false
        if let bulletLen = LinePrefix.bulletMarkerLength(rest) {
            emptyListItem = String(rest.dropFirst(bulletLen)).isEmpty
            newMarker = indent + "- "
        } else if let number = LinePrefix.numberMarker(rest) {
            emptyListItem = String(rest.dropFirst(number.markerLength)).isEmpty
            newMarker = indent + "\(number.number + 1). "
        }

        // Empty list item + caret Enter => exit the list by clearing the current line.
        if emptyListItem, selection.isCaret {
            let lineStart = model.lineStart(lineIndex)
            let lineEnd = lineStart + TextModel.utf16Length(line)
            let newText = ns.substring(to: lineStart) + ns.substring(from: lineEnd)
            return TextEdit(text: newText, selection: .caret(lineStart))
        }

        let insertion = "\n" + newMarker
        let newText = ns.substring(to: selection.location) + insertion + ns.substring(from: selection.end)
        let caret = selection.location + TextModel.utf16Length(insertion)
        return TextEdit(text: newText, selection: .caret(caret))
    }

    // MARK: - Shared prefix-edit driver

    /// Applies a per-line prefix `transform` to every touched line. `transform` returns the new
    /// line and the signed UTF-16 delta applied to that line's leading prefix (used to shift a
    /// caret). Range selections come back covering the same whole lines.
    private func applyPrefixOp(
        text: String,
        selection: TextSelection,
        transform: (_ lineIndex: Int, _ line: String) -> (line: String, prefixDelta: Int)
    ) -> TextEdit {
        let model = TextModel(text)
        let range = model.lineRange(for: selection)
        var newLines = model.lines
        var caretLineDelta = 0
        for i in range {
            let result = transform(i, model.lines[i])
            newLines[i] = result.line
            if i == range.lowerBound { caretLineDelta = result.prefixDelta }
        }
        let newModel = TextModel(lines: newLines)
        if selection.isCaret {
            let line = range.lowerBound
            let column = selection.location - model.lineStart(line)
            let newLocation = model.lineStart(line) + max(0, column + caretLineDelta)
            return TextEdit(text: newModel.text, selection: .caret(newLocation))
        }
        return TextEdit(text: newModel.text, selection: newModel.selectionCovering(range))
    }
}
