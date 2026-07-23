import DevNotesCore
import SwiftUI

/// Outline actions for the editor. Every button routes through the pure `OutlineEngine` via
/// `EditorViewModel`; the toolbar itself contains no text-manipulation logic.
struct EditorToolbar: View {
    var editor: EditorViewModel
    /// Icon point size. iOS passes a larger value (~20% up) so the pinned tools are comfortably
    /// tappable; macOS uses the system default.
    var iconSize: CGFloat?
    /// Whether the "Highlight Similar" toggle is currently active.
    var isHighlightSimilarActive: Bool
    var onToggleHighlightSimilar: () -> Void
    /// Mobile-only extras (nil hides the button): insert date/time, undo, and zoom. iOS has no
    /// menu bar or ⌘-shortcuts, so these actions need on-screen buttons.
    var onInsertDateTime: (() -> Void)?
    var onUndo: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onZoomIn: (() -> Void)?

    var body: some View {
        // The iOS button row (larger icons + extra tools) outgrows an iPhone's width, so it
        // scrolls horizontally; macOS keeps the fixed row.
        if iconSize == nil {
            content
        } else {
            ScrollView(.horizontal, showsIndicators: false) { content }
        }
    }

    private var content: some View {
        HStack(spacing: iconSize == nil ? 12 : 18) {
            button("list.bullet", "Bullet List") { editor.run(.toggleBullet) }
            button("list.number", "Numbered List") { editor.run(.toggleNumber) }
            Divider().frame(height: 16)
            button("decrease.indent", "Outdent") { editor.run(.outdent) }
            button("increase.indent", "Indent") { editor.run(.indent) }
            Divider().frame(height: 16)
            button("arrow.up", "Move Line Up") { editor.run(.moveLineUp) }
            button("arrow.down", "Move Line Down") { editor.run(.moveLineDown) }
            Divider().frame(height: 16)
            Menu {
                ForEach(0 ... 3, id: \.self) { level in
                    Button(level == 0 ? "Body" : "Heading \(level)") { editor.setHeading(level) }
                }
            } label: {
                Label("Heading", systemImage: "textformat.size")
                    .font(iconSize.map { .system(size: $0) })
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Divider().frame(height: 16)
            toggleButton("highlighter", "Highlight Similar", isOn: isHighlightSimilarActive, action: onToggleHighlightSimilar)
            if onUndo != nil || onInsertDateTime != nil || onZoomOut != nil || onZoomIn != nil {
                Divider().frame(height: 16)
            }
            if let onUndo {
                button("arrow.uturn.backward", "Undo", action: onUndo)
            }
            if let onInsertDateTime {
                button("calendar.badge.clock", "Insert Date & Time", action: onInsertDateTime)
            }
            if let onZoomOut {
                button("minus.magnifyingglass", "Zoom Out", action: onZoomOut)
            }
            if let onZoomIn {
                button("plus.magnifyingglass", "Zoom In", action: onZoomIn)
            }
            Spacer()
        }
        .padding(.horizontal, iconSize == nil ? 8 : 12)
        .padding(.vertical, iconSize == nil ? 6 : 8)
    }

    private func button(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(iconSize.map { .system(size: $0) })
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    /// Same as `button`, but tints the glyph while `isOn` so an active toggle (Highlight Similar)
    /// reads differently from the momentary outline actions around it.
    private func toggleButton(_ systemImage: String, _ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(iconSize.map { .system(size: $0) })
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}
