import DevNotesCore
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Live Markdown **syntax coloring** for the editor. This colors the raw Markdown in place — the
/// `#`, `-`, `**`, `` ` `` markers stay visible and take on a font color — rather than hiding
/// markup or rendering HTML. Colors are a small fixed palette layered on top of the
/// `StyleApplier` body attributes, so the user's custom stylesheet still governs the base font,
/// size, and default text color; this pass only overrides `foregroundColor` (and font traits) on
/// the spans it recognises.
///
/// It runs over the whole (small) note on each edit. There is no WebView and no CSS execution: the
/// input is plain text scanned with `NSRegularExpression`, and only known token ranges are colored.
struct MarkdownHighlighter {
    var style: StyleSheet
    var baseFontSize: CGFloat = 14
    var baseFontName: String = "Menlo"

    private var applier: StyleApplier {
        StyleApplier(baseFontSize: baseFontSize, baseFontName: baseFontName)
    }

    // MARK: - Palette
    // Chosen to stay legible in both the light and dark themes. The heading-marker red is the
    // value called out in the feature request (#780202).
    private static let headingMarker = PlatformColor(hex: "#780202")!
    private static let headingText = PlatformColor(hex: "#a11212")!
    private static let listMarker = PlatformColor(hex: "#2563eb")!
    private static let emphasisMarker = PlatformColor(hex: "#7c3aed")!
    private static let codeColor = PlatformColor(hex: "#0f766e")!
    private static let quoteColor = PlatformColor(hex: "#6b7280")!
    private static let linkColor = PlatformColor(hex: "#2563eb")!

    /// Applies base attributes then the syntax overlays to `storage`. Selection and text are left
    /// untouched — only attribute runs change.
    func apply(to storage: NSTextStorage) {
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard ns.length > 0 else { return }

        let body = applier.bodyAttributes(from: style)
        storage.setAttributes(body, range: full)

        let baseFont = (body[.font] as? PlatformFont)
            ?? PlatformFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular)

        // --- Block markers (per line) ---
        // Headings: color the leading #'s, and give the heading text its heading font + color.
        applyRegex(#"^[ \t]*(#{1,6})([ \t]+.*)?$"#, in: ns, storage: storage, options: [.anchorsMatchLines]) { match in
            let markers = match.range(at: 1)
            storage.addAttributes([.foregroundColor: Self.headingMarker], range: markers)
            let level = min(3, max(1, markers.length))
            let headingAttrs = applier.headingAttributes(level: level, from: style)
            if let headingFont = headingAttrs[.font] as? PlatformFont {
                storage.addAttribute(.font, value: headingFont, range: markers)
                if match.range(at: 2).location != NSNotFound, match.range(at: 2).length > 0 {
                    storage.addAttributes([.font: headingFont, .foregroundColor: Self.headingText], range: match.range(at: 2))
                }
            }
        }

        // Bullet markers: `-`, `*`, `+` followed by a space.
        applyRegex(#"^[ \t]*([-*+])[ \t]"#, in: ns, storage: storage, options: [.anchorsMatchLines]) { match in
            storage.addAttribute(.foregroundColor, value: Self.listMarker, range: match.range(at: 1))
        }
        // Numbered markers: `12.` followed by a space.
        applyRegex(#"^[ \t]*(\d+\.)[ \t]"#, in: ns, storage: storage, options: [.anchorsMatchLines]) { match in
            storage.addAttribute(.foregroundColor, value: Self.listMarker, range: match.range(at: 1))
        }
        // Blockquote marker.
        applyRegex(#"^[ \t]*(>)"#, in: ns, storage: storage, options: [.anchorsMatchLines]) { match in
            storage.addAttribute(.foregroundColor, value: Self.quoteColor, range: match.range(at: 1))
        }

        // --- Inline spans ---
        // Inline code `like this` — teal + monospaced.
        applyRegex(#"`[^`\n]+`"#, in: ns, storage: storage) { match in
            storage.addAttributes([
                .foregroundColor: Self.codeColor,
                .font: Self.monospaced(baseFont)
            ], range: match.range)
        }
        // Bold **text** or __text__ — bold trait, dim markers.
        applyRegex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, in: ns, storage: storage) { match in
            storage.addAttribute(.font, value: Self.bold(baseFont), range: match.range(at: 2))
            colorMarkers(around: match, group: 2, color: Self.emphasisMarker, markerWidth: 2, in: storage)
        }
        // Italic *text* or _text_ — italic trait. Lookarounds avoid matching inside ** ** runs.
        applyRegex(#"(?<![\*_])([*_])(?=\S)([^*_\n]+?)(?<=\S)\1(?![\*_])"#, in: ns, storage: storage) { match in
            storage.addAttribute(.font, value: Self.italic(baseFont), range: match.range(at: 2))
            colorMarkers(around: match, group: 2, color: Self.emphasisMarker, markerWidth: 1, in: storage)
        }
        // Links [text](url) — color the visible text.
        applyRegex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#, in: ns, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: Self.linkColor, range: match.range(at: 1))
        }
    }

    // MARK: - Helpers

    private func applyRegex(
        _ pattern: String,
        in ns: NSString,
        storage: NSTextStorage,
        options: NSRegularExpression.Options = [],
        body: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        regex.enumerateMatches(in: ns as String, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            if let match { body(match) }
        }
    }

    /// Dims the delimiter runs on either side of the emphasised text so `**bold**` reads as
    /// colored markers wrapping styled text.
    private func colorMarkers(around match: NSTextCheckingResult, group: Int, color: PlatformColor, markerWidth: Int, in storage: NSTextStorage) {
        let inner = match.range(at: group)
        let full = match.range
        let leading = NSRange(location: full.location, length: max(0, inner.location - full.location))
        let trailingStart = inner.location + inner.length
        let trailing = NSRange(location: trailingStart, length: max(0, full.location + full.length - trailingStart))
        if leading.length > 0 { storage.addAttribute(.foregroundColor, value: color, range: leading) }
        if trailing.length > 0 { storage.addAttribute(.foregroundColor, value: color, range: trailing) }
    }

    // MARK: - Font trait derivation

    private static func bold(_ font: PlatformFont) -> PlatformFont {
        #if os(macOS)
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        #elseif os(iOS)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitBold)) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #else
        return font
        #endif
    }

    private static func italic(_ font: PlatformFont) -> PlatformFont {
        #if os(macOS)
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #elseif os(iOS)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #else
        return font
        #endif
    }

    private static func monospaced(_ font: PlatformFont) -> PlatformFont {
        PlatformFont(name: "Menlo", size: font.pointSize)
            ?? PlatformFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
    }
}

private extension StyleSheet {
    subscript(_ key: StyleTokenKey) -> StyleValue? { tokens[key] }
}
