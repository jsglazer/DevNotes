import Testing
@testable import DevNotesCore

@Suite("SearchEngine")
struct SearchEngineTests {
    @Test("Empty query matches everything")
    func emptyQueryMatches() {
        #expect(SearchEngine.matches("anything", query: "", options: SearchOptions()))
    }

    @Test("Literal search is case-insensitive by default")
    func caseInsensitiveByDefault() {
        #expect(SearchEngine.matches("Hello World", query: "hello", options: SearchOptions()))
    }

    @Test("Case-sensitive search respects case")
    func caseSensitive() {
        let options = SearchOptions(caseSensitive: true)
        #expect(SearchEngine.matches("hello", query: "hello", options: options))
        #expect(SearchEngine.matches("Hello", query: "hello", options: options) == false)
    }

    @Test("Whole-word search does not match inside longer words")
    func wholeWord() {
        let options = SearchOptions(wholeWord: true)
        #expect(SearchEngine.matches("a cat sat", query: "cat", options: options))
        #expect(SearchEngine.matches("category", query: "cat", options: options) == false)
    }

    @Test("Regex search matches a pattern")
    func regexMatches() {
        let options = SearchOptions(isRegex: true)
        #expect(SearchEngine.matches("abc123", query: "[0-9]+", options: options))
    }

    @Test("An invalid regex matches nothing instead of throwing")
    func invalidRegex() {
        let options = SearchOptions(isRegex: true)
        #expect(SearchEngine.makeRegex(query: "[", options: options) == nil)
        #expect(SearchEngine.matches("abc", query: "[", options: options) == false)
    }

    @Test("Match ranges are returned in UTF-16 units for highlighting")
    func matchRanges() {
        let ranges = SearchEngine.matchRanges("a cat cat", query: "cat", options: SearchOptions())
        #expect(ranges == [
            TextSelection(location: 2, length: 3),
            TextSelection(location: 6, length: 3)
        ])
    }

    @Test("Replace all substitutes every literal match")
    func replaceAllLiteral() {
        let result = SearchEngine.replaceAll(in: "a cat cat", query: "cat", options: SearchOptions(), replacement: "dog")
        #expect(result == "a dog dog")
    }

    @Test("Replace all treats a literal replacement verbatim (no $ template expansion)")
    func replaceAllLiteralDollar() {
        let result = SearchEngine.replaceAll(in: "price x", query: "x", options: SearchOptions(), replacement: "$5")
        #expect(result == "price $5")
    }

    @Test("Replace all expands capture groups in regex mode")
    func replaceAllRegexTemplate() {
        let options = SearchOptions(isRegex: true)
        let result = SearchEngine.replaceAll(in: "2026-07-05", query: "(\\d{4})-(\\d{2})", options: options, replacement: "$2/$1")
        #expect(result == "07/2026-05")
    }

    @Test("Replace match rewrites only the indexed occurrence")
    func replaceMatchByIndex() {
        let result = SearchEngine.replaceMatch(at: 1, in: "a cat cat", query: "cat", options: SearchOptions(), replacement: "dog")
        #expect(result?.text == "a cat dog")
        #expect(result?.replacedRange == TextSelection(location: 6, length: 3))
    }

    @Test("Replace match returns nil for an out-of-range index")
    func replaceMatchOutOfRange() {
        #expect(SearchEngine.replaceMatch(at: 5, in: "a cat", query: "cat", options: SearchOptions(), replacement: "dog") == nil)
    }

    @Test("Filter keeps matching summaries and preserves order")
    func filterSummaries() {
        let summaries = [
            NoteSummary(id: NoteID("1"), title: "Groceries", body: "milk and eggs", modifiedAt: .init(timeIntervalSince1970: 3)),
            NoteSummary(id: NoteID("2"), title: "Ideas", body: "build a cat app", modifiedAt: .init(timeIntervalSince1970: 2)),
            NoteSummary(id: NoteID("3"), title: "Cats", body: "nothing here", modifiedAt: .init(timeIntervalSince1970: 1))
        ]
        let filtered = SearchEngine.filter(summaries, query: "cat", options: SearchOptions())
        #expect(filtered.map(\.id) == [NoteID("2"), NoteID("3")])
    }
}
