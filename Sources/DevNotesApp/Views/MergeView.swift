import DevNotesCore
import DevStyleKit
import SwiftUI

/// The visual conflict merge UI. macOS gets a side-by-side comparison; iOS gets an inline
/// highlighted stream — both rendered from the same `DiffMergeEngine`. Choosing a side records
/// the merged body through `AppModel`, so the captured versions are surfaced, never discarded.
struct MergeView: View {
    /// The DevStyle profile for the current light/dark appearance.
    @Environment(\.dsTheme) private var dsTheme

    let conflict: ConflictRecord
    /// The full on-disk path of the conflicted note, or its raw ID when no path is known (an
    /// in-memory repository in tests/previews).
    var filePath: String
    var onResolve: (String) -> Void

    private let engine = DiffMergeEngine()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            #if os(macOS)
            sideBySide
            #else
            inline
            #endif
            Divider()
            actions
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Resolve conflict — \(conflict.id.rawValue)")
                .font(.headline)
            Text(filePath)
                .font(.caption.monospaced())
                .foregroundStyle(dsTheme.surface(.muted))
                .textSelection(.enabled)
            Text("Mine: \(conflict.mine.deviceName) · Theirs: \(conflict.theirs.deviceName)")
                .font(.caption)
                .foregroundStyle(dsTheme.surface(.muted))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    #if os(macOS)
    private var sideBySide: some View {
        let rows = engine.sideBySide(mine: conflict.mine.body, theirs: conflict.theirs.body)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 0) {
                        segmentedCell(row.left, segments: row.leftSegments, side: .left, kind: row.kind)
                        Divider()
                        segmentedCell(row.right, segments: row.rightSegments, side: .right, kind: row.kind)
                    }
                }
            }
        }
    }

    private enum Side { case left, right }

    private func segmentedCell(_ text: String?, segments: [InlineSegment], side: Side, kind: SideBySideRow.Kind) -> some View {
        Group {
            if let text {
                if segments.isEmpty {
                    Text(text.isEmpty ? " " : text)
                } else {
                    highlighted(segments, side: side)
                }
            } else {
                Text(" ")
            }
        }
        .font(.body.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(background(kind: kind, side: side))
    }

    private func highlighted(_ segments: [InlineSegment], side: Side) -> some View {
        segments.reduce(Text("")) { partial, segment in
            let visible = (side == .left && segment.kind == .inserted) || (side == .right && segment.kind == .deleted)
            if visible { return partial }
            var piece = Text(segment.text)
            if segment.kind != .equal {
                piece = piece.bold()
            }
            return partial + piece
        }
    }

    private func background(kind: SideBySideRow.Kind, side: Side) -> Color {
        switch kind {
        case .unchanged: return .clear
        case .changed: return dsTheme.surface(.warning).opacity(0.15)
        case .removedLeft: return side == .left ? dsTheme.surface(.error).opacity(0.15) : .clear
        case .addedRight: return side == .right ? dsTheme.surface(.success).opacity(0.15) : .clear
        }
    }
    #endif

    private var inline: some View {
        let lines = engine.inline(mine: conflict.mine.body, theirs: conflict.theirs.body)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(prefix(line.kind) + line.text)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(inlineBackground(line.kind))
                }
            }
        }
    }

    private func prefix(_ kind: InlineLine.Kind) -> String {
        switch kind {
        case .unchanged: return "  "
        case .removed: return "- "
        case .added: return "+ "
        }
    }

    private func inlineBackground(_ kind: InlineLine.Kind) -> Color {
        switch kind {
        case .unchanged: return .clear
        case .removed: return dsTheme.surface(.error).opacity(0.15)
        case .added: return dsTheme.surface(.success).opacity(0.15)
        }
    }

    private var actions: some View {
        HStack {
            Button("Keep Mine") { onResolve(conflict.mine.body) }
            Button("Keep Theirs") { onResolve(conflict.theirs.body) }
            Spacer()
        }
        .padding(8)
    }
}
