import DevNotesCore
import DevStyleKit
import SwiftUI

/// The main editing pane: outline toolbar over the TextKit 2 editor.
struct EditorPane: View {
    @Bindable var model: AppModel
    /// Resolves the current-line band colour for the active theme (the native editor paints it).
    @Environment(\.colorScheme) private var colorScheme
    /// The DevStyle profile for the current light/dark appearance (`.devStyle(store)` at the root).
    @Environment(\.dsTheme) private var dsTheme

    var body: some View {
        let palette = EditorPalette(theme: dsTheme)
        VStack(spacing: 0) {
            if model.selectedID == nil {
                ContentUnavailablePlaceholder()
            } else {
                #if os(macOS)
                EditorToolbar(
                    editor: model.editor,
                    isHighlightSimilarActive: model.highlightSimilarActive,
                    onToggleHighlightSimilar: model.toggleHighlightSimilar,
                    isOutlineVisible: model.isOutlineVisible,
                    onToggleOutline: { model.isOutlineVisible.toggle() },
                    onExportPDF: { Exporter.exportPDF(model: model) },
                    onCreateBackup: { Exporter.exportBackup(model: model) }
                )
                .background(dsTheme.surface(.panel))
                Divider()
                if model.find.isPresented {
                    FindReplaceBar(model: model)
                    Divider()
                }
                #else
                // iOS keeps the outline formatting tools pinned on-screen (not behind a sheet),
                // plus the actions that have no menu bar to live in: undo, date/time, and zoom.
                EditorToolbar(
                    editor: model.editor,
                    iconSize: 20,
                    isHighlightSimilarActive: model.highlightSimilarActive,
                    onToggleHighlightSimilar: model.toggleHighlightSimilar,
                    isOutlineVisible: model.isOutlineVisible,
                    onToggleOutline: { model.isOutlineVisible.toggle() },
                    onInsertDateTime: model.insertDateTime,
                    onUndo: model.editor.requestUndo,
                    onZoomOut: model.zoomOut,
                    onZoomIn: model.zoomIn
                )
                .background(dsTheme.surface(.panel))
                Divider()
                #endif
                MarkdownTextView(
                    text: Binding(get: { model.editor.text }, set: { model.editor.text = $0 }),
                    selection: Binding(get: { model.editor.selection }, set: { model.editor.selection = $0 }),
                    style: model.styleSheet,
                    palette: palette,
                    wrapText: model.wrapText,
                    showLineNumbers: model.showLineNumbers,
                    spellCheck: model.spellCheck,
                    zoom: model.zoom,
                    currentLineHighlight: model.currentLineColor(for: colorScheme, palette: palette),
                    bottomPadding: model.bottomPadding,
                    searchMatches: model.find.isPresented ? model.find.matches : [],
                    currentMatch: model.find.isPresented ? model.find.currentMatch : nil,
                    similarMatches: model.similarMatches,
                    similarHighlightColor: model.similarHighlightColor(for: colorScheme, palette: palette),
                    focusRequest: model.editor.focusRequest,
                    undoRequest: model.editor.undoRequest,
                    scrollRequest: model.editor.scrollRequest,
                    loadGeneration: model.editor.loadGeneration,
                    openLinksOnLongPress: model.openLinksOnLongPress,
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
    @Environment(\.dsTheme) private var dsTheme

    var body: some View {
        let stats = DevNotesCore.TextStats(text)
        HStack(spacing: 14) {
            // App version, bottom-left (moved here from the top bar / window toolbar).
            Text(AppVersion.display)
            Spacer()
            Text("\(stats.words) \(stats.words == 1 ? "word" : "words")")
            Text("\(stats.lines) \(stats.lines == 1 ? "line" : "lines")")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(dsTheme.surface(.muted))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(dsTheme.surface(.panel))
    }
}

private struct ContentUnavailablePlaceholder: View {
    @Environment(\.dsTheme) private var dsTheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundStyle(dsTheme.surface(.muted))
            Text("Select or create a note")
                .foregroundStyle(dsTheme.surface(.muted))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dsTheme.color("editor-bg"))
    }
}
