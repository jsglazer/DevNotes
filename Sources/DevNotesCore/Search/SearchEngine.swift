import Foundation

/// Search options surfaced above the file list: regex, whole-word, case-sensitivity.
public struct SearchOptions: Equatable, Sendable {
    public var isRegex: Bool
    public var wholeWord: Bool
    public var caseSensitive: Bool

    public init(isRegex: Bool = false, wholeWord: Bool = false, caseSensitive: Bool = false) {
        self.isRegex = isRegex
        self.wholeWord = wholeWord
        self.caseSensitive = caseSensitive
    }
}

/// Pure search: `(query, options) -> filter/matches/ranges` over the note index. Implements
/// regex + whole-word + case-sensitivity as pure logic. Zero AppKit / UIKit / SwiftUI /
/// CloudKit; no I/O. Ranges are returned as `TextSelection` (UTF-16) for highlighting.
public enum SearchEngine {
    /// Compiles `query`/`options` into an `NSRegularExpression`, or `nil` if the query is empty
    /// or (in regex mode) syntactically invalid.
    public static func makeRegex(query: String, options: SearchOptions) -> NSRegularExpression? {
        guard query.isEmpty == false else { return nil }
        var pattern = options.isRegex ? query : NSRegularExpression.escapedPattern(for: query)
        if options.wholeWord {
            pattern = "\\b(?:\(pattern))\\b"
        }
        var regexOptions: NSRegularExpression.Options = []
        if options.caseSensitive == false {
            regexOptions.insert(.caseInsensitive)
        }
        return try? NSRegularExpression(pattern: pattern, options: regexOptions)
    }

    /// Whether `text` matches. An empty query matches everything; an invalid regex matches
    /// nothing (so a half-typed pattern simply yields no results rather than throwing).
    public static func matches(_ text: String, query: String, options: SearchOptions) -> Bool {
        guard query.isEmpty == false else { return true }
        guard let regex = makeRegex(query: query, options: options) else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// UTF-16 ranges of every match in `text`, for highlighting. Empty for empty/invalid query.
    public static func matchRanges(_ text: String, query: String, options: SearchOptions) -> [TextSelection] {
        guard query.isEmpty == false, let regex = makeRegex(query: query, options: options) else { return [] }
        let full = NSRange(location: 0, length: (text as NSString).length)
        var ranges: [TextSelection] = []
        regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match, match.range.location != NSNotFound else { return }
            ranges.append(TextSelection(location: match.range.location, length: match.range.length))
        }
        return ranges
    }

    /// Replaces the single match at `index` (0-based over the ordered matches `matchRanges`
    /// produces) in `text`. In regex mode `replacement` is an ICU template (`$1`, `$2` reference
    /// capture groups); in literal mode it is inserted verbatim. Returns the rewritten text and the
    /// UTF-16 range the inserted replacement now occupies, or `nil` for an out-of-range index or an
    /// empty/invalid query.
    public static func replaceMatch(
        at index: Int,
        in text: String,
        query: String,
        options: SearchOptions,
        replacement: String
    ) -> (text: String, replacedRange: TextSelection)? {
        guard let regex = makeRegex(query: query, options: options) else { return nil }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var matches: [NSTextCheckingResult] = []
        regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            if let match, match.range.location != NSNotFound { matches.append(match) }
        }
        guard index >= 0, index < matches.count else { return nil }
        let match = matches[index]
        let template = options.isRegex ? replacement : NSRegularExpression.escapedTemplate(for: replacement)
        let expanded = regex.replacementString(for: match, in: text, offset: 0, template: template)
        let newText = ns.replacingCharacters(in: match.range, with: expanded)
        let replacedRange = TextSelection(location: match.range.location, length: (expanded as NSString).length)
        return (newText, replacedRange)
    }

    /// Replaces every match of `query` in `text`. In regex mode `replacement` is an ICU template
    /// (`$1`, `$2` reference capture groups); in literal mode it is inserted verbatim. Returns the
    /// text unchanged for an empty/invalid query.
    public static func replaceAll(
        in text: String,
        query: String,
        options: SearchOptions,
        replacement: String
    ) -> String {
        guard let regex = makeRegex(query: query, options: options) else { return text }
        let full = NSRange(location: 0, length: (text as NSString).length)
        let template = options.isRegex ? replacement : NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(in: text, options: [], range: full, withTemplate: template)
    }

    /// Filters note summaries to those whose title or body matches. Order is preserved, so a
    /// pre-sorted (modified-date) list stays sorted.
    public static func filter(_ summaries: [NoteSummary], query: String, options: SearchOptions) -> [NoteSummary] {
        guard query.isEmpty == false else { return summaries }
        return summaries.filter { summary in
            matches(summary.title, query: query, options: options)
                || matches(summary.body, query: query, options: options)
        }
    }
}
