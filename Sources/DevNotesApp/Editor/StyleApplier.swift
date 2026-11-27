import DevNotesCore
import DevStyleKit
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Turns the editor's look into concrete text attributes for the **native attributed-string
/// renderer** — never CSS executed in a WebView. Two inputs, both already reduced to typed values:
/// the active DevStyle profile (`EditorPalette`: body font, size, line height, colours) and the
/// user's custom style box (`StyleSheet`, sanitised to a closed token set), which wins for every
/// token it sets.
struct StyleApplier {
    /// The active DevStyle theme's editor colours and body font.
    var palette: EditorPalette = .builtin(dark: false)
    /// Text-zoom multiplier (⌘+/⌘-). Multiplies every resolved font size so the whole note scales
    /// while the profile and the user's stylesheet still govern the relative sizes.
    var zoom: CGFloat = 1

    /// The unzoomed body size: the style box's `font-size`, else the profile's.
    func baseSize(from sheet: StyleSheet) -> CGFloat {
        sizeToken(sheet[.fontSize]) ?? palette.bodySize
    }

    /// The editor background: the style box's `background-color`, else the profile's `editor-bg`.
    func editorBackground(from sheet: StyleSheet) -> PlatformColor {
        colorToken(sheet[.backgroundColor]) ?? palette[.editorBackground]
    }

    /// Body typography attributes: the profile's, with the style box's tokens on top.
    func bodyAttributes(from sheet: StyleSheet) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]

        let size = baseSize(from: sheet) * zoom
        attributes[.font] = makeFont(family: familyToken(sheet[.fontFamily]), size: size, weight: sheet[.fontWeight])
        attributes[.foregroundColor] = colorToken(sheet[.textColor]) ?? palette[.editorText]

        let paragraph = NSMutableParagraphStyle()
        if let lineSpacing = sizeToken(sheet[.lineSpacing]) {
            paragraph.lineSpacing = lineSpacing
        } else {
            // the profile's line height (DevStyle mono-line-height) unless the style box sets spacing
            paragraph.lineHeightMultiple = palette.lineHeightMultiple
        }
        if let paragraphSpacing = sizeToken(sheet[.paragraphSpacing]) {
            paragraph.paragraphSpacing = paragraphSpacing
        }
        attributes[.paragraphStyle] = paragraph
        return attributes
    }

    /// Heading attributes for level 1–6: DevNotes' heading sizes (or the style box's), the editor
    /// font in bold, and the level's colour — the style box's `heading-color` when set, else the
    /// profile's per-level colour (`syn-heading-1` … `syn-heading-6`).
    func headingAttributes(level: Int, from sheet: StyleSheet) -> [NSAttributedString.Key: Any] {
        var attributes = bodyAttributes(from: sheet)
        let sizeLevel = min(3, max(1, level))
        let key: StyleTokenKey = sizeLevel == 1 ? .heading1Size : (sizeLevel == 2 ? .heading2Size : .heading3Size)
        let base = baseSize(from: sheet)
        let size = (sizeToken(sheet[key]) ?? (base * (sizeLevel == 1 ? 1.8 : sizeLevel == 2 ? 1.5 : 1.25))) * zoom
        attributes[.font] = makeFont(family: familyToken(sheet[.fontFamily]), size: size, weight: .fontWeight(.named("bold")))
        attributes[.foregroundColor] = colorToken(sheet[.headingColor]) ?? palette.heading(level: level)
        return attributes
    }

    // MARK: - Token → value mapping

    private func sizeToken(_ value: StyleValue?) -> CGFloat? {
        if case let .size(number) = value { return CGFloat(number) }
        return nil
    }

    private func familyToken(_ value: StyleValue?) -> String? {
        if case let .fontFamily(name) = value { return name }
        return nil
    }

    func colorToken(_ value: StyleValue?) -> PlatformColor? {
        if case let .color(hex) = value { return PlatformColor(hex: hex) }
        return nil
    }

    /// The style box's family list when set, else the profile's; installed fonts only, falling back
    /// to the system monospaced font.
    private func makeFont(family: String?, size: CGFloat, weight: StyleValue?) -> PlatformFont {
        let base = family.map { DSFontResolver.font(families: fontFamilies($0), size: size) } ?? palette.bodyFont(size: size)
        guard case let .fontWeight(token) = weight else { return base }
        let isBold: Bool
        switch token {
        case let .named(named): isBold = named == "bold" || named == "heavy" || named == "black" || named == "semibold"
        case let .numeric(number): isBold = number >= 600
        }
        guard isBold else { return base }
        #if os(macOS)
        return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        #elseif os(iOS)
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) else { return base }
        return UIFont(descriptor: descriptor, size: size)
        #else
        return base
        #endif
    }
}

private extension StyleSheet {
    subscript(_ key: StyleTokenKey) -> StyleValue? { tokens[key] }
}

extension PlatformColor {
    /// Builds a colour from a sanitised `#rgb` / `#rrggbb` / `#rrggbbaa` string. The input has
    /// already passed `StyleSanitizer`, so this parse is total.
    convenience init?(hex: String) {
        var hex = hex
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let r, g, b, a: CGFloat
        if hasAlpha {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
