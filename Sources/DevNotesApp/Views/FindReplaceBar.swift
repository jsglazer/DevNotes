#if os(macOS)
import DevNotesCore
import SwiftUI

/// The Sublime-style Find/Replace bar shown over the editor (⌘F / ⌘⌥F). Find row: query field,
/// regex / whole-word / case toggles, a "3 of 12" counter, prev/next, and a replace-row toggle.
/// Replace row (when shown): replacement field, Replace, and Replace All. All matching/rewriting
/// runs through pure `SearchEngine` on `AppModel`; this view only edits `model.find` state and
/// invokes those actions.
struct FindReplaceBar: View {
    @Bindable var model: AppModel
    @FocusState private var focus: Field?

    private enum Field { case find, replace }

    var body: some View {
        VStack(spacing: 6) {
            findRow
            if model.find.showReplace {
                replaceRow
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear { focus = .find }
        .onExitCommand { model.closeFind() }
    }

    private var findRow: some View {
        HStack(spacing: 6) {
            Button {
                model.find.showReplace.toggle()
            } label: {
                Image(systemName: model.find.showReplace ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain)
            .help(model.find.showReplace ? "Hide replace" : "Show replace")

            TextField("Find", text: $model.find.query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($focus, equals: .find)
                .onChange(of: model.find.query) { model.refreshFindMatches(preferredLocation: nil) }
                .onSubmit { model.findNext() }
                .frame(minWidth: 160)

            optionToggle(".*", isOn: $model.find.options.isRegex, help: "Regular expression")
            optionToggle("W", isOn: $model.find.options.wholeWord, help: "Whole word")
            optionToggle("Aa", isOn: $model.find.options.caseSensitive, help: "Case sensitive")

            Text(model.find.statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)

            Button { model.findPrevious() } label: { Image(systemName: "chevron.up") }
                .help("Previous match (⇧⌘G)")
                .disabled(model.find.matches.isEmpty)
            Button { model.findNext() } label: { Image(systemName: "chevron.down") }
                .help("Next match (⌘G)")
                .disabled(model.find.matches.isEmpty)

            Button { model.closeFind() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .help("Close (Esc)")
        }
    }

    private var replaceRow: some View {
        HStack(spacing: 6) {
            // Aligns the field under the Find field (past the disclosure chevron).
            Image(systemName: "chevron.right").opacity(0)

            TextField("Replace", text: $model.find.replacement)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($focus, equals: .replace)
                .onSubmit { model.replaceCurrent() }
                .frame(minWidth: 160)

            Button("Replace") { model.replaceCurrent() }
                .disabled(model.find.matches.isEmpty)
            Button("Replace All") { model.replaceAll() }
                .disabled(model.find.matches.isEmpty)
            Spacer(minLength: 0)
        }
    }

    private func optionToggle(_ label: String, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            model.refreshFindMatches(preferredLocation: nil)
        } label: {
            Text(label)
                .font(.caption.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isOn.wrappedValue ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
#endif
