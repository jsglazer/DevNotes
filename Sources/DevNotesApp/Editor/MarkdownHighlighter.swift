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
    /// Text-zoom multiplier (⌘+/⌘-), forwarded to the `StyleApplier` so the syntax pass sizes fonts
    /// to match the zoomed body text.
    var zoom: CGFloat = 1

    private var applier: StyleApplier {
        StyleApplier(baseFontSize: baseFontSize, baseFontName: baseFontName, zoom: zoom)
    }

    // MARK: - Palette
    // Chosen to stay legible in both the light and dark themes. Heading lines are colored per
    // level — markers and text alike: # red, ## orange, ### yellow, #### (and deeper) green.
    private static let fallbackColor = PlatformColor.gray
    private static let headingLevelColors: [PlatformColor] = [
        PlatformColor(hex: "#D8564F") ?? fallbackColor,
        PlatformColor(hex: "#E07D2C") ?? fallbackColor,
        PlatformColor(hex: "#DAB22E") ?? fallbackColor,
        PlatformColor(hex: "#89AC40") ?? fallbackColor
    ]
    private static let listMarker = PlatformColor(hex: "#2563eb") ?? fallbackColor
    private static let emphasisMarker = PlatformColor(hex: "#7c3aed") ?? fallbackColor
    private static let codeColor = PlatformColor(hex: "#0f766e") ?? fallbackColor
    private static let quoteColor = PlatformColor(hex: "#6b7280") ?? fallbackColor
    private static let linkColor = PlatformColor(hex: "#2563eb") ?? fallbackColor

    /// Heading color for a `#` run of `level` characters; levels past the palette reuse its last color.
    private static func headingColor(level: Int) -> PlatformColor {
        headingLevelColors[min(max(level, 1), headingLevelColors.count) - 1]
    }

    // MARK: - Compiled patterns
    // Compiled once per process. `apply(to:)` runs on every keystroke, so re-compiling each
    // NSRegularExpression per call was pure overhead on the typing path.
    private static let headingPattern = compile(#"^[ \t]*(#{1,6})([ \t]+.*)?$"#, options: [.anchorsMatchLines])
    private static let bulletPattern = compile(#"^[ \t]*([-*+])[ \t]"#, options: [.anchorsMatchLines])
    private static let numberedPattern = compile(#"^[ \t]*(\d+\.)[ \t]"#, options: [.anchorsMatchLines])
    private static let quotePattern = compile(#"^[ \t]*(>)"#, options: [.anchorsMatchLines])
    private static let thematicBreakPattern = compile(#"^[ \t]{0,3}([-*_])([ \t]*\1){2,}[ \t]*$"#, options: [.anchorsMatchLines])
    private static let codePattern = compile(#"`[^`\n]+`"#)
    private static let boldPattern = compile(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicPattern = compile(#"(?<![\*_])([*_])(?=\S)([^*_\n]+?)(?<=\S)\1(?![\*_])"#)
    private static let linkPattern = compile(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)

    private static func compile(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

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
        // The body paragraph style (line/paragraph spacing) is the base each list line's hanging
        // indent is layered onto, so wrapped bullet/number lines tuck under their text.
        let baseParagraph = (body[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle()

        // --- Block markers (per line) ---
        // Headings: the whole line — leading #'s and heading text — takes the per-level color,
        // and the heading text gets its heading font.
        applyRegex(Self.headingPattern, in: ns, storage: storage) { match in
            let markers = match.range(at: 1)
            let color = Self.headingColor(level: markers.length)
            storage.addAttributes([.foregroundColor: color], range: markers)
            let level = min(3, max(1, markers.length))
            let headingAttrs = applier.headingAttributes(level: level, from: style)
            if let headingFont = headingAttrs[.font] as? PlatformFont {
                storage.addAttribute(.font, value: headingFont, range: markers)
                let text = match.range(at: 2)
                if text.location != NSNotFound, text.length > 0 {
                    storage.addAttributes([.font: headingFont, .foregroundColor: color], range: text)
                }
            }
        }

        // Bullet markers: `-`, `*`, `+` followed by a space. The whole matched prefix (indent +
        // marker + trailing space) sets the hanging indent so wrapped text tucks under the marker.
        applyRegex(Self.bulletPattern, in: ns, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: Self.listMarker, range: match.range(at: 1))
            applyHangingIndent(prefixRange: match.range, in: ns, storage: storage, baseFont: baseFont, base: baseParagraph)
        }
        // Numbered markers: `12.` followed by a space.
        applyRegex(Self.numberedPattern, in: ns, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: Self.listMarker, range: match.range(at: 1))
            applyHangingIndent(prefixRange: match.range, in: ns, storage: storage, baseFont: baseFont, base: baseParagraph)
        }
        // Blockquote marker.
        applyRegex(Self.quotePattern, in: ns, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: Self.quoteColor, range: match.range(at: 1))
        }
        // Thematic break (`---`, `***`, `___`) — dim the whole line so the real rule drawn over it
        // (macOS) reads cleanly, and iOS still gets a distinct divider colour.
        applyRegex(Self.thematicBreakPattern, in: ns, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: Self.quoteColor, range: match.range)
        }

        // --- Inline spans ---
        // Inline code `like this` — teal + monospaced.
        applyRegex(Self.codePattern, in: ns, storage: storage) { match in
            storage.addAttributes([
                .foregroundColor: Self.codeColor,
                .font: Self.monospaced(baseFont)
            ], range: match.range)
        }
        // Bold **text** or __text__ — bold trait, dim markers.
        applyRegex(Self.boldPattern, in: ns, storage: storage) { match in
            storage.addAttribute(.font, value: Self.bold(baseFont), range: match.range(at: 2))
            colorMarkers(around: match, group: 2, color: Self.emphasisMarker, in: storage)
        }
        // Italic *text* or _text_ — italic trait. Lookarounds avoid matching inside ** ** runs.
        applyRegex(Self.italicPattern, in: ns, storage: storage) { match in
            storage.addAttribute(.font, value: Self.italic(baseFont), range: match.range(at: 2))
            colorMarkers(around: match, group: 2, color: Self.emphasisMarker, in: storage)
        }
        // Links [text](url) — color the visible text.
        applyRegex(Self.linkPattern, in: ns, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: Self.linkColor, range: match.range(at: 1))
        }
    }

    // MARK: - Helpers

    /// Gives a list line a hanging indent: continuation (wrapped) lines align under the text after
    /// the marker, instead of falling back to the left margin. `prefixRange` is the matched
    /// indent + marker + space; its rendered width in `baseFont` becomes the paragraph's `headIndent`.
    /// The first line keeps its natural start (`firstLineHeadIndent = 0`) because its own prefix
    /// characters already provide that offset.
    private func applyHangingIndent(
        prefixRange: NSRange,
        in ns: NSString,
        storage: NSTextStorage,
        baseFont: PlatformFont,
        base: NSParagraphStyle
    ) {
        guard prefixRange.length > 0, NSMaxRange(prefixRange) <= ns.length else { return }
        let prefix = ns.substring(with: prefixRange)
        let width = (prefix as NSString).size(withAttributes: [.font: baseFont]).width
        guard width > 0 else { return }
        guard let paragraph = base.mutableCopy() as? NSMutableParagraphStyle else { return }
        paragraph.headIndent = width
        paragraph.firstLineHeadIndent = 0
        let lineRange = ns.paragraphRange(for: prefixRange)
        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
    }

    private func applyRegex(
        _ regex: NSRegularExpression?,
        in ns: NSString,
        storage: NSTextStorage,
        body: (NSTextCheckingResult) -> Void
    ) {
        guard let regex else { return }
        regex.enumerateMatches(in: ns as String, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            if let match { body(match) }
        }
    }

    /// Dims the delimiter runs on either side of the emphasised text so `**bold**` reads as
    /// colored markers wrapping styled text.
    private func colorMarkers(
        around match: NSTextCheckingResult,
        group: Int,
        color: PlatformColor,
        in storage: NSTextStorage
    ) {
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
        let traits = font.fontDescriptor.symbolicTraits.union(.traitBold)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #else
        return font
        #endif
    }

    private static func italic(_ font: PlatformFont) -> PlatformFont {
        #if os(macOS)
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #elseif os(iOS)
        let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
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
