#if os(macOS)
import AppKit
import DevNotesCore
import SwiftUI

/// Menu-bar commands: File → export, Edit → move line, View → wrap/line-numbers/spell-check/theme/
/// sidebar/navigation, and a Help link to the project on GitHub. All state lives on `AppModel`, so
/// menus, the toolbar, and Settings stay in sync. Every shortcut here is resolved from the user's
/// `keymap.json` (via `model.keymap`) rather than hard-coded, so a rebind in that file moves the
/// menu shortcut too.
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

        // Move-line lives in the Edit menu, next to the other text-editing actions.
        CommandGroup(after: .pasteboard) {
            Divider()
            menuButton("Move Line Up", .moveLineUp)
            menuButton("Move Line Down", .moveLineDown)
            Divider()
            menuButton("Insert Date & Time", .insertDateTime)
                .disabled(model.selectedID == nil)
        }

        // Find/Replace over the open note. Standard macOS shortcuts (⌘F / ⌘⌥F / ⌘G / ⇧⌘G).
        CommandGroup(after: .textEditing) {
            Button("Find…") { model.openFind(replace: false) }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(model.selectedID == nil)
            Button("Find and Replace…") { model.openFind(replace: true) }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(model.selectedID == nil)
            Button("Find Next") { model.findNext() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(model.find.matches.isEmpty)
            Button("Find Previous") { model.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(model.find.matches.isEmpty)
        }

        CommandGroup(after: .sidebar) {
            Button(model.columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar") {
                model.toggleSidebar()
            }
            .keyboardShortcut("b", modifiers: .command)

            Divider()

            menuButton("Previous Note", .previousNote)
            menuButton("Next Note", .nextNote)

            Divider()

            Toggle("Wrap Text", isOn: $model.wrapText)
                .keyboardShortcut(shortcut(.wrapText))
            Toggle("Show Line Numbers", isOn: $model.showLineNumbers)
                .keyboardShortcut(shortcut(.showLineNumbers))
            Toggle("Check Spelling While Typing", isOn: $model.spellCheck)

            Picker("Theme", selection: $model.theme) {
                Text("System").tag(AppTheme.system)
                Text("Light").tag(AppTheme.light)
                Text("Dark").tag(AppTheme.dark)
            }

            Divider()

            // Text zoom for the editor + sidebar. ⌘+ / ⌘- / ⌘0, the usual document-zoom keys.
            Button("Zoom In") { model.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { model.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { model.zoomReset() }
                .keyboardShortcut("0", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("DevNotes on GitHub") {
                NSWorkspace.shared.open(Self.repositoryURL)
            }
        }
    }

    /// A menu button that runs a keymap action and carries that action's current shortcut.
    private func menuButton(_ title: String, _ action: KeymapAction) -> some View {
        Button(title) { model.perform(action) }
            .keyboardShortcut(shortcut(action))
    }

    /// The SwiftUI shortcut for an action, resolved from the live keymap (falling back to the
    /// built-in default if the user's file somehow lacks a binding).
    private func shortcut(_ action: KeymapAction) -> KeyboardShortcut {
        let chord = model.keymap.chord(for: action) ?? Keymap.defaults.chord(for: action)
        return chord?.keyboardShortcut ?? KeyboardShortcut(KeyEquivalent(" "))
    }
}

extension KeyChord {
    /// AppKit/SwiftUI shortcut for this chord, or nil if the key has no `KeyEquivalent`.
    var keyboardShortcut: KeyboardShortcut? {
        KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    var eventModifiers: EventModifiers {
        var mods: EventModifiers = []
        if modifiers.contains(.command) { mods.insert(.command) }
        if modifiers.contains(.option) { mods.insert(.option) }
        if modifiers.contains(.control) { mods.insert(.control) }
        if modifiers.contains(.shift) { mods.insert(.shift) }
        return mods
    }

    var keyEquivalent: KeyEquivalent {
        switch key {
        case "up": return .upArrow
        case "down": return .downArrow
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "tab": return .tab
        case "return": return .return
        case "space": return .space
        case "escape": return .escape
        case "delete": return .delete
        default: return KeyEquivalent(key.first ?? " ")
        }
    }
}
#endif
