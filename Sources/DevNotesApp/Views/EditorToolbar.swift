import DevNotesCore
import SwiftUI

/// Outline actions for the editor. Every button routes through the pure `OutlineEngine` via
/// `EditorViewModel`; the toolbar itself contains no text-manipulation logic.
struct EditorToolbar: View {
    var editor: EditorViewModel

    var body: some View {
        HStack(spacing: 12) {
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
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func button(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}
