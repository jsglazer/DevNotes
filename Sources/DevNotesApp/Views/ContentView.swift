import DevNotesCore
import SwiftUI

/// Root layout: collapsible sidebar (⌘B) + editor pane, with the conflict merge surfaced as a
/// sheet when sync reports one.
struct ContentView: View {
    @Bindable var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
        } detail: {
            EditorPane(model: model)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    withAnimation { toggleSidebar() }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .keyboardShortcut("b", modifiers: .command)
            }
        }
        .task {
            await model.bootstrap()
            // Sync is started only AFTER the first paint / file list — off the launch path.
            await model.startSyncIfNeeded()
        }
        .sheet(item: firstConflict) { conflict in
            MergeView(conflict: conflict) { mergedBody in
                Task { await model.resolveConflict(conflict.id, mergedBody: mergedBody) }
            }
            .frame(minWidth: 640, minHeight: 420)
        }
        .preferredColorScheme(model.theme.colorScheme)
    }

    private var firstConflict: Binding<ConflictRecord?> {
        Binding(
            get: { model.conflicts.first },
            set: { _ in }
        )
    }

    private func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }
}
