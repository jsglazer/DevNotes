import DevNotesCore
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Turns a sanitised `StyleSheet` (bounded tokens from Core) into concrete text attributes for
/// the **native attributed-string renderer** — never CSS executed in a WebView. Because the
/// input is already validated to a closed token set, this layer only maps known tokens; there is
/// no path for arbitrary style input to reach the text container.
struct StyleApplier {
    /// Resolved defaults used when a token is absent.
    var baseFontSize: CGFloat = 14
    var baseFontName: String = "Menlo"
    /// Text-zoom multiplier (⌘+/⌘-). Multiplies every resolved font size so the whole note scales
    /// while the user's stylesheet still governs the relative sizes.
    var zoom: CGFloat = 1

    /// Fallback text color when the style sheet has no explicit `textColor` token — must be a
    /// dynamic system color so it stays legible when the theme switches (a fixed color left
    /// typed text black-on-black in dark mode).
    private static var defaultTextColor: PlatformColor {
        #if os(macOS)
        return NSColor.textColor
        #elseif os(iOS)
        return UIColor.label
        #endif
    }

    /// Body typography attributes derived from the sheet.
    func bodyAttributes(from sheet: StyleSheet) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]

        let size = (sizeToken(sheet[.fontSize]) ?? baseFontSize) * zoom
        let family = familyToken(sheet[.fontFamily]) ?? baseFontName
        attributes[.font] = makeFont(name: family, size: size, weight: sheet[.fontWeight])

        attributes[.foregroundColor] = colorToken(sheet[.textColor]) ?? Self.defaultTextColor

        let paragraph = NSMutableParagraphStyle()
        if let lineSpacing = sizeToken(sheet[.lineSpacing]) {
            paragraph.lineSpacing = lineSpacing
        }
        if let paragraphSpacing = sizeToken(sheet[.paragraphSpacing]) {
            paragraph.paragraphSpacing = paragraphSpacing
        }
        attributes[.paragraphStyle] = paragraph
        return attributes
    }

    /// Heading attributes for level 1–3, scaled from the sheet's heading sizes.
    func headingAttributes(level: Int, from sheet: StyleSheet) -> [NSAttributedString.Key: Any] {
        var attributes = bodyAttributes(from: sheet)
        let key: StyleTokenKey = level <= 1 ? .heading1Size : (level == 2 ? .heading2Size : .heading3Size)
        let size = (sizeToken(sheet[key]) ?? (baseFontSize * (level <= 1 ? 1.8 : level == 2 ? 1.5 : 1.25))) * zoom
        attributes[.font] = makeFont(name: familyToken(sheet[.fontFamily]) ?? baseFontName, size: size, weight: .fontWeight(.named("bold")))
        if let color = colorToken(sheet[.headingColor]) {
            attributes[.foregroundColor] = color
        }
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

    private func colorToken(_ value: StyleValue?) -> PlatformColor? {
        if case let .color(hex) = value { return PlatformColor(hex: hex) }
        return nil
    }

    private func makeFont(name: String, size: CGFloat, weight: StyleValue?) -> PlatformFont {
        let base = PlatformFont(name: name, size: size) ?? PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
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
