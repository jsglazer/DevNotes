import Testing
@testable import DevNotesCore

@Suite("DevStyle mapping")
struct DevStyleMappingTests {
    /// The DevStyle 1.1.0 contract (tokens.json in jsglazer/devstyle 1.0.3), as plain names.
    static let contract: Set<String> = [
        "bg", "panel", "raised", "border", "overlay", "fg", "muted", "fg-on-accent", "accent", "accent-soft",
        "focus-ring", "link", "error", "warning", "success", "info", "editor-bg", "editor-fg", "gutter-bg",
        "gutter-fg", "cursor", "selection", "active-line", "matching-bracket", "selection-match", "search-match",
        "search-current", "broken", "pair-highlight", "sync", "syn-heading", "syn-heading-1", "syn-heading-2",
        "syn-heading-3", "syn-heading-4", "syn-heading-5", "syn-heading-6", "syn-keyword", "syn-env", "syn-math",
        "syn-number", "syn-atom", "syn-comment", "syn-code", "syn-quote", "syn-link", "syn-bracket", "syn-meta",
        "syn-error", "ui-font", "ui-size", "mono-font", "mono-size", "mono-line-height", "prose-font", "prose-size",
        "prose-line-height", "heading-font", "radius", "radius-small", "space", "shadow", "page-bg", "page-shadow",
        "page-filter"
    ]

    @Test("Every role maps to a real DevStyle token")
    func everyRoleMapsToTheContract() {
        for role in EditorRole.allCases {
            let token = DevStyleMapping.editorTokens[role]
            #expect(token != nil, "\(role)")
            #expect(Self.contract.contains(token ?? ""), "\(role)")
        }
        for role in SurfaceRole.allCases {
            #expect(Self.contract.contains(DevStyleMapping.surfaceTokens[role] ?? ""), "\(role)")
        }
        #expect(DevStyleMapping.allTokens.isSubset(of: Self.contract))
    }

    @Test("Each heading level has its own colour token; deeper levels use level 6")
    func headingLevels() {
        #expect(DevStyleMapping.headingToken(level: 1) == "syn-heading-1")
        #expect(DevStyleMapping.headingToken(level: 4) == "syn-heading-4")
        #expect(DevStyleMapping.headingToken(level: 6) == "syn-heading-6")
        #expect(DevStyleMapping.headingToken(level: 9) == "syn-heading-6")
        #expect(DevStyleMapping.headingToken(level: 0) == "syn-heading-1")
    }
}

@Suite("Legacy style migration (1.0.32)")
struct LegacyStyleMigrationTests {
    @Test("Colours still at the old defaults are cleared, any other choice is kept")
    func colourOverrides() {
        #expect(LegacyStyleMigration.migratedOverride("#FFF6C2", for: .currentLineLight) == "")
        #expect(LegacyStyleMigration.migratedOverride("#fff6c2", for: .currentLineLight) == "")
        #expect(LegacyStyleMigration.migratedOverride("#3A3B22", for: .currentLineDark) == "")
        #expect(LegacyStyleMigration.migratedOverride("#FFE08A", for: .similarLight) == "")
        #expect(LegacyStyleMigration.migratedOverride("#6E5A1E", for: .similarDark) == "")
        #expect(LegacyStyleMigration.migratedOverride("#123456", for: .similarDark) == "#123456")
        // a light default used in the dark slot was still a choice
        #expect(LegacyStyleMigration.migratedOverride("#FFF6C2", for: .currentLineDark) == "#FFF6C2")
        #expect(LegacyStyleMigration.migratedOverride("  ", for: .similarLight) == "")
    }

    @Test("A style box that only restates the old Menlo 14 defaults can be cleared")
    func styleInputDefaults() {
        #expect(LegacyStyleMigration.isOnlyOldDefaults(styleInput: ""))
        #expect(LegacyStyleMigration.isOnlyOldDefaults(styleInput: "font-family: Menlo; font-size: 14px"))
        #expect(LegacyStyleMigration.isOnlyOldDefaults(styleInput: "font-family: 'Menlo'"))
        #expect(LegacyStyleMigration.isOnlyOldDefaults(styleInput: "font-size: 16") == false)
        #expect(LegacyStyleMigration.isOnlyOldDefaults(styleInput: "font-family: Menlo; text-color: #ffffff") == false)
        #expect(LegacyStyleMigration.isOnlyOldDefaults(styleInput: "font-family: Menlo; bogus") == false)
    }
}
