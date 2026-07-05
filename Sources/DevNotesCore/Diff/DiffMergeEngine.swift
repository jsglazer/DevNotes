import Foundation

/// A run of characters classified against the other version, for intra-line highlighting.
public struct InlineSegment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case equal, inserted, deleted }
    public var kind: Kind
    public var text: String
    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// One row of the macOS side-by-side merge view. `changed` rows carry char-level segments so
/// the UI can highlight exactly what differs within the line.
public struct SideBySideRow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case unchanged, changed, addedRight, removedLeft }
    public var kind: Kind
    public var left: String?
    public var right: String?
    public var leftSegments: [InlineSegment]
    public var rightSegments: [InlineSegment]
    public init(
        kind: Kind,
        left: String?,
        right: String?,
        leftSegments: [InlineSegment] = [],
        rightSegments: [InlineSegment] = []
    ) {
        self.kind = kind
        self.left = left
        self.right = right
        self.leftSegments = leftSegments
        self.rightSegments = rightSegments
    }
}

/// One line of the iOS inline merge view.
public struct InlineLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case unchanged, removed, added }
    public var kind: Kind
    public var text: String
    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// A block of a 3-way merge. Auto-resolvable blocks are labelled by which side changed;
/// genuine divergences are `conflict`.
public enum MergeBlock: Equatable, Sendable {
    case unchanged([String])
    case mineOnly([String])
    case theirsOnly([String])
    case conflict(mine: [String], theirs: [String])
}

/// Pure diff / merge engine serving BOTH the side-by-side (macOS) and inline (iOS) layouts
/// from the same LCS logic. Zero AppKit / UIKit / SwiftUI / CloudKit; no I/O.
public struct DiffMergeEngine: Sendable {
    public init() {}

    // MARK: - Line-level diff (inline, iOS)

    /// `mine` vs `theirs` as a single inline stream: unchanged, removed (mine-only),
    /// added (theirs-only).
    public func inline(mine: String, theirs: String) -> [InlineLine] {
        LCS.diff(mine.splitIntoLines(), theirs.splitIntoLines()).map { change in
            switch change {
            case let .equal(line): return InlineLine(kind: .unchanged, text: line)
            case let .delete(line): return InlineLine(kind: .removed, text: line)
            case let .insert(line): return InlineLine(kind: .added, text: line)
            }
        }
    }

    // MARK: - Line-level diff (side-by-side, macOS)

    /// `mine` (left) vs `theirs` (right) as aligned rows. Adjacent deletes/inserts are paired
    /// into `changed` rows with char-level highlights; leftovers become removed/added rows.
    public func sideBySide(mine: String, theirs: String) -> [SideBySideRow] {
        let ops = LCS.diff(mine.splitIntoLines(), theirs.splitIntoLines())
        var rows: [SideBySideRow] = []
        var index = 0
        while index < ops.count {
            if case let .equal(line) = ops[index] {
                rows.append(SideBySideRow(kind: .unchanged, left: line, right: line))
                index += 1
                continue
            }
            var deletes: [String] = []
            var inserts: [String] = []
            collecting: while index < ops.count {
                switch ops[index] {
                case .equal:
                    break collecting
                case let .delete(line):
                    deletes.append(line)
                    index += 1
                case let .insert(line):
                    inserts.append(line)
                    index += 1
                }
            }
            let paired = min(deletes.count, inserts.count)
            for k in 0 ..< paired {
                let segments = characterDiff(deletes[k], inserts[k])
                rows.append(SideBySideRow(
                    kind: .changed,
                    left: deletes[k],
                    right: inserts[k],
                    leftSegments: segments.filter { $0.kind != .inserted },
                    rightSegments: segments.filter { $0.kind != .deleted }
                ))
            }
            for k in paired ..< deletes.count {
                rows.append(SideBySideRow(kind: .removedLeft, left: deletes[k], right: nil))
            }
            for k in paired ..< inserts.count {
                rows.append(SideBySideRow(kind: .addedRight, left: nil, right: inserts[k]))
            }
        }
        return rows
    }

    // MARK: - Character-level diff (intra-line highlight)

    /// Character-level diff of two lines, adjacent same-kind runs coalesced into segments.
    public func characterDiff(_ a: String, _ b: String) -> [InlineSegment] {
        let ops = LCS.diff(Array(a), Array(b))
        var segments: [InlineSegment] = []
        for op in ops {
            let (kind, character): (InlineSegment.Kind, Character)
            switch op {
            case let .equal(char): (kind, character) = (.equal, char)
            case let .delete(char): (kind, character) = (.deleted, char)
            case let .insert(char): (kind, character) = (.inserted, char)
            }
            if var last = segments.last, last.kind == kind {
                last.text.append(character)
                segments[segments.count - 1] = last
            } else {
                segments.append(InlineSegment(kind: kind, text: String(character)))
            }
        }
        return segments
    }

    // MARK: - 3-way merge

    private enum AutoSide { case mine, theirs }

    /// 3-way merge into blocks. When `base` shows exactly one side changed, that side's edits
    /// are labelled auto-resolvable (`mineOnly` / `theirsOnly`); otherwise divergent regions
    /// are `conflict`. With no `base`, every divergence is classified from the two-way diff.
    public func merge(base: String?, mine: String, theirs: String) -> [MergeBlock] {
        let mineLines = mine.splitIntoLines()
        let theirsLines = theirs.splitIntoLines()
        let auto = autoSide(base: base, mineLines: mineLines, theirsLines: theirsLines)

        var blocks: [MergeBlock] = []
        let ops = LCS.diff(mineLines, theirsLines)
        var index = 0
        while index < ops.count {
            if case .equal = ops[index] {
                var run: [String] = []
                while index < ops.count, case let .equal(line) = ops[index] {
                    run.append(line)
                    index += 1
                }
                blocks.append(.unchanged(run))
                continue
            }
            let (deletes, inserts) = collectDivergence(ops, from: &index)
            blocks.append(divergenceBlock(deletes: deletes, inserts: inserts, auto: auto))
        }
        return blocks
    }

    /// When `base` shows exactly one side changed, that side's edits can be auto-resolved.
    private func autoSide(base: String?, mineLines: [String], theirsLines: [String]) -> AutoSide? {
        guard let base else { return nil }
        let baseLines = base.splitIntoLines()
        if mineLines == baseLines, theirsLines != baseLines { return .theirs }
        if theirsLines == baseLines, mineLines != baseLines { return .mine }
        return nil
    }

    /// Consumes the contiguous non-equal run starting at `index`, returning its two sides.
    private func collectDivergence(_ ops: [Change<String>], from index: inout Int) -> (deletes: [String], inserts: [String]) {
        var deletes: [String] = []
        var inserts: [String] = []
        collecting: while index < ops.count {
            switch ops[index] {
            case .equal:
                break collecting
            case let .delete(line):
                deletes.append(line)
                index += 1
            case let .insert(line):
                inserts.append(line)
                index += 1
            }
        }
        return (deletes, inserts)
    }

    /// Classifies one divergent run into an auto-resolvable side or a conflict block.
    private func divergenceBlock(deletes: [String], inserts: [String], auto: AutoSide?) -> MergeBlock {
        switch auto {
        case .mine:
            return .mineOnly(deletes)
        case .theirs:
            return .theirsOnly(inserts)
        case nil:
            if inserts.isEmpty { return .mineOnly(deletes) }
            if deletes.isEmpty { return .theirsOnly(inserts) }
            return .conflict(mine: deletes, theirs: inserts)
        }
    }
}
