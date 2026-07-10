import DevNotesCore
import SwiftUI

/// The collapsible left panel: search bar over the modified-date-sorted file list. Toggling the
/// panel is bound to ⌘B by the root view.
struct SidebarView: View {
    @Bindable var model: AppModel

    /// Base file-name point size (one point larger than the previous `.body`). Fixed — the ⌘+/⌘-
    /// zoom scales only the editor content area, never this file list. Platform bodies differ, so
    /// the baseline does too.
    private var titleFontSize: CGFloat {
        #if os(macOS)
        return 14
        #else
        return 18
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(model: model)
            Divider()
            List(selection: Binding(
                get: { model.selectedID },
                set: { id in if let id { Task { await model.select(id) } } }
            )) {
                ForEach(model.visibleSummaries) { summary in
                    HStack(spacing: 6) {
                        if model.isPinned(summary.id) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        // File name only — the modified date is no longer shown in the list.
                        Text(summary.title)
                            .font(.system(size: titleFontSize, weight: .bold))
                            .lineLimit(1)
                    }
                    .tag(summary.id)
                    .contextMenu {
                        Button(model.isPinned(summary.id) ? "Unpin" : "Pin to Top",
                               systemImage: model.isPinned(summary.id) ? "pin.slash" : "pin") {
                            model.togglePin(summary.id)
                        }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await model.delete(summary.id) }
                        }
                    }
                }
                // Drag to re-order pinned notes. The model ignores moves that fall outside the
                // pinned group, so only pins are reorderable.
                .onMove { source, destination in
                    model.movePinned(from: source, to: destination)
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
