#if os(macOS)
import AppKit
import DevNotesCore

/// `NSTextView` that gives the app first crack at each key press so the user's `keymap.json`
/// bindings (Tab-to-indent, Shift-Tab-to-outdent, select-to-edge, …) run instead of the field
/// editor's defaults. Unhandled keys fall straight through to `super`, preserving normal typing,
/// list continuation (via the delegate's `doCommandBy`), and native shortcuts.
final class EditorTextView: NSTextView {
    /// Set by the representable each update. Returns true when the chord mapped to an action and
    /// was performed, so the event is consumed.
    var onKeyChord: (@MainActor (DevNotesCore.KeyChord) -> Bool)?

    /// Colour of the band painted behind the caret's line, or nil when the current-line highlight is
    /// off. Set by the representable; already resolved for the active theme.
    var currentLineHighlight: NSColor?

    override func keyDown(with event: NSEvent) {
        if let chord = DevNotesCore.KeyChord(macEvent: event), onKeyChord?(chord) == true {
            return
        }
        super.keyDown(with: event)
    }

    /// Paints (behind the glyphs) the current-line band, then lets the text draw, then strokes a
    /// real full-width horizontal line across every Markdown thematic-break line (`---`, `***`,
    /// `___`), so a rule *looks* like a rule while its characters stay editable. The dashes
    /// themselves are dimmed by `MarkdownHighlighter`. The band is drawn first (and the view's own
    /// background is clear) so it sits under the text rather than covering it.
    override func draw(_ dirtyRect: NSRect) {
        drawCurrentLineHighlight(in: dirtyRect)
        super.draw(dirtyRect)
        drawThematicBreaks(in: dirtyRect)
    }

    /// Fills the full width of the caret's line with `currentLineHighlight`. No-op when the
    /// highlight is off or there's an active selection spanning multiple characters (the band tracks
    /// a caret, not a range).
    private func drawCurrentLineHighlight(in dirtyRect: NSRect) {
        guard let color = currentLineHighlight,
              let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange else { return }
        let ns = string as NSString
        let caret = min(selectedRange().location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let origin = textContainerOrigin
        let documentStart = contentManager.documentRange.location

        color.setFill()
        // Walk only the fragments the viewport has ALREADY laid out. Enumerating from the document
        // start with `.ensuresLayout` forced a full-document layout on every redraw (every caret
        // move/blink) — the layout storm behind the random scroll jumps while typing.
        layoutManager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            guard fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedAscending else {
                return false
            }
            let offset = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
            guard offset <= ns.length else { return true }
            // The fragment whose line range contains the caret is the caret's line.
            let fragmentLine = ns.lineRange(for: NSRange(location: min(offset, ns.length), length: 0))
            guard NSEqualRanges(fragmentLine, lineRange) else {
                // Stop once we've scanned past the caret's line.
                return offset <= lineRange.location
            }
            let frame = fragment.layoutFragmentFrame
            let rect = NSRect(x: 0, y: frame.minY + origin.y, width: bounds.width, height: frame.height)
            NSBezierPath(rect: rect).fill()
            return true
        }
    }

    private func drawThematicBreaks(in dirtyRect: NSRect) {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange else { return }

        let ns = string as NSString
        guard ns.length > 0 else { return }
        let origin = textContainerOrigin
        let leftInset = textContainerInset.width
        let documentStart = contentManager.documentRange.location

        // A 1-pt `separatorColor` hairline was effectively invisible against the editor background,
        // so `---` looked like it produced no rule. Draw a clearly visible mid-grey line instead.
        // Enumeration is viewport-scoped and never forces layout: the old whole-document
        // `.ensuresLayout` walk on every redraw destabilised fragment frames mid-draw, which is why
        // a freshly typed `---` rule could appear and immediately vanish.
        NSColor.secondaryLabelColor.setStroke()
        layoutManager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            guard fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedAscending else {
                return false
            }
            let frame = fragment.layoutFragmentFrame
            let y = frame.midY + origin.y
            // Draw only fragments intersecting the redraw region, but keep enumerating downward
            // until we're fully past the bottom of it — the earlier early-out could stop before
            // reaching a rule that sat just inside the dirty rect, so the line never appeared.
            if frame.maxY + origin.y >= dirtyRect.minY - 1, frame.minY + origin.y <= dirtyRect.maxY + 1 {
                let offset = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
                if offset <= ns.length {
                    let lineRange = ns.lineRange(for: NSRange(location: offset, length: 0))
                    let line = ns.substring(with: lineRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if DevNotesCore.Markdown.isThematicBreak(line) {
                        let path = NSBezierPath()
                        path.lineWidth = 1.5
                        path.move(to: NSPoint(x: leftInset, y: y.rounded() + 0.5))
                        path.line(to: NSPoint(x: bounds.width - leftInset, y: y.rounded() + 0.5))
                        path.stroke()
                    }
                }
            }
            // Stop once this fragment starts below the dirty region.
            return frame.minY + origin.y <= dirtyRect.maxY + 1
        }
    }
}

extension DevNotesCore.KeyChord {
    /// Builds a `KeyChord` from an AppKit key-down event: the four device-independent modifiers
    /// plus a normalized key token (special keys by key code, everything else by its shifted
    /// character). Returns nil for events with no usable character (e.g. dead keys).
    init?(macEvent event: NSEvent) {
        var modifiers: Set<DevNotesCore.KeyModifier> = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        guard let key = Self.keyToken(for: event) else { return nil }
        self.init(modifiers: modifiers, key: key)
    }

    /// Hardware key codes for the keys that carry no useful character, mapped to the Core token set.
    private static let specialKeyCodes: [UInt16: String] = [
        126: "up", 125: "down", 123: "left", 124: "right",
        48: "tab", 36: "return", 76: "return", 49: "space",
        53: "escape", 51: "delete", 117: "delete"
    ]

    private static func keyToken(for event: NSEvent) -> String? {
        if let named = specialKeyCodes[event.keyCode] { return named }
        // charactersIgnoringModifiers applies Shift (but not Cmd/Ctrl/Opt), so ⇧⌘N reads as "N".
        guard let characters = event.charactersIgnoringModifiers, characters.isEmpty == false else {
            return nil
        }
        return characters.lowercased()
    }
}
#endif
