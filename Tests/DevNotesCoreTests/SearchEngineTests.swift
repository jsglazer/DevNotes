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
