import DevNotesCore
import DevStyleKit
import SwiftUI

/// The search bar above the file list: query field plus regex / whole-word / case-sensitive
/// toggles. It only mutates `AppModel` search state; filtering happens in pure Core.
struct SearchBarView: View {
    /// The DevStyle profile for the current light/dark appearance.
    @Environment(\.dsTheme) private var dsTheme

    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            TextField("Search", text: $model.searchQuery)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .overlay(alignment: .trailing) {
                    if !model.searchQuery.isEmpty {
                        Button {
                            model.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(dsTheme.surface(.muted))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 6)
                        .help("Clear search")
                    }
                }

            HStack(spacing: 4) {
                toggle(".*", isOn: $model.searchOptions.isRegex, help: "Regular expression")
                toggle("W", isOn: $model.searchOptions.wholeWord, help: "Whole word")
                toggle("Aa", isOn: $model.searchOptions.caseSensitive, help: "Case sensitive")
                Spacer()
            }
            .font(.caption.monospaced())
        }
        .padding(8)
    }

    private func toggle(_ label: String, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isOn.wrappedValue ? dsTheme.surface(.accent).opacity(0.3) : dsTheme.surface(.border).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
