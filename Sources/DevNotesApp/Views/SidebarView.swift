import DevNotesCore
import SwiftUI

/// The collapsible left panel: search bar over the modified-date-sorted file list. Toggling the
/// panel is bound to ⌘B by the root view.
struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(model: model)
            Divider()
            List(selection: Binding(
                get: { model.selectedID },
                set: { id in if let id { Task { await model.select(id) } } }
            )) {
                ForEach(model.visibleSummaries) { summary in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(summary.modifiedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(summary.id)
                }
            }
            .listStyle(.sidebar)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.newNote() }
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
