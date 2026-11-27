import Foundation

/// Where each part of DevNotes takes its look from in a DevStyle profile
/// (https://github.com/jsglazer/devstyle). DevStyle profiles are shared by every app; DevNotes
/// reads only their typed `--ds-*` values (through DevStyleKit, in the app shell), never CSS.
///
/// Pure: token names as plain strings, so the mapping is tested without DevStyleKit.
public enum EditorRole: String, CaseIterable, Sendable {
    case editorBackground
    case editorText
    case cursor
    case selection
    case currentLine
    case similarMatch
    case searchMatch
    case searchCurrent
    case gutterBackground
    case gutterText
    case gutterBorder
    case listMarker
    case emphasisMarker
    case code
    case quote
    case link
    case rule
}

/// SwiftUI surfaces around the editor (sidebar, outline, bars, merge view).
public enum SurfaceRole: String, CaseIterable, Sendable {
    case background
    case panel
    case border
    case text
    case muted
    case accent
    case textOnAccent
    case error
    case warning
    case success
}

public enum DevStyleMapping {
    /// DevStyle token (without `--ds-`) for each editor role.
    public static let editorTokens: [EditorRole: String] = [
        .editorBackground: "editor-bg",
        .editorText: "editor-fg",
        .cursor: "cursor",
        .selection: "selection",
        .currentLine: "active-line",
        .similarMatch: "selection-match",
        .searchMatch: "search-match",
        .searchCurrent: "search-current",
        .gutterBackground: "gutter-bg",
        .gutterText: "gutter-fg",
        .gutterBorder: "border",
        .listMarker: "syn-keyword",
        .emphasisMarker: "syn-meta",
        .code: "syn-code",
        .quote: "syn-quote",
        .link: "syn-link",
        .rule: "muted"
    ]

    /// DevStyle token for each surface role.
    public static let surfaceTokens: [SurfaceRole: String] = [
        .background: "bg",
        .panel: "panel",
        .border: "border",
        .text: "fg",
        .muted: "muted",
        .accent: "accent",
        .textOnAccent: "fg-on-accent",
        .error: "error",
        .warning: "warning",
        .success: "success"
    ]

    /// Body text: the editor font, its size and line height.
    public static let bodyFontToken = "mono-font"
    public static let bodySizeToken = "mono-size"
    public static let lineHeightToken = "mono-line-height"
    /// Interface text in the surfaces.
    public static let uiFontToken = "ui-font"
    public static let uiSizeToken = "ui-size"

    /// DevStyle has a colour per heading level (`syn-heading-1` … `syn-heading-6`, DevStyle 1.0.3).
    public static let headingLevels = 6

    /// The heading colour token for a Markdown heading level (1–6; deeper levels use level 6).
    public static func headingToken(level: Int) -> String {
        "syn-heading-\(min(max(level, 1), headingLevels))"
    }

    /// Every token DevNotes reads, for tests and diagnostics.
    public static var allTokens: Set<String> {
        var all = Set(editorTokens.values).union(surfaceTokens.values)
        all.formUnion([bodyFontToken, bodySizeToken, lineHeightToken, uiFontToken, uiSizeToken])
        for level in 1 ... headingLevels { all.insert(headingToken(level: level)) }
        return all
    }
}

/// One-time migration from DevNotes 1.0.32, whose colours were its own. Values still at the old
/// defaults weren't a choice the user made, so they are cleared and the DevStyle profile shows.
public enum LegacyStyleMigration {
    public enum ColorPreference: String, CaseIterable, Sendable {
        case currentLineLight
        case currentLineDark
        case similarLight
        case similarDark
    }

    /// DevNotes 1.0.32's defaults for the colour pickers in Settings.
    public static let oldDefaults: [ColorPreference: String] = [
        .currentLineLight: "#FFF6C2",
        .currentLineDark: "#3A3B22",
        .similarLight: "#FFE08A",
        .similarDark: "#6E5A1E"
    ]

    /// The stored override after migration: empty ("use the profile's colour") when the value is
    /// blank or still the old default, otherwise the value unchanged.
    public static func migratedOverride(_ value: String, for preference: ColorPreference) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else { return "" }
        if let old = oldDefaults[preference], old.caseInsensitiveCompare(trimmed) == .orderedSame { return "" }
        return value
    }

    /// DevNotes 1.0.32 drew notes in Menlo 14 when the custom style box was empty.
    public static let oldBodyDefaults: [StyleTokenKey: StyleValue] = [
        .fontFamily: .fontFamily("Menlo"),
        .fontSize: .size(14)
    ]

    /// True when the custom style box only restates DevNotes 1.0.32's defaults (or is empty), so
    /// clearing it lets the profile's font show without changing anything the user chose.
    public static func isOnlyOldDefaults(styleInput: String) -> Bool {
        let sheet = StyleSanitizer.sanitize(styleInput)
        guard sheet.rejected.isEmpty else { return false }
        return sheet.tokens.allSatisfy { key, value in
            guard let old = oldBodyDefaults[key] else { return false }
            if case let .fontFamily(name) = value, case let .fontFamily(oldName) = old {
                return name.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\"", with: "")
                    .caseInsensitiveCompare(oldName) == .orderedSame
            }
            return value == old
        }
    }
}
