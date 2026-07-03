import DevNotesCore
import SwiftUI

/// Root layout: collapsible sidebar (⌘B) + editor pane, with the conflict merge surfaced as a
/// sheet when sync reports one.
struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
        } detail: {
            EditorPane(model: model)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    withAnimation { model.toggleSidebar() }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                // ⌘B is owned by the View-menu command so the shortcut isn't double-bound.
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
}
