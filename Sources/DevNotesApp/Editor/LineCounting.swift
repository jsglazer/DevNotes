import Foundation

extension NSString {
    /// Number of `\n` characters inside `range`. The line-number gutters use this to advance
    /// their count from one laid-out fragment to the next, instead of rescanning the whole
    /// prefix per fragment (which made gutter drawing O(document²)).
    func newlineCount(in range: NSRange) -> Int {
        guard range.length > 0, NSMaxRange(range) <= length else { return 0 }
        var count = 0
        var location = range.location
        let end = NSMaxRange(range)
        while location < end {
            let found = self.range(of: "\n", options: [], range: NSRange(location: location, length: end - location))
            guard found.location != NSNotFound else { break }
            count += 1
            location = found.location + 1
        }
        return count
    }
}
