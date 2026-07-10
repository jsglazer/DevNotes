import DevNotesCore
import SwiftUI

/// Root layout.
/// - macOS: collapsible sidebar (⌘B) + editor pane, conflict merge surfaced as a sheet.
/// - iOS: single-pane editor with a floating top bar; the note list and outline tools are
///   presented as sheets rather than a split view, since NavigationSplitView's compact-width
///   collapse behaviour doesn't give a usable phone layout for this app.
struct ContentView: View {
    @Bindable var model: AppModel
    #if os(iOS)
    @State private var isNotesListPresented = false
    @State private var isSettingsPresented = false
    #endif

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    #if os(macOS)
    private var macBody: some View {
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
            ToolbarItem(placement: .primaryAction) {
                Text(AppVersion.display)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
    #else
    private var iosBody: some View {
        EditorPane(model: model)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        if model.selectedID != nil {
                            Text(model.activeTitle.isEmpty ? "Untitled" : model.activeTitle)
                                .font(.headline.bold())
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(AppVersion.display)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    IOSTopBar(
                        editor: model.editor,
                        onShowNotes: { isNotesListPresented = true },
                        onNewNote: { Task { await model.newNote() } }
                    )
                }
                .background(.bar)
            }
            .toolbar {
                // A key at the bottom-right of the keyboard accessory bar to dismiss the keyboard.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                        )
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
            }
            .sheet(isPresented: $isNotesListPresented) {
                NavigationStack {
                    SidebarView(model: model)
                        .navigationTitle("Notes")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    isSettingsPresented = true
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isNotesListPresented = false }
                            }
                        }
                        .sheet(isPresented: $isSettingsPresented) {
                            NavigationStack {
                                SettingsView(model: model)
                                    .navigationTitle("Settings")
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbar {
                                        ToolbarItem(placement: .confirmationAction) {
                                            Button("Done") { isSettingsPresented = false }
                                        }
                                    }
                            }
                        }
                }
            }
            .onChange(of: model.selectedID) { _, _ in isNotesListPresented = false }
            .task {
                await model.bootstrap()
                await model.startSyncIfNeeded()
            }
            .sheet(item: firstConflict) { conflict in
                MergeView(conflict: conflict) { mergedBody in
                    Task { await model.resolveConflict(conflict.id, mergedBody: mergedBody) }
                }
            }
            .preferredColorScheme(model.theme.colorScheme)
    }
    #endif

    private var firstConflict: Binding<ConflictRecord?> {
        Binding(
            get: { model.conflicts.first },
            set: { _ in }
        )
    }
}

#if os(iOS)
/// The floating top bar for the iOS editor screen: note-list + new-note circles on the left,
/// a heading/search pill in the center, and outline-tool access on the right — DevNotes'
/// equivalent of the reference app's toolbar, mapped onto this app's actual feature set (no
/// tags exist in DevNotesCore, so there's no tag row here).
private struct IOSTopBar: View {
    var editor: EditorViewModel
    var onShowNotes: () -> Void
    var onNewNote: () -> Void

    var body: some View {
        // Sizes are ~20% larger than the original bar so the controls are easier to hit on a phone.
        HStack(spacing: 14) {
            circleButton("doc.text", action: onShowNotes)
            circleButton("plus", action: onNewNote)
            Spacer()
            HStack(spacing: 22) {
                Menu {
                    ForEach(0 ... 3, id: \.self) { level in
                        Button(level == 0 ? "Body" : "Heading \(level)") { editor.setHeading(level) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                Button(action: onShowNotes) {
                    Image(systemName: "magnifyingglass")
                    // Search lives inside the notes-list sheet; this jumps straight there.
                }
            }
            .font(.system(size: 19, weight: .medium))
            .padding(.horizontal, 19)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.gray.opacity(0.15)))
            Spacer()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func circleButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 53, height: 53)
                .background(Circle().fill(Color.gray.opacity(0.15)))
        }
    }
}
#endif
