import Foundation

/// Computes the smallest single contiguous replacement that turns one string into another, in
/// UTF-16 units so the result maps directly onto `NSTextStorage.replaceCharacters(in:with:)`.
/// The editor's Return handling uses this so a list continuation edits only the line it touches —
/// replacing the whole document re-laid the entire TextKit 2 viewport on every Return, which is
/// what made the view lurch each time Return was hit.
public enum TextDiff {
    /// The minimal `(range, replacement)` such that replacing `range` in `old` with `replacement`
    /// yields `new`, or nil when the strings are already equal. Boundaries never split a
    /// surrogate pair.
    public static func minimalEdit(from old: String, to new: String) -> (range: NSRange, replacement: String)? {
        let oldNS = old as NSString
        let newNS = new as NSString
        guard old != new else { return nil }

        var prefix = 0
        let maxPrefix = min(oldNS.length, newNS.length)
        while prefix < maxPrefix, oldNS.character(at: prefix) == newNS.character(at: prefix) {
            prefix += 1
        }
        // Both strings share the character before `prefix`, so backing off applies to both.
        while prefix > 0, UTF16.isLeadSurrogate(oldNS.character(at: prefix - 1)) {
            prefix -= 1
        }

        var oldEnd = oldNS.length
        var newEnd = newNS.length
        while oldEnd > prefix, newEnd > prefix, oldNS.character(at: oldEnd - 1) == newNS.character(at: newEnd - 1) {
            oldEnd -= 1
            newEnd -= 1
        }
        // The suffixes are identical, so extending past a trail surrogate stays in bounds on both.
        while oldEnd < oldNS.length, UTF16.isTrailSurrogate(oldNS.character(at: oldEnd)) {
            oldEnd += 1
            newEnd += 1
        }

        let range = NSRange(location: prefix, length: oldEnd - prefix)
        let replacement = newNS.substring(with: NSRange(location: prefix, length: newEnd - prefix))
        return (range, replacement)
    }
}
