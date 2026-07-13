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
                EditorToolbar(
                    editor: model.editor,
                    isHighlightSimilarActive: model.highlightSimilarActive,
                    onToggleHighlightSimilar: model.toggleHighlightSimilar
                )
                Divider()
                if model.find.isPresented {
                    FindReplaceBar(model: model)
                    Divider()
                }
                #else
                // iOS keeps the outline formatting tools pinned on-screen (not behind a sheet).
                EditorToolbar(
                    editor: model.editor,
                    iconSize: 20,
                    isHighlightSimilarActive: model.highlightSimilarActive,
                    onToggleHighlightSimilar: model.toggleHighlightSimilar
                )
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
                    similarMatches: model.similarMatches,
                    similarHighlightColor: model.similarHighlightColor,
                    focusRequest: model.editor.focusRequest,
                    loadGeneration: model.editor.loadGeneration,
                    onKeyChord: { chord in
                        guard let action = model.keymap.action(for: chord) else { return false }
                        return model.perform(action)
                    }
                )
                Divider()
                EditorStatusBar(text: model.editor.text)
            }
        }
    }
}

/// The bottom counter strip: live word + line totals for the open note, mirroring the top outline
/// toolbar's inset/divider layout. Counts come from the pure `TextStats`; this view holds no logic.
private struct EditorStatusBar: View {
    var text: String

    var body: some View {
        let stats = DevNotesCore.TextStats(text)
        HStack(spacing: 14) {
            Spacer()
            Text("\(stats.words) \(stats.words == 1 ? "word" : "words")")
            Text("\(stats.lines) \(stats.lines == 1 ? "line" : "lines")")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
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
