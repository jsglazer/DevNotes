import DevNotesCore
import SwiftUI

/// The main editing pane: outline toolbar over the TextKit 2 editor.
struct EditorPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.selectedID == nil {
                ContentUnavailablePlaceholder()
            } else {
                EditorToolbar(editor: model.editor)
                Divider()
                MarkdownTextView(
                    text: Binding(get: { model.editor.text }, set: { model.editor.text = $0 }),
                    selection: Binding(get: { model.editor.selection }, set: { model.editor.selection = $0 }),
                    style: model.styleSheet,
                    wrapText: model.wrapText,
                    showLineNumbers: model.showLineNumbers
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
