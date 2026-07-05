import DevNotesCore
import SwiftUI

/// App entry point. It wires the composition root: a file-backed `NoteRepository` (source of
/// truth) and a lazily-started CloudKit `SyncService`, injected into `AppModel`. No singletons,
/// and nothing on this path touches CloudKit — the container is created only when sync starts,
/// after first paint, protecting the < 1s launch budget.
@main
struct DevNotesApp: App {
    @State private var model: AppModel

    init() {
        let store = FileNoteStore.makeDefault()
        let sync = CloudKitSyncService(
            conflictProvider: { [store] in
                let summaries = (try? await store.summaries()) ?? []
                var captured: [ConflictRecord] = []
                for summary in summaries {
                    if let conflict = await store.captureConflict(for: summary.id) {
                        captured.append(conflict)
                    }
                }
                return captured
            },
            conflictResolver: { [store] id in await store.resolveFileVersionConflict(for: id) }
        )
        _model = State(initialValue: AppModel(repository: store, sync: sync, watchDirectory: store.directory))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        #if os(macOS)
        .commands {
            AppCommands(model: model)
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView(model: model)
        }
        #endif
    }
}
