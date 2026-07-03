import Foundation

/// One captured version of a note involved in a sync conflict. Under v1's last-writer-wins
/// record resolution, these pre-conflict versions are captured (via `NSFileVersion` in the
/// shell) and surfaced to the merge UI — never silently discarded.
public struct NoteVersion: Equatable, Sendable, Codable {
    public var body: String
    public var modifiedAt: Date
    public var deviceName: String

    public init(body: String, modifiedAt: Date, deviceName: String) {
        self.body = body
        self.modifiedAt = modifiedAt
        self.deviceName = deviceName
    }
}

/// A conflict on a single note: the local version (`mine`), the incoming version (`theirs`),
/// and the common ancestor (`base`) when one is known.
public struct ConflictRecord: Equatable, Sendable, Identifiable, Codable {
    public var id: NoteID
    public var base: NoteVersion?
    public var mine: NoteVersion
    public var theirs: NoteVersion

    public init(id: NoteID, base: NoteVersion?, mine: NoteVersion, theirs: NoteVersion) {
        self.id = id
        self.base = base
        self.mine = mine
        self.theirs = theirs
    }
}

/// Pure FIFO queue of unresolved conflicts, so that if several arise while offline the user
/// can resolve them one at a time on reconnect. A value type / state machine — no I/O, fully
/// testable. Enqueuing a conflict for a note that is already queued updates it in place
/// (keeping its position) rather than duplicating.
public struct ConflictQueue: Equatable, Sendable {
    public private(set) var pending: [ConflictRecord]

    public init(_ pending: [ConflictRecord] = []) {
        self.pending = pending
    }

    public var isEmpty: Bool { pending.isEmpty }
    public var count: Int { pending.count }

    /// The conflict the user should resolve next.
    public var current: ConflictRecord? { pending.first }

    public mutating func enqueue(_ conflict: ConflictRecord) {
        if let index = pending.firstIndex(where: { $0.id == conflict.id }) {
            pending[index] = conflict
        } else {
            pending.append(conflict)
        }
    }

    /// Removes the conflict for `id` (e.g. once resolved). Returns whether one was removed.
    @discardableResult
    public mutating func resolve(_ id: NoteID) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return false }
        pending.remove(at: index)
        return true
    }

    /// Removes and returns the current conflict.
    @discardableResult
    public mutating func resolveCurrent() -> ConflictRecord? {
        guard pending.isEmpty == false else { return nil }
        return pending.removeFirst()
    }
}
