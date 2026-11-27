import DevNotesCore
import DevStyleKit
import SwiftUI

/// Settings ▸ Style: which DevStyle profile DevNotes shows (https://github.com/jsglazer/devstyle).
/// On macOS a switch decides between the style shared by every DevStyle app and DevNotes' own pair;
/// iOS has no shared folder, so it shows only the two pickers over DevStyle's built-in profiles.
/// Problems with a profile (a bad value, a missing profile) are listed here, never as alerts.
struct StyleSettingsSection: View {
    @Bindable var model: AppModel
    @State private var error: String?

    var body: some View {
        // Reading the store's observable values here keeps the section live when another app
        // changes the shared style.
        let store = model.style
        let follow = model.followsSharedStyle
        Section("Style") {
            if model.canShareStyle {
                Toggle("Follow shared style (all DevStyle apps)", isOn: Binding(
                    get: { follow },
                    set: { model.setFollowsSharedStyle($0) }
                ))
            }
            profilePicker("Light profile", appearance: .light)
            profilePicker("Dark profile", appearance: .dark)
            Text(hint(follow: follow))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ForEach(Array(store.issues.enumerated()), id: \.offset) { _, issue in
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func hint(follow: Bool) -> String {
        if model.canShareStyle == false {
            return "DevStyle's built-in profiles, one for light and one for dark appearance. The Theme setting above picks which one shows."
        }
        let folder = model.style.folder?.url.path ?? ""
        return follow
            ? "Following the shared style: changing these profiles changes every app that follows it. Profiles live in \(folder)."
            : "Using DevNotes' own profiles: other apps are not affected. Profiles live in \(folder)."
    }

    private func profilePicker(_ title: String, appearance: DSAppearance) -> some View {
        Picker(title, selection: Binding(
            get: { model.styleProfileID(for: appearance) },
            set: { id in
                do {
                    error = nil
                    try model.chooseStyleProfiles(
                        light: appearance == .light ? id : nil,
                        dark: appearance == .dark ? id : nil
                    )
                } catch {
                    self.error = "Could not change the shared style: \(error.localizedDescription)"
                }
            }
        )) {
            ForEach(model.styleProfiles(for: appearance)) { profile in
                Text(profile.appearance == appearance ? profile.name : "\(profile.name) (\(profile.appearance.rawValue))")
                    .tag(profile.id)
            }
        }
    }
}
