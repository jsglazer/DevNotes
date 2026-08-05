import Foundation

/// The preferences that follow the user between devices: the Editor Style token sheet plus the
/// appearance/format settings that describe how notes should *look and read* everywhere.
/// Deliberately excludes the device-shaped preferences — zoom, wrap, line numbers, spell check,
/// bottom padding, open-on-launch — since a Mac-sized zoom level has no business landing on a phone.
///
/// Handled as one snapshot rather than nine loose keys so "this device and iCloud disagree" is a
/// single comparison, and so a divergence can be described to the user instead of silently resolved.
struct SyncedPreferences: Equatable, Sendable {
    var styleInput: String
    var theme: String
    var openJump: String
    var dateFormat: String
    var highlightCurrentLine: Bool
    var currentLineLight: String
    var currentLineDark: String
    var similarLight: String
    var similarDark: String

    /// Human-readable names of the settings that differ from `other`, in Settings order — the body
    /// of the conflict alert, so the user knows what they're choosing between.
    func differences(from other: SyncedPreferences) -> [String] {
        var names: [String] = []
        if theme != other.theme { names.append("Theme") }
        if highlightCurrentLine != other.highlightCurrentLine
            || currentLineLight != other.currentLineLight
            || currentLineDark != other.currentLineDark {
            names.append("Current Line highlight")
        }
        if similarLight != other.similarLight || similarDark != other.similarDark {
            names.append("Highlight Similar colours")
        }
        if dateFormat != other.dateFormat { names.append("Insert Date & Time format") }
        if openJump != other.openJump { names.append("On Open") }
        if styleInput != other.styleInput { names.append("Editor Style") }
        return names
    }
}

/// Raised when this device's synced preferences and the copy in iCloud have both moved since they
/// were last reconciled — a genuine divergence with no correct automatic answer, so the user picks.
/// Presented as an alert by the root view.
struct PreferenceConflict: Identifiable, Equatable {
    let id = UUID()
    /// The snapshot iCloud is holding.
    let remote: SyncedPreferences
    /// The device that last published to iCloud ("Josh's iPhone"), or a generic fallback.
    let remoteDevice: String
    /// Names of the settings that differ (see `SyncedPreferences.differences(from:)`).
    let differences: [String]

    /// The alert body: what disagrees, and where the other copy came from.
    var message: String {
        let list = differences.isEmpty ? "Some settings" : differences.joined(separator: ", ")
        return """
        \(list) changed on this device and on \(remoteDevice) since they were last in sync.

        Choose which copy to keep — it will be applied everywhere.
        """
    }
}

extension NSUbiquitousKeyValueStore {
    /// The synced preferences iCloud currently holds, laid over `local` so a key iCloud has never
    /// seen keeps this device's value rather than reading back as an empty string. Returns nil when
    /// iCloud holds none of them at all (nothing to reconcile against).
    func syncedPreferences(mergedOnto local: SyncedPreferences) -> SyncedPreferences? {
        var result = local
        var found = false
        if let raw = string(forKey: PreferenceKey.styleInput) {
            result.styleInput = raw
            found = true
        }
        if let raw = string(forKey: PreferenceKey.theme), raw.isEmpty == false {
            result.theme = raw
            found = true
        }
        if let raw = string(forKey: PreferenceKey.openJump), raw.isEmpty == false {
            result.openJump = raw
            found = true
        }
        if let raw = string(forKey: PreferenceKey.dateFormat), raw.isEmpty == false {
            result.dateFormat = raw
            found = true
        }
        if object(forKey: PreferenceKey.highlightCurrentLine) != nil {
            result.highlightCurrentLine = bool(forKey: PreferenceKey.highlightCurrentLine)
            found = true
        }
        for (key, keyPath) in Self.colorKeyPaths {
            if let raw = string(forKey: key), raw.isEmpty == false {
                result[keyPath: keyPath] = raw
                found = true
            }
        }
        return found ? result : nil
    }

    /// Publishes `preferences` as this device's copy, stamped with the revision it was changed at
    /// and the device that changed it, then flushes once. A single `synchronize()` per push (rather
    /// than one per key) matters: the key-value store throttles how often it will actually upload,
    /// and hammering it — as a per-keystroke mirror of the style sheet did — gets changes delayed
    /// or coalesced away instead of delivered.
    func publish(_ preferences: SyncedPreferences, revision: Double, device: String) {
        set(preferences.styleInput, forKey: PreferenceKey.styleInput)
        set(preferences.theme, forKey: PreferenceKey.theme)
        set(preferences.openJump, forKey: PreferenceKey.openJump)
        set(preferences.dateFormat, forKey: PreferenceKey.dateFormat)
        set(preferences.highlightCurrentLine, forKey: PreferenceKey.highlightCurrentLine)
        set(preferences.currentLineLight, forKey: PreferenceKey.currentLineLight)
        set(preferences.currentLineDark, forKey: PreferenceKey.currentLineDark)
        set(preferences.similarLight, forKey: PreferenceKey.similarColorLight)
        set(preferences.similarDark, forKey: PreferenceKey.similarColorDark)
        set(revision, forKey: PreferenceKey.prefsRevision)
        set(device, forKey: PreferenceKey.prefsDevice)
        synchronize()
    }

    /// When iCloud's copy was last changed, as seconds since 1970. Zero when it predates revision
    /// stamping (written by an app version before this one) or has never been written.
    var preferencesRevision: Double { double(forKey: PreferenceKey.prefsRevision) }

    /// The device that last published, for the conflict alert.
    var preferencesDevice: String {
        let name = string(forKey: PreferenceKey.prefsDevice) ?? ""
        return name.isEmpty ? "another device" : name
    }

    /// The two-per-theme colour settings, paired with the snapshot fields they load into.
    private static var colorKeyPaths: [(String, WritableKeyPath<SyncedPreferences, String>)] {
        [
            (PreferenceKey.currentLineLight, \.currentLineLight),
            (PreferenceKey.currentLineDark, \.currentLineDark),
            (PreferenceKey.similarColorLight, \.similarLight),
            (PreferenceKey.similarColorDark, \.similarDark)
        ]
    }
}
