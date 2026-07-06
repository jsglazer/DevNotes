import DevNotesCore
import Foundation
import Observation

/// UI-facing state for the in-editor Find/Replace bar (macOS). Holds only the query, replacement,
/// options, and the live match list/cursor — all find/replace *actions* live on `AppModel`, which
/// owns the editor text these operate over. Pure `SearchEngine` does the matching and rewriting.
@MainActor
@Observable
public final class FindState {
    /// Whether the bar is visible over the editor.
    public var isPresented = false
    /// Whether the replace row is shown (⌘⌥F opens with it; ⌘F without).
    public var showReplace = false

    public var query = ""
    public var replacement = ""
    public var options = SearchOptions()

    /// UTF-16 ranges of every current match in the open note, in document order.
    public private(set) var matches: [DevNotesCore.TextSelection] = []
    /// Index into `matches` of the highlighted "current" match, or -1 when there are none.
    public private(set) var currentIndex = -1

    public init() {}

    public var matchCount: Int { matches.count }

    /// The match the editor should select/scroll to, if any.
    public var currentMatch: DevNotesCore.TextSelection? {
        guard currentIndex >= 0, currentIndex < matches.count else { return nil }
        return matches[currentIndex]
    }

    /// "3 of 12" style status, or "No results" / empty for an empty query.
    public var statusText: String {
        if query.isEmpty { return "" }
        guard matches.isEmpty == false else { return "No results" }
        return "\(currentIndex + 1) of \(matches.count)"
    }

    /// Recomputes matches over `text` and keeps `currentIndex` pointing at a sensible match:
    /// the first one at or after `preferredLocation` when the cursor was reset, otherwise the
    /// nearest still-valid index.
    func refresh(in text: String, preferredLocation: Int? = nil) {
        matches = SearchEngine.matchRanges(text, query: query, options: options)
        guard matches.isEmpty == false else { currentIndex = -1; return }
        if let preferredLocation {
            currentIndex = matches.firstIndex { $0.location >= preferredLocation } ?? 0
        } else {
            currentIndex = min(max(currentIndex, 0), matches.count - 1)
        }
    }

    func advance(by delta: Int) {
        guard matches.isEmpty == false else { currentIndex = -1; return }
        currentIndex = ((currentIndex + delta) % matches.count + matches.count) % matches.count
    }

    /// Clamps the cursor after a replacement removed/shifted matches.
    func clampIndex() {
        if matches.isEmpty { currentIndex = -1 } else { currentIndex = min(max(currentIndex, 0), matches.count - 1) }
    }
}
