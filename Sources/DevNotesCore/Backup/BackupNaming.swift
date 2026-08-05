import Foundation

/// Naming rules for the files inside a backup archive. Pure, so the awkward parts — a title that
/// isn't a legal file name, two notes sharing a title — are decided here and tested headlessly
/// rather than inside the file-copying code.
///
/// Notes DevNotes creates are named `<UUID>.md` on disk, which makes an archive of raw file names
/// unreadable. A backup names each file after the note's title instead, and carries a manifest
/// mapping those names back to the originals (the raw file name is the note's identity — pins,
/// open-on-launch and caret positions are all keyed by it).
public enum BackupNaming {
    /// Characters that can't appear in a file name on the platforms DevNotes runs on (`/` is the
    /// path separator everywhere; `:` is one in the Finder's eyes; the rest are Windows-illegal and
    /// would make an archive unpleasant to unzip elsewhere).
    private static let illegal = Set(#"/\:?%*|"<>"# + "\u{0}")

    /// Longest title we'll turn into a file name, so a note whose first line is a paragraph doesn't
    /// produce a 4KB file name.
    private static let maxLength = 80

    /// One note's place in the archive: the file name it's written as, and the on-disk name it came
    /// from.
    public struct Entry: Equatable, Sendable {
        /// The note's real file name on disk (`<UUID>.md`), i.e. its `NoteID`.
        public let id: String
        /// The name this note is written as inside the archive (`<title>.md`).
        public let fileName: String

        public init(id: String, fileName: String) {
            self.id = id
            self.fileName = fileName
        }
    }

    /// The archive entry for every note, in the order given. Titles that collide (case-insensitively
    /// — the notes directory usually lives on a case-insensitive volume) get ` 2`, ` 3`… suffixes,
    /// so no note is ever silently overwritten by another inside the zip.
    public static func entries(for notes: [NoteSummary]) -> [Entry] {
        var taken: Set<String> = []
        return notes.map { note in
            let base = baseName(title: note.title, id: note.id.rawValue)
            var candidate = base
            var counter = 2
            while taken.contains(candidate.lowercased()) {
                candidate = "\(base) \(counter)"
                counter += 1
            }
            taken.insert(candidate.lowercased())
            return Entry(id: note.id.rawValue, fileName: "\(candidate).md")
        }
    }

    /// The extension-less file name for a title: illegal characters replaced, whitespace collapsed,
    /// length capped. Falls back to the note's own file name (minus `.md`) when the title yields
    /// nothing usable, so every note lands in the archive under *some* name.
    public static func baseName(title: String, id: String) -> String {
        var cleaned = ""
        var lastWasSpace = false
        for character in title {
            if character.isWhitespace || character.isNewline {
                // Collapse any run of whitespace to a single space.
                if lastWasSpace { continue }
                cleaned.append(" ")
                lastWasSpace = true
                continue
            }
            lastWasSpace = false
            cleaned.append(illegal.contains(character) ? "-" : character)
        }
        // Leading dots make a hidden file; trailing dots/spaces are stripped by some file systems.
        let trimmed = cleaned
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let capped = String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        if capped.isEmpty {
            let fallback = (id as NSString).deletingPathExtension
            return fallback.isEmpty ? "Untitled" : fallback
        }
        return capped
    }

    /// The manifest written to the archive root, mapping each archived file back to the on-disk name
    /// it came from — the only way to restore a note under its original identity.
    public static func manifest(for entries: [Entry], archiveName: String, created: String) -> String {
        var lines = [
            "\(archiveName)",
            "Created: \(created)",
            "",
            "Notes are archived under their titles. This maps each one back to its original file",
            "name on disk — restore a note under that name to keep its identity (pins, open-on-launch",
            "and caret position are all keyed by the file name).",
            "",
            "ARCHIVED FILE\tORIGINAL FILE"
        ]
        lines.append(contentsOf: entries.map { "\($0.fileName)\t\($0.id)" })
        return lines.joined(separator: "\n") + "\n"
    }
}
