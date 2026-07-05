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

    override func keyDown(with event: NSEvent) {
        if let chord = DevNotesCore.KeyChord(macEvent: event), onKeyChord?(chord) == true {
            return
        }
        super.keyDown(with: event)
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
