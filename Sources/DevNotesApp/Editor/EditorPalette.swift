import DevNotesCore
import DevStyleKit
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// The editor's colours and body font, read from the active DevStyle theme
/// (https://github.com/jsglazer/devstyle). DevStyleKit hands over only typed values (colours,
/// sizes, font-family lists) parsed from the profile's `--ds-*` lines — never CSS — so nothing
/// arbitrary reaches the text view. Which token feeds which part is `DevStyleMapping` (Core).
///
/// A value type compared by theme, so the editor surfaces re-colour only when the profile or the
/// light/dark appearance actually changes.
struct EditorPalette: Equatable {
    let theme: DSTheme

    init(theme: DSTheme) {
        self.theme = theme
    }

    /// The built-in Default for an appearance (previews, export without a window).
    static func builtin(dark: Bool) -> EditorPalette {
        EditorPalette(theme: .builtinDefault(dark ? .dark : .light))
    }

    subscript(_ role: EditorRole) -> PlatformColor {
        theme.platformColor(DevStyleMapping.editorTokens[role] ?? "editor-fg")
    }

    /// Per-level heading colour (`syn-heading-1` … `syn-heading-6`).
    func heading(level: Int) -> PlatformColor {
        theme.platformColor(DevStyleMapping.headingToken(level: level))
    }

    /// The profile's editor font families (e.g. `'SF Mono', Menlo, monospace`).
    var bodyFamilies: [String] { theme.families(DevStyleMapping.bodyFontToken) }

    /// The profile's editor font size in points (DevStyle `mono-size`).
    var bodySize: CGFloat {
        let size = theme.size(DevStyleMapping.bodySizeToken)
        return size > 0 ? size : 14
    }

    /// The profile's editor line height as a multiple of the font size (DevStyle `mono-line-height`).
    var lineHeightMultiple: CGFloat {
        let value = theme.size(DevStyleMapping.lineHeightToken)
        return value >= 1 && value <= 3 ? value : 1
    }

    /// The profile's body font at `size` points.
    func bodyFont(size: CGFloat) -> PlatformFont {
        DSFontResolver.font(families: bodyFamilies, size: size)
    }

    /// SwiftUI colour for a surface role (sidebar, bars, outline, merge view).
    func surface(_ role: SurfaceRole) -> Color {
        theme.color(DevStyleMapping.surfaceTokens[role] ?? "fg")
    }
}

extension DSTheme {
    /// SwiftUI colour for a DevNotes surface role.
    func surface(_ role: SurfaceRole) -> Color {
        color(DevStyleMapping.surfaceTokens[role] ?? "fg")
    }

    /// The interface font (DevStyle `ui-font` at `ui-size`), scaled.
    func interfaceFont(scale: CGFloat = 1) -> Font {
        font(DevStyleMapping.uiFontToken, sizeToken: DevStyleMapping.uiSizeToken, scale: scale)
    }
}

/// Splits a sanitised `font-family` value (`'Fira Code', Menlo, monospace`) into family names.
func fontFamilies(_ value: String) -> [String] {
    value.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }
        .filter { $0.isEmpty == false }
}
