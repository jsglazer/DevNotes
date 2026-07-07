import Foundation

/// The resolved action→chord table the shell drives shortcuts from. Built by layering the
/// user's `keymap.json` overrides on top of `defaults`, so a partial or partly-broken user file
/// still yields a complete, usable keymap (every action always has a binding).
///
/// Pure value type: it knows nothing about where the JSON came from (the app-layer `KeymapStore`
/// owns file I/O) and nothing about AppKit key events (the shell converts an event to a `KeyChord`
/// and calls `action(for:)`).
public struct Keymap: Sendable {
    public private(set) var bindings: [KeymapAction: KeyChord]

    public init(bindings: [KeymapAction: KeyChord]) {
        self.bindings = bindings
    }

    public func chord(for action: KeymapAction) -> KeyChord? {
        bindings[action]
    }

    /// Reverse lookup used on every key-down: which action (if any) is bound to this chord.
    public func action(for chord: KeyChord) -> KeymapAction? {
        reverse[chord]
    }

    private var reverse: [KeyChord: KeymapAction] {
        var map: [KeyChord: KeymapAction] = [:]
        // Stable iteration so a duplicate chord resolves deterministically (first action wins).
        for action in KeymapAction.allCases {
            guard let chord = bindings[action] else { continue }
            if map[chord] == nil { map[chord] = action }
        }
        return map
    }

    // MARK: - Defaults (standard-macOS layout)

    /// The built-in bindings. Also the seed written to a fresh `keymap.json` so the file itself is
    /// the discoverable catalog of every bindable function.
    public static let defaults = Keymap(bindings: [
        .indent: KeyChord(modifiers: [], key: "tab"),
        .unindent: KeyChord(modifiers: [.shift], key: "tab"),
        .moveLineUp: KeyChord(modifiers: [.control, .option], key: "up"),
        .moveLineDown: KeyChord(modifiers: [.control, .option], key: "down"),
        .previousNote: KeyChord(modifiers: [.option, .command], key: "up"),
        .nextNote: KeyChord(modifiers: [.option, .command], key: "down"),
        .selectToTop: KeyChord(modifiers: [.shift, .command], key: "up"),
        .selectToBottom: KeyChord(modifiers: [.shift, .command], key: "down"),
        .wrapText: KeyChord(modifiers: [.shift, .command], key: "w"),
        .showLineNumbers: KeyChord(modifiers: [.shift, .command], key: "n"),
        .insertDateTime: KeyChord(modifiers: [.control, .option], key: "d")
    ])

    // MARK: - Loading

    /// Merges a decoded `[action rawValue: chord string]` map from `keymap.json` over the defaults.
    /// Unknown action keys and unparseable chords are skipped (reported as warnings) and the
    /// default binding is kept, so a hand-edited file can never leave an action unbound.
    public static func load(from raw: [String: String]) -> (keymap: Keymap, warnings: [String]) {
        var bindings = defaults.bindings
        var warnings: [String] = []
        for (rawAction, rawChord) in raw {
            guard let action = KeymapAction(rawValue: rawAction) else {
                warnings.append("Unknown action “\(rawAction)” ignored.")
                continue
            }
            guard let chord = KeyChord.parse(rawChord) else {
                warnings.append("Could not parse shortcut “\(rawChord)” for \(rawAction); kept default.")
                continue
            }
            bindings[action] = chord
        }
        let keymap = Keymap(bindings: bindings)
        warnings.append(contentsOf: keymap.duplicateWarnings())
        return (keymap, warnings)
    }

    /// The canonical `[rawValue: serialized chord]` map, used to seed/rewrite `keymap.json` with
    /// every action present and sorted stably.
    public var serialized: [String: String] {
        var out: [String: String] = [:]
        for action in KeymapAction.allCases {
            if let chord = bindings[action] { out[action.rawValue] = chord.serialized }
        }
        return out
    }

    /// Flags chords bound to more than one action (a hand-editing mistake): only the first action
    /// in `allCases` order will actually fire.
    private func duplicateWarnings() -> [String] {
        var seen: [KeyChord: KeymapAction] = [:]
        var warnings: [String] = []
        for action in KeymapAction.allCases {
            guard let chord = bindings[action] else { continue }
            if let owner = seen[chord] {
                warnings.append(
                    "Shortcut “\(chord.serialized)” is bound to both \(owner.rawValue) and "
                        + "\(action.rawValue); \(owner.rawValue) wins."
                )
            } else {
                seen[chord] = action
            }
        }
        return warnings
    }
}
