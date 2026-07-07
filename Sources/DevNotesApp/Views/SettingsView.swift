import DevNotesCore
import SwiftUI

/// Settings: theme toggle, open-jump behaviour, and the bounded "custom CSS" token editor. Input
/// is sanitised live by `StyleSanitizer`; rejected declarations are shown so the user sees exactly
/// what was ignored.
struct SettingsView: View {
    @Bindable var model: AppModel

    /// A short, copy-pasteable stylesheet shown in the panel and inserted by the button.
    private static let exampleStyle = """
    font-family: Menlo
    font-size: 15
    text-color: #e0e0e0
    line-spacing: 4
    heading-color: #3b82f6
    """

    /// Live sample of the current date format, so the user sees what ⌃⌥D will insert.
    private var dateTimePreview: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = model.dateFormat
        return formatter.string(from: Date())
    }

    var body: some View {
        // Tabbed so each pane fits without the whole sheet needing to scroll — the tall "Editor
        // Style" input and the long shortcut list each get their own scroll space, and the style
        // input no longer grows past the pane (which used to steal focus while typing).
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            shortcutsTab
                .tabItem { Label("Keyboard Shortcuts", systemImage: "keyboard") }
            editorStyleTab
                .tabItem { Label("Editor Style", systemImage: "paintbrush") }
        }
        #if os(macOS)
        .frame(width: 500, height: 460)
        #endif
    }

    private var generalTab: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $model.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.rawValue.capitalized).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Editor") {
                Toggle("Wrap text", isOn: $model.wrapText)
                Toggle("Show line numbers", isOn: $model.showLineNumbers)
                Toggle("Check spelling while typing", isOn: $model.spellCheck)

                Stepper(
                    "Bottom padding: \(Int(model.bottomPadding)) pt",
                    value: $model.bottomPadding,
                    in: 0 ... 600,
                    step: 20
                )
                Text("Blank space kept below the last line so the caret never sits against the window's bottom edge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Insert Date & Time") {
                TextField("Format", text: $model.dateFormat)
                    .font(.body.monospaced())
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
                Text("Preview: \(dateTimePreview)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Inserted at the caret by the Insert Date & Time shortcut. Uses DateFormatter patterns (yyyy=year, MM=month, dd=day, HH=hour, mm=minute, ss=second).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("On Open") {
                Picker("Jump to", selection: $model.openJump) {
                    Text("First line").tag(OpenJump.firstLine)
                    Text("Last line").tag(OpenJump.lastLine)
                }
                .pickerStyle(.segmented)
                Text("Where the caret lands when you open a note.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTab: some View {
        Form {
            Section("Keyboard Shortcuts") {
                Text(
                    "Every bindable function and its current shortcut. Edit them in "
                        + "`~/.config/devnotes/keymap.json` (created on first launch); changes take effect "
                        + "next launch."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(KeymapAction.allCases, id: \.self) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        Text(model.keymap.chord(for: action)?.displaySymbols ?? "—")
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if model.keymapWarnings.isEmpty == false {
                    ForEach(Array(model.keymapWarnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var editorStyleTab: some View {
        Form {
            Section("Editor Style") {
                Text(
                    "Style the editor with one `token: value` per line. Only the tokens below are honoured "
                        + "— anything else is safely ignored (never executed as CSS). See the README for the "
                        + "full catalog and more examples."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Supported tokens: \(StyleTokenKey.allCases.map(\.rawValue).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Fixed height (scrolls internally): a growing TextEditor here used to push past the
                // pane and drop first-responder mid-keystroke. A bounded box never re-lays-out the
                // ancestor, so typing stays put.
                TextEditor(text: $model.styleInput)
                    .font(.body.monospaced())
                    .frame(height: 160)
                    .scrollContentBackground(.hidden)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                    )
                    .onChange(of: model.styleInput) {
                        model.editor.style = model.styleSheet
                    }

                // One worked example, right below the input box, with a one-tap insert.
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Example")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Insert Example") { model.styleInput = Self.exampleStyle }
                            .font(.caption)
                            #if os(macOS)
                            .buttonStyle(.link)
                            #else
                            .buttonStyle(.borderless)
                            #endif
                    }
                    Text(Self.exampleStyle)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }

                let sheet = model.styleSheet
                if sheet.rejected.isEmpty == false {
                    ForEach(Array(sheet.rejected.enumerated()), id: \.offset) { _, rejected in
                        Label("\(rejected.raw) — \(rejected.reason)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
