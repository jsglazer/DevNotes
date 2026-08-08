import DevNotesCore
import SwiftUI

/// Collapsible hierarchical heading outline of the currently open note, shown below the file list
/// when toggled from the sidebar toolbar. Clicking a heading moves the caret to that line.
struct OutlinePanelView: View {
    @Bindable var model: AppModel
    @State private var collapsedIDs: Set<Int> = []

    private var headings: [OutlineHeading] {
        guard model.selectedID != nil else { return [] }
        return HeadingOutline.extract(from: model.editor.text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if headings.isEmpty {
                    Text(model.selectedID == nil ? "No note open" : "No headings in this note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                } else {
                    ForEach(headings) { heading in
                        row(for: heading)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Type-erased because this recursively calls itself for `heading.children` — a `some View`
    /// return would otherwise define the opaque type in terms of itself.
    private func row(for heading: OutlineHeading) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if heading.children.isEmpty {
                    Color.clear.frame(width: 12)
                } else {
                    Button {
                        toggle(heading.id)
                    } label: {
                        Image(systemName: collapsedIDs.contains(heading.id) ? "chevron.right" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    model.editor.jump(to: heading.selection)
                    model.editor.requestFocus()
                } label: {
                    Text(heading.text)
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(heading.level - 1) * 12)

            if collapsedIDs.contains(heading.id) == false {
                ForEach(heading.children) { child in
                    row(for: child)
                }
            }
        })
    }

    private func toggle(_ id: Int) {
        if collapsedIDs.contains(id) {
            collapsedIDs.remove(id)
        } else {
            collapsedIDs.insert(id)
        }
    }
}
