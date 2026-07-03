#if os(macOS)
import AppKit
import SwiftUI

/// Menu-bar commands: File → export, View → wrap/line-numbers/theme/sidebar, and a Help link to
/// the project on GitHub. All state lives on `AppModel`, so menus, the toolbar, and Settings stay
/// in sync.
struct AppCommands: Commands {
    @Bindable var model: AppModel

    private static let repositoryURL = URL(string: "https://github.com/jsglazer/DevNotes")!

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Export as Markdown…") { Exporter.exportMarkdown(model: model) }
                .disabled(model.selectedID == nil)
            Button("Export as Plain Text…") { Exporter.exportText(model: model) }
                .disabled(model.selectedID == nil)
            Button("Save as PDF…") { Exporter.exportPDF(model: model) }
                .disabled(model.selectedID == nil)
        }

        CommandGroup(after: .sidebar) {
            Button(model.columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar") {
                model.toggleSidebar()
            }
            .keyboardShortcut("b", modifiers: .command)

            Divider()

            Toggle("Wrap Text", isOn: $model.wrapText)
            Toggle("Show Line Numbers", isOn: $model.showLineNumbers)

            Picker("Theme", selection: $model.theme) {
                Text("System").tag(AppTheme.system)
                Text("Light").tag(AppTheme.light)
                Text("Dark").tag(AppTheme.dark)
            }
        }

        CommandGroup(replacing: .help) {
            Button("DevNotes on GitHub") {
                NSWorkspace.shared.open(Self.repositoryURL)
            }
        }
    }
}
#endif
