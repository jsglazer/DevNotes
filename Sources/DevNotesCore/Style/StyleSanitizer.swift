import Foundation

/// The BOUNDED set of style tokens the editor honours. "Custom CSS" is NOT arbitrary CSS
/// executed in a WebView — it is only these known keys applied to the native attributed-string
/// renderer. Anything outside this set is rejected. This is how the §4 "CSS sanitised"
/// reviewer criterion is met.
public enum StyleTokenKey: String, CaseIterable, Sendable {
    case fontFamily = "font-family"
    case fontSize = "font-size"
    case fontWeight = "font-weight"
    case textColor = "text-color"
    case backgroundColor = "background-color"
    case accentColor = "accent-color"
    case lineSpacing = "line-spacing"
    case paragraphSpacing = "paragraph-spacing"
    case heading1Size = "heading1-size"
    case heading2Size = "heading2-size"
    case heading3Size = "heading3-size"
    case headingColor = "heading-color"
}

public enum FontWeightToken: Equatable, Sendable {
    case named(String)
    case numeric(Int)
}

/// A validated, typed style value. Only these shapes can exist — there is no path to an
/// arbitrary string reaching the renderer.
public enum StyleValue: Equatable, Sendable {
    case size(Double)
    case color(String) // normalised "#rrggbb" / "#rrggbbaa"
    case fontFamily(String)
    case fontWeight(FontWeightToken)
}

public struct RejectedDeclaration: Equatable, Sendable {
    public var raw: String
    public var reason: String
    public init(raw: String, reason: String) {
        self.raw = raw
        self.reason = reason
    }
}

/// The result of sanitising user style input: the accepted, typed tokens plus every rejected
/// declaration and why.
public struct StyleSheet: Equatable, Sendable {
    public var tokens: [StyleTokenKey: StyleValue]
    public var rejected: [RejectedDeclaration]

    public init(tokens: [StyleTokenKey: StyleValue] = [:], rejected: [RejectedDeclaration] = []) {
        self.tokens = tokens
        self.rejected = rejected
    }
}

/// Parses `key: value;` declarations and accepts ONLY known tokens with valid values,
/// rejecting everything else. Pure and deterministic.
public enum StyleSanitizer {
    private static let namedWeights: Set<String> = [
        "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"
    ]

    public static func sanitize(_ input: String) -> StyleSheet {
        var sheet = StyleSheet()
        let declarations = input
            .replacingOccurrences(of: "\n", with: ";")
            .components(separatedBy: ";")

        for rawDeclaration in declarations {
            let declaration = rawDeclaration.trimmingCharacters(in: .whitespaces)
            guard declaration.isEmpty == false else { continue }
            guard let colon = declaration.firstIndex(of: ":") else {
                sheet.rejected.append(RejectedDeclaration(raw: declaration, reason: "missing ':' separator"))
                continue
            }
            let keyText = declaration[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let valueText = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            guard let key = StyleTokenKey(rawValue: keyText) else {
                sheet.rejected.append(RejectedDeclaration(raw: declaration, reason: "unknown token '\(keyText)'"))
                continue
            }
            guard let value = validate(key: key, value: valueText) else {
                sheet.rejected.append(RejectedDeclaration(raw: declaration, reason: "invalid value for '\(keyText)'"))
                continue
            }
            sheet.tokens[key] = value
        }
        return sheet
    }

    private static func validate(key: StyleTokenKey, value: String) -> StyleValue? {
        switch key {
        case .fontSize, .lineSpacing, .paragraphSpacing, .heading1Size, .heading2Size, .heading3Size:
            return parseSize(value).map(StyleValue.size)
        case .textColor, .backgroundColor, .accentColor, .headingColor:
            return parseColor(value).map(StyleValue.color)
        case .fontFamily:
            return parseFontFamily(value).map(StyleValue.fontFamily)
        case .fontWeight:
            return parseFontWeight(value).map(StyleValue.fontWeight)
        }
    }

    static func parseSize(_ value: String) -> Double? {
        var text = value.lowercased()
        for unit in ["px", "pt", "em", "rem"] where text.hasSuffix(unit) {
            text = String(text.dropLast(unit.count))
        }
        text = text.trimmingCharacters(in: .whitespaces)
        guard let number = Double(text), number > 0, number <= 400 else { return nil }
        return number
    }

    static func parseColor(_ value: String) -> String? {
        guard value.hasPrefix("#") else { return nil }
        let hex = value.dropFirst().lowercased()
        guard hex.count == 3 || hex.count == 6 || hex.count == 8 else { return nil }
        guard hex.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + hex
    }

    static func parseFontFamily(_ value: String) -> String? {
        guard value.isEmpty == false else { return nil }
        // Reject anything that could break out of a token: CSS punctuation, url(), etc.
        let allowed = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-_,'\""))
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value.trimmingCharacters(in: .whitespaces)
    }

    static func parseFontWeight(_ value: String) -> FontWeightToken? {
        let lowered = value.lowercased()
        if namedWeights.contains(lowered) { return .named(lowered) }
        if let number = Int(lowered), (1 ... 1000).contains(number) { return .numeric(number) }
        return nil
    }
}
