import DevNotesCore
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Live Markdown **syntax coloring** for the editor. This colors the raw Markdown in place — the
/// `#`, `-`, `**`, `` ` `` markers stay visible and take on a font color — rather than hiding
/// markup or rendering HTML. Colours come from the active DevStyle profile (`EditorPalette`:
/// per-level heading colours, list markers, emphasis, code, quotes, links), layered on top of the
/// `StyleApplier` body attributes, so the profile and the user's custom stylesheet govern the base
/// font, size, and default text colour; this pass only overrides `foregroundColor` (and font
/// traits) on the spans it recognises.
///
/// It runs over the whole (small) note on each edit. There is no WebView and no CSS execution: the
/// input is plain text scanned with `NSRegularExpression`, and only known token ranges are colored.
struct MarkdownHighlighter {
    var style: StyleSheet
    /// The active DevStyle theme's colours and body font.
    var palette: EditorPalette = .builtin(dark: false)
    /// Text-zoom multiplier (⌘+/⌘-), forwarded to the `StyleApplier` so the syntax pass sizes fonts
    /// to match the zoomed body text.
    var zoom: CGFloat = 1

    private var applier: StyleApplier {
        StyleApplier(palette: palette, zoom: zoom)
    }

    // MARK: - Palette
    // From the DevStyle profile. Heading lines are coloured per level, markers and text alike
    // (`syn-heading-1` … `syn-heading-6`; Default keeps DevNotes' red, orange, yellow, green…),
    // unless the custom style box sets `heading-color`.

    /// Heading colour for a `#` run of `level` characters.
    private func headingColor(level: Int) -> PlatformColor {
        applier.colorToken(style[.headingColor]) ?? palette.heading(level: level)
    }

    /// List-marker colour: the user's `bullet-color` token when set, else the profile's.
    private var bulletColor: PlatformColor {
        applier.colorToken(style[.bulletColor]) ?? palette[.listMarker]
    }

    /// Extra vertical space painted before heading lines (`section-spacing` token), scaled with the
    /// zoom like every other size. Nil when the token is absent.
    private var sectionSpacingBefore: CGFloat? {
        if case let .size(value)? = style[.sectionSpacing] { return CGFloat(value) * zoom }
        return nil
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
    ///
    /// `editedRange` scopes the work to just the paragraph(s) an edit touched: **every** pattern
    /// this highlighter recognises is line-anchored or single-line (headings/lists/quotes/rules are
    /// `^…$`; code/bold/italic/link all exclude `\n`), so a change on one line can never alter
    /// another line's colouring. Re-styling only the edited paragraph — instead of `setAttributes`
    /// over the whole document on every keystroke — is what stops the TextKit 2 viewport from
    /// blanking newly-typed text on longer notes. Pass `nil` (the default) to re-colour everything
    /// (load, style/zoom/gutter change, or a full-text replacement).
    func apply(to storage: NSTextStorage, editedRange: NSRange? = nil) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }

        let full: NSRange
        if let editedRange, NSMaxRange(editedRange) <= ns.length {
            full = ns.paragraphRange(for: editedRange)
        } else {
            full = NSRange(location: 0, length: ns.length)
        }
        guard full.length > 0 else { return }

        let body = applier.bodyAttributes(from: style)
        storage.setAttributes(body, range: full)

        let baseFont = (body[.font] as? PlatformFont)
            ?? PlatformFont.monospacedSystemFont(ofSize: applier.baseSize(from: style) * zoom, weight: .regular)
        // The body paragraph style (line/paragraph spacing) is the base each list line's hanging
        // indent is layered onto, so wrapped bullet/number lines tuck under their text.
        let baseParagraph = (body[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle()

        // --- Block markers (per line) ---
        // Headings: the whole line — leading #'s and heading text — takes the per-level color,
        // and the heading text gets its heading font.
        applyRegex(Self.headingPattern, in: ns, range: full, storage: storage) { match in
            let markers = match.range(at: 1)
            let color = headingColor(level: markers.length)
            storage.addAttributes([.foregroundColor: color], range: markers)
            let headingAttrs = applier.headingAttributes(level: markers.length, from: style)
            if let headingFont = headingAttrs[.font] as? PlatformFont {
                storage.addAttribute(.font, value: headingFont, range: markers)
                let text = match.range(at: 2)
                if text.location != NSNotFound, text.length > 0 {
                    storage.addAttributes([.font: headingFont, .foregroundColor: color], range: text)
                }
            }
            // `section-spacing` token: breathing room above each heading (paragraph-level, so it
            // survives wrapping) without the user having to type blank lines.
            if let spacing = sectionSpacingBefore,
               let paragraph = baseParagraph.mutableCopy() as? NSMutableParagraphStyle {
                paragraph.paragraphSpacingBefore = spacing
                storage.addAttribute(.paragraphStyle, value: paragraph, range: ns.paragraphRange(for: match.range))
            }
        }

        // Bullet markers: `-`, `*`, `+` followed by a space. The whole matched prefix (indent +
        // marker + trailing space) sets the hanging indent so wrapped text tucks under the marker.
        applyRegex(Self.bulletPattern, in: ns, range: full, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: bulletColor, range: match.range(at: 1))
            applyHangingIndent(prefixRange: match.range, in: ns, storage: storage, baseFont: baseFont, base: baseParagraph)
        }
        // Numbered markers: `12.` followed by a space.
        applyRegex(Self.numberedPattern, in: ns, range: full, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: bulletColor, range: match.range(at: 1))
            applyHangingIndent(prefixRange: match.range, in: ns, storage: storage, baseFont: baseFont, base: baseParagraph)
        }
        // Blockquote marker.
        applyRegex(Self.quotePattern, in: ns, range: full, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: palette[.quote], range: match.range(at: 1))
        }
        // Thematic break (`---`, `***`, `___`) — dim the whole line so the real rule drawn over it
        // (macOS) reads cleanly, and iOS still gets a distinct divider colour.
        applyRegex(Self.thematicBreakPattern, in: ns, range: full, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: palette[.rule], range: match.range)
        }

        // --- Inline spans ---
        // Inline code `like this` — teal + monospaced.
        applyRegex(Self.codePattern, in: ns, range: full, storage: storage) { match in
            storage.addAttributes([
                .foregroundColor: palette[.code],
                .font: Self.monospaced(baseFont)
            ], range: match.range)
        }
        // Bold **text** or __text__ — bold trait, dim markers.
        applyRegex(Self.boldPattern, in: ns, range: full, storage: storage) { match in
            storage.addAttribute(.font, value: Self.bold(baseFont), range: match.range(at: 2))
            colorMarkers(around: match, group: 2, color: palette[.emphasisMarker], in: storage)
        }
        // Italic *text* or _text_ — italic trait. Lookarounds avoid matching inside ** ** runs.
        applyRegex(Self.italicPattern, in: ns, range: full, storage: storage) { match in
            storage.addAttribute(.font, value: Self.italic(baseFont), range: match.range(at: 2))
            colorMarkers(around: match, group: 2, color: palette[.emphasisMarker], in: storage)
        }
        // Links [text](url) — color the visible text.
        applyRegex(Self.linkPattern, in: ns, range: full, storage: storage) { match in
            storage.addAttribute(.foregroundColor, value: palette[.link], range: match.range(at: 1))
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
        range: NSRange,
        storage: NSTextStorage,
        body: (NSTextCheckingResult) -> Void
    ) {
        guard let regex else { return }
        regex.enumerateMatches(in: ns as String, range: range) { match, _, _ in
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
