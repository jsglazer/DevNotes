import Foundation

/// One heading in a note's table of contents, with its nested sub-headings. `selection` is a caret
/// at the start of the heading's line, for jumping the editor straight to it.
public struct OutlineHeading: Identifiable, Equatable, Sendable {
    public let id: Int
    public let level: Int
    public let text: String
    public let selection: TextSelection
    public var children: [OutlineHeading]
}

/// Extracts a hierarchical table of contents from a note's Markdown headings (`#` through `######`).
/// Pure text logic, no I/O — mirrors the heading detection `MarkdownHighlighter` uses for live
/// syntax coloring, but built for structure rather than display.
public enum HeadingOutline {
    private static let pattern = try? NSRegularExpression(
        pattern: #"^[ \t]*(#{1,6})[ \t]+(.+?)[ \t]*$"#,
        options: [.anchorsMatchLines]
    )

    /// The document's headings, nested by level (a heading is a child of the nearest preceding
    /// heading with a lower level — levels can skip, e.g. an H3 directly under an H1).
    public static func extract(from text: String) -> [OutlineHeading] {
        guard let pattern else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        var flat: [(level: Int, title: String, selection: TextSelection)] = []
        pattern.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match else { return }
            let level = match.range(at: 1).length
            let title = ns.substring(with: match.range(at: 2))
            flat.append((level, title, .caret(match.range.location)))
        }

        var nextID = 0
        var index = 0
        func build(minLevel: Int) -> [OutlineHeading] {
            var result: [OutlineHeading] = []
            while index < flat.count, flat[index].level >= minLevel {
                let item = flat[index]
                index += 1
                let children = build(minLevel: item.level + 1)
                result.append(OutlineHeading(
                    id: nextID,
                    level: item.level,
                    text: item.title,
                    selection: item.selection,
                    children: children
                ))
                nextID += 1
            }
            return result
        }
        return build(minLevel: 1)
    }
}
