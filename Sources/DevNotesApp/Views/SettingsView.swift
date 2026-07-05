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

    var body: some View {
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

                TextEditor(text: $model.styleInput)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
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
        .padding()
        .frame(minWidth: 420, minHeight: 360)
    }
}
