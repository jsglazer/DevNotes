import Foundation

/// Finds the link a character offset falls inside, so both editor surfaces can open the URL under a
/// long press without either platform re-implementing the detection. `NSDataDetector` spans bare
/// URLs and the address part of `[text](url)` alike.
public enum LinkDetector {
    /// The URL whose text range contains `offset`, or nil when the offset isn't inside a link.
    public static func url(in text: String, at offset: Int) -> URL? {
        let ns = text as NSString
        guard ns.length > 0, offset >= 0, offset <= ns.length,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        return detector
            .matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            .first { NSLocationInRange(offset, $0.range) }?
            .url
    }
}
