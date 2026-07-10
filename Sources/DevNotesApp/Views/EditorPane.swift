import DevNotesCore
import SwiftUI

/// The main editing pane: outline toolbar over the TextKit 2 editor.
struct EditorPane: View {
    @Bindable var model: AppModel
    /// Resolves the current-line band colour for the active theme (the native editor paints it).
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if model.selectedID == nil {
                ContentUnavailablePlaceholder()
            } else {
                #if os(macOS)
                EditorToolbar(editor: model.editor)
                Divider()
                if model.find.isPresented {
                    FindReplaceBar(model: model)
                    Divider()
                }
                #else
                // iOS keeps the outline formatting tools pinned on-screen (not behind a sheet).
                EditorToolbar(editor: model.editor, iconSize: 20)
                Divider()
                #endif
                MarkdownTextView(
                    text: Binding(get: { model.editor.text }, set: { model.editor.text = $0 }),
                    selection: Binding(get: { model.editor.selection }, set: { model.editor.selection = $0 }),
                    style: model.styleSheet,
                    wrapText: model.wrapText,
                    showLineNumbers: model.showLineNumbers,
                    spellCheck: model.spellCheck,
                    zoom: model.zoom,
                    currentLineHighlight: model.currentLineColor(for: colorScheme),
                    bottomPadding: model.bottomPadding,
                    searchMatches: model.find.isPresented ? model.find.matches : [],
                    currentMatch: model.find.isPresented ? model.find.currentMatch : nil,
                    focusRequest: model.editor.focusRequest,
                    onKeyChord: { chord in
                        guard let action = model.keymap.action(for: chord) else { return false }
                        return model.perform(action)
                    }
                )
            }
        }
    }
}

private struct ContentUnavailablePlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Select or create a note")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
