import Foundation

/// Stable identity for a note. Backed by the note's relative file name in the iCloud
/// ubiquity container (the source of truth is one `.md` file per note).
public struct NoteID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// A single note. `body` is the full Markdown text; the file on disk is authoritative and
/// this value type is what the pure core reasons about. No I/O lives here.
public struct Note: Equatable, Sendable, Identifiable, Codable {
    public var id: NoteID
    public var body: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(id: NoteID, body: String, createdAt: Date, modifiedAt: Date) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Display title: the first non-empty line, with leading Markdown heading markers and
    /// whitespace stripped. Falls back to "Untitled".
    public var title: String {
        for rawLine in body.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            var stripped = Substring(trimmed)
            while stripped.first == "#" { stripped = stripped.dropFirst() }
            let title = stripped.trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? "Untitled" : title
        }
        return "Untitled"
    }
}

/// Lightweight projection used for the modified-date-sorted list and the search index. This
/// is derived from `Note` (rebuildable from files); it is never a source of truth.
public struct NoteSummary: Equatable, Sendable, Identifiable, Codable {
    public var id: NoteID
    public var title: String
    public var body: String
    public var modifiedAt: Date

    public init(id: NoteID, title: String, body: String, modifiedAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.modifiedAt = modifiedAt
    }

    public init(_ note: Note) {
        self.init(id: note.id, title: note.title, body: note.body, modifiedAt: note.modifiedAt)
    }

    /// Sorts most-recently-modified first, breaking ties on `id` so the order is deterministic.
    public static func sortedByModified(_ summaries: [NoteSummary]) -> [NoteSummary] {
        summaries.sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.id.rawValue < rhs.id.rawValue
        }
    }
}
