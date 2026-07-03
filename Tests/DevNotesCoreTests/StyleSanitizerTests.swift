import Testing
@testable import DevNotesCore

@Suite("StyleSanitizer")
struct StyleSanitizerTests {
    @Test("Known tokens with valid values are accepted and typed")
    func acceptsKnownTokens() {
        let sheet = StyleSanitizer.sanitize("font-size: 14; text-color: #ffcc00; font-family: Menlo; font-weight: bold")
        #expect(sheet.tokens[.fontSize] == .size(14))
        #expect(sheet.tokens[.textColor] == .color("#ffcc00"))
        #expect(sheet.tokens[.fontFamily] == .fontFamily("Menlo"))
        #expect(sheet.tokens[.fontWeight] == .fontWeight(.named("bold")))
        #expect(sheet.rejected.isEmpty)
    }

    @Test("Unknown tokens are rejected, not applied")
    func rejectsUnknownToken() {
        let sheet = StyleSanitizer.sanitize("color: red; position: absolute")
        #expect(sheet.tokens.isEmpty)
        #expect(sheet.rejected.count == 2)
    }

    @Test("Known token with an out-of-range value is rejected")
    func rejectsInvalidValue() {
        let sheet = StyleSanitizer.sanitize("font-size: 9999")
        #expect(sheet.tokens[.fontSize] == nil)
        #expect(sheet.rejected.count == 1)
    }

    @Test("Sizes accept unit suffixes")
    func parsesSizesWithUnits() {
        #expect(StyleSanitizer.parseSize("14px") == 14)
        #expect(StyleSanitizer.parseSize("18pt") == 18)
        #expect(StyleSanitizer.parseSize("0") == nil)
        #expect(StyleSanitizer.parseSize("abc") == nil)
    }

    @Test("Colors accept only #rgb / #rrggbb / #rrggbbaa hex")
    func parsesColors() {
        #expect(StyleSanitizer.parseColor("#fff") == "#fff")
        #expect(StyleSanitizer.parseColor("#FFCC00") == "#ffcc00")
        #expect(StyleSanitizer.parseColor("#12") == nil)
        #expect(StyleSanitizer.parseColor("red") == nil)
    }

    @Test("Font family rejects anything that could break out of a token")
    func rejectsDangerousFontFamily() {
        #expect(StyleSanitizer.parseFontFamily("Helvetica Neue") == "Helvetica Neue")
        #expect(StyleSanitizer.parseFontFamily("url(evil.css)") == nil)
        #expect(StyleSanitizer.parseFontFamily("a; }") == nil)
    }

    @Test("Font weight accepts named and numeric forms")
    func parsesFontWeight() {
        #expect(StyleSanitizer.parseFontWeight("semibold") == .named("semibold"))
        #expect(StyleSanitizer.parseFontWeight("600") == .numeric(600))
        #expect(StyleSanitizer.parseFontWeight("obese") == nil)
    }
}
