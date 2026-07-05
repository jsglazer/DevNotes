import Foundation

/// A keyboard modifier, normalized to a canonical name. Parsing accepts common aliases
/// (`cmd`/`command`, `alt`/`opt`/`option`, `ctrl`/`control`, `shift`) so hand-edited `keymap.json`
/// is forgiving; serialization always emits the canonical short token.
public enum KeyModifier: String, Sendable, CaseIterable, Comparable {
    case command
    case option
    case control
    case shift

    /// Canonical short token written back to `keymap.json` (e.g. `cmd`).
    public var token: String {
        switch self {
        case .command: return "cmd"
        case .option: return "alt"
        case .control: return "ctrl"
        case .shift: return "shift"
        }
    }

    /// The macOS glyph used in the Settings shortcut list (⌘⌥⌃⇧).
    public var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    static func parse(_ token: String) -> KeyModifier? {
        switch token.lowercased() {
        case "cmd", "command", "meta", "super": return .command
        case "alt", "opt", "option": return .option
        case "ctrl", "control": return .control
        case "shift": return .shift
        default: return nil
        }
    }

    /// Canonical modifier order for display/serialization: ⌃⌥⇧⌘ (Apple's HIG order).
    private var order: Int {
        switch self {
        case .control: return 0
        case .option: return 1
        case .shift: return 2
        case .command: return 3
        }
    }

    public static func < (lhs: KeyModifier, rhs: KeyModifier) -> Bool { lhs.order < rhs.order }
}

/// A parsed keyboard shortcut: a set of modifiers plus a single normalized key token
/// (e.g. `up`, `tab`, `w`). Pure and `Hashable` so the shell can reverse-map a pressed chord back
/// to its `KeymapAction` with a dictionary lookup — no AppKit/UIKit types leak into Core.
public struct KeyChord: Sendable, Hashable {
    public let modifiers: Set<KeyModifier>
    /// Normalized, lowercased key token. Named keys: `up`,`down`,`left`,`right`,`tab`,`return`,
    /// `space`,`escape`,`delete`. Otherwise a single character such as `w` or `]`.
    public let key: String

    public init(modifiers: Set<KeyModifier>, key: String) {
        self.modifiers = modifiers
        self.key = key.lowercased()
    }

    /// Parses `"shift+cmd+n"` / `"ctrl+alt+up"` / `"tab"`. Returns nil if a modifier token is
    /// unrecognized or the key is missing — callers surface that as a warning and fall back to the
    /// default binding, so one bad line never breaks the whole keymap.
    public static func parse(_ string: String) -> KeyChord? {
        let parts = string.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let rawKey = parts.last, rawKey.isEmpty == false else { return nil }
        var modifiers: Set<KeyModifier> = []
        for token in parts.dropLast() {
            guard let modifier = KeyModifier.parse(token) else { return nil }
            modifiers.insert(modifier)
        }
        return KeyChord(modifiers: modifiers, key: normalizeKey(rawKey))
    }

    /// Folds key aliases to the canonical token set.
    private static func normalizeKey(_ raw: String) -> String {
        switch raw.lowercased() {
        case "up", "uparrow", "arrowup": return "up"
        case "down", "downarrow", "arrowdown": return "down"
        case "left", "leftarrow", "arrowleft": return "left"
        case "right", "rightarrow", "arrowright": return "right"
        case "tab": return "tab"
        case "return", "enter", "\n": return "return"
        case "space", "spacebar", " ": return "space"
        case "esc", "escape": return "escape"
        case "del", "delete", "backspace": return "delete"
        default: return raw.lowercased()
        }
    }

    /// Canonical serialization written to `keymap.json`, e.g. `ctrl+alt+up`.
    public var serialized: String {
        (modifiers.sorted().map(\.token) + [key]).joined(separator: "+")
    }

    /// macOS-style glyph string for the Settings shortcut list, e.g. `⇧⌘N`.
    public var displaySymbols: String {
        let mods = modifiers.sorted().map(\.symbol).joined()
        return mods + keySymbol
    }

    private var keySymbol: String {
        switch key {
        case "up": return "↑"
        case "down": return "↓"
        case "left": return "←"
        case "right": return "→"
        case "tab": return "⇥"
        case "return": return "↩"
        case "space": return "␣"
        case "escape": return "⎋"
        case "delete": return "⌫"
        default: return key.uppercased()
        }
    }
}
