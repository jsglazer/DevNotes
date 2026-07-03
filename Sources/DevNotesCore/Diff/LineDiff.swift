import Foundation

/// One aligned step of a diff between two sequences.
enum Change<Element: Equatable>: Equatable {
    case equal(Element)
    case delete(Element) // present in the left/`mine` sequence only
    case insert(Element) // present in the right/`theirs` sequence only
}

/// Longest-common-subsequence diff over any equatable sequence. Deterministic (fixed
/// tie-breaking) so tests are stable. `O(n·m)` time/space, which is fine for note-sized text.
enum LCS {
    static func diff<Element: Equatable>(_ a: [Element], _ b: [Element]) -> [Change<Element>] {
        let n = a.count
        let m = b.count
        // dp[i][j] = LCS length of a[i...] and b[j...].
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var result: [Change<Element>] = []
        var i = 0
        var j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                result.append(.equal(a[i]))
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                result.append(.delete(a[i]))
                i += 1
            } else {
                result.append(.insert(b[j]))
                j += 1
            }
        }
        while i < n { result.append(.delete(a[i])); i += 1 }
        while j < m { result.append(.insert(b[j])); j += 1 }
        return result
    }
}

extension String {
    /// Splits on `"\n"` into logical lines (an empty string is one empty line).
    func splitIntoLines() -> [String] { components(separatedBy: "\n") }
}
