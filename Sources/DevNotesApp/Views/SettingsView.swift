import DevNotesCore
import SwiftUI

/// Settings: theme toggle and the bounded "custom CSS" token editor. Input is sanitised live by
/// `StyleSanitizer`; rejected declarations are shown so the user sees exactly what was ignored.
struct SettingsView: View {
    @Bindable var model: AppModel

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

            Section("Editor Style") {
                Text("Supported tokens: \(StyleTokenKey.allCases.map(\.rawValue).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.styleInput)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .onChange(of: model.styleInput) {
                        model.editor.style = model.styleSheet
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
