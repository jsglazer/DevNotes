import DevNotesCore
import SwiftUI

/// The search bar above the file list: query field plus regex / whole-word / case-sensitive
/// toggles. It only mutates `AppModel` search state; filtering happens in pure Core.
struct SearchBarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            TextField("Search", text: $model.searchQuery)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

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
                .background(isOn.wrappedValue ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
