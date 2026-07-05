import DevNotesCore
import Foundation

/// Loads (and, on first run, seeds) the user-editable shortcut file at
/// `$HOME/.config/devnotes/keymap.json`. The seed is the full default keymap — every bindable
/// action written out with its default chord — so opening that one file shows the complete,
/// editable catalog of functions that can be bound.
///
/// This is the only place that touches the filesystem for shortcuts; `Keymap` (Core) does the
/// pure merge/validation. Missing or malformed files degrade gracefully to the defaults rather
/// than throwing, so a bad edit never blocks launch.
enum KeymapStore {
    #if os(macOS)
    /// `~/.config/devnotes/keymap.json` (macOS only — the file-backed, user-editable keymap is a
    /// desktop feature; iOS has no equivalent config location).
    static var fileURL: URL {
        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("devnotes", isDirectory: true)
        return config.appendingPathComponent("keymap.json", isDirectory: false)
    }
    #endif

    /// The resolved keymap plus any warnings (unknown actions, unparseable/duplicate chords) to
    /// surface in Settings. On macOS it reads (and first-run seeds) the keymap file; on iOS it
    /// simply returns the built-in defaults.
    static func load() -> (keymap: Keymap, warnings: [String]) {
        #if os(macOS)
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else {
            seedDefaults(at: url)
            return (Keymap.defaults, [])
        }
        guard let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return (Keymap.defaults, ["Could not read keymap.json (invalid JSON); using defaults."])
        }
        return Keymap.load(from: raw)
        #else
        return (Keymap.defaults, [])
        #endif
    }

    #if os(macOS)

    /// Writes the full default keymap to `url`, creating `~/.config/devnotes` as needed. Best
    /// effort: a write failure (sandbox/permissions) just means the user runs on the in-memory
    /// defaults, which is fine.
    private static func seedDefaults(at url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Keymap.defaults.serialized) else { return }
        try? data.write(to: url, options: .atomic)
    }
    #endif
}
