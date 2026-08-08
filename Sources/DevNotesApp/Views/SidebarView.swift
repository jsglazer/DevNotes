import DevNotesCore
import SwiftUI

/// The collapsible left panel: search bar over the modified-date-sorted file list, with an optional
/// heading-outline panel below it (`model.isOutlineVisible`, toggled from `EditorToolbar`). The
/// sidebar itself collapses via ⌘B, bound by the root view.
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

    /// Whether the search bar has an active query — while true, the file list is replaced by a
    /// per-occurrence breakdown instead of a plain filtered list of names.
    private var isSearching: Bool {
        model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(model: model)
            Divider()
            List(selection: Binding(
                get: { model.selectedID },
                set: { id in if let id { Task { await model.select(id) } } }
            )) {
                if isSearching {
                    ForEach(model.visibleSummaries) { summary in
                        searchResultSection(for: summary)
                    }
                } else {
                    ForEach(model.visibleSummaries) { summary in
                        fileRow(for: summary)
                    }
                    // Drag to re-order pinned notes. The model ignores moves that fall outside the
                    // pinned group, so only pins are reorderable.
                    .onMove { source, destination in
                        model.movePinned(from: source, to: destination)
                    }
                }
            }
            .listStyle(.sidebar)

            if model.isOutlineVisible {
                Divider()
                OutlinePanelView(model: model)
                    .frame(maxHeight: 220)
            }
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

    // MARK: - Plain file list (no active search)

    private func fileRow(for summary: NoteSummary) -> some View {
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
            pinButton(for: summary.id)
            Divider()
            deleteButton(for: summary.id)
        }
    }

    // MARK: - Search results (bold file name + one row per occurrence)

    private func searchResultSection(for summary: NoteSummary) -> some View {
        Section {
            let items = occurrences(for: summary)
            if items.isEmpty {
                Button {
                    Task { await model.select(summary.id) }
                } label: {
                    Text("Open note (title match)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(items) { occurrence in
                    occurrenceRow(id: summary.id, occurrence: occurrence)
                }
            }
        } header: {
            HStack(spacing: 6) {
                if model.isPinned(summary.id) {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(summary.title)
                    .font(.system(size: titleFontSize, weight: .bold))
                    .lineLimit(1)
            }
            .contextMenu {
                pinButton(for: summary.id)
                Divider()
                deleteButton(for: summary.id)
            }
        }
    }

    private func occurrenceRow(id: NoteID, occurrence: SearchOccurrence) -> some View {
        Button {
            Task { await openOccurrence(id, occurrence) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(occurrence.lineNumber)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20, alignment: .trailing)
                Text(occurrence.snippet)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func occurrences(for summary: NoteSummary) -> [SearchOccurrence] {
        SearchEngine.occurrences(in: summary.body, query: model.searchQuery, options: model.searchOptions)
    }

    /// Opens `id` (if not already open) and jumps the caret to this specific occurrence — the note
    /// may already be open at a different match (or a different caret position entirely), so the
    /// jump always happens explicitly rather than relying on whatever `select` lands on by default.
    private func openOccurrence(_ id: NoteID, _ occurrence: SearchOccurrence) async {
        await model.select(id)
        model.editor.jump(to: occurrence.selection)
        model.editor.requestFocus()
    }

    // MARK: - Shared context menu actions

    private func pinButton(for id: NoteID) -> some View {
        Button(model.isPinned(id) ? "Unpin" : "Pin to Top",
               systemImage: model.isPinned(id) ? "pin.slash" : "pin") {
            model.togglePin(id)
        }
    }

    private func deleteButton(for id: NoteID) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            Task { await model.delete(id) }
        }
    }
}
