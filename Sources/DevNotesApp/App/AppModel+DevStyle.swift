import DevNotesCore
import DevStyleKit
import Foundation

/// Choosing the DevStyle profile: either follow the style shared by every DevStyle app
/// (`devstyle.json` in the App Group folder, macOS) or use DevNotes' own pair. The choice is per
/// device (`DSAppPreference` in UserDefaults), not synced through iCloud — iOS has no shared folder.
extension AppModel {
    /// True where there is a shared DevStyle folder to follow (macOS with the App Group).
    var canShareStyle: Bool { style.folder != nil }

    /// True while DevNotes follows the shared style.
    var followsSharedStyle: Bool { canShareStyle && style.preference.follow }

    /// The profile id showing for an appearance.
    func styleProfileID(for appearance: DSAppearance) -> String {
        DSSelection.resolve(style.config, followsSharedStyle ? .followShared : ownPreference, appearance)
    }

    /// DevNotes' own pair, starting from whatever is showing now.
    private var ownPreference: DSAppPreference {
        DSAppPreference(
            follow: false,
            light: style.preference.light ?? style.config.light,
            dark: style.preference.dark ?? style.config.dark
        )
    }

    /// Turn "Follow shared style" on or off. Turning it off keeps the profiles that are showing.
    func setFollowsSharedStyle(_ on: Bool) {
        guard canShareStyle else { return }
        if on {
            style.setPreference(.followShared)
        } else {
            style.setPreference(DSAppPreference(follow: false, light: style.config.light, dark: style.config.dark))
        }
    }

    /// Choose a profile for one or both appearances (nil keeps that appearance's current profile).
    /// While following the shared style this changes it for every DevStyle app; otherwise only
    /// DevNotes' own pair.
    func chooseStyleProfiles(light: String? = nil, dark: String? = nil) throws {
        let newLight = light ?? styleProfileID(for: .light)
        let newDark = dark ?? styleProfileID(for: .dark)
        if followsSharedStyle {
            try style.setShared(DSSharedConfig(light: newLight, dark: newDark))
        } else {
            style.setPreference(DSAppPreference(follow: false, light: newLight, dark: newDark))
        }
    }

    /// Profiles of one appearance for a picker, plus the current one if it isn't in the list.
    func styleProfiles(for appearance: DSAppearance) -> [DSProfileInfo] {
        let current = styleProfileID(for: appearance)
        var list = style.profiles.filter { $0.appearance == appearance }.sorted { $0.name < $1.name }
        if list.contains(where: { $0.id == current }) == false,
           let other = style.profiles.first(where: { $0.id == current }) {
            list.append(other)
        }
        return list
    }
}
