import XCTest
@testable import DevNotesCore

final class KeymapTests: XCTestCase {
    // MARK: - Chord parsing

    func testParsesModifiersAndNamedKey() {
        let chord = KeyChord.parse("ctrl+alt+up")
        XCTAssertEqual(chord, KeyChord(modifiers: [.control, .option], key: "up"))
    }

    func testParsesModifierAliases() {
        XCTAssertEqual(KeyChord.parse("command+option+n"),
                       KeyChord(modifiers: [.command, .option], key: "n"))
        XCTAssertEqual(KeyChord.parse("opt+ctrl+w"),
                       KeyChord(modifiers: [.option, .control], key: "w"))
    }

    func testParsesBareKey() {
        XCTAssertEqual(KeyChord.parse("tab"), KeyChord(modifiers: [], key: "tab"))
    }

    func testKeyIsCaseInsensitive() {
        XCTAssertEqual(KeyChord.parse("Shift+Cmd+N"),
                       KeyChord(modifiers: [.shift, .command], key: "n"))
    }

    func testRejectsUnknownModifier() {
        XCTAssertNil(KeyChord.parse("hyper+n"))
    }

    func testRejectsEmpty() {
        XCTAssertNil(KeyChord.parse(""))
    }

    // MARK: - Serialization / display

    func testSerializedIsCanonicalOrder() {
        // Insertion order shouldn't matter: modifiers always emit ⌃⌥⇧⌘ order.
        let chord = KeyChord(modifiers: [.command, .shift], key: "n")
        XCTAssertEqual(chord.serialized, "shift+cmd+n")
    }

    func testDisplaySymbols() {
        XCTAssertEqual(KeyChord(modifiers: [.shift, .command], key: "up").displaySymbols, "⇧⌘↑")
        XCTAssertEqual(KeyChord(modifiers: [.control, .option], key: "down").displaySymbols, "⌃⌥↓")
        XCTAssertEqual(KeyChord(modifiers: [], key: "tab").displaySymbols, "⇥")
    }

    func testRoundTripsThroughSerialization() {
        let chord = KeyChord(modifiers: [.option, .command], key: "up")
        XCTAssertEqual(KeyChord.parse(chord.serialized), chord)
    }

    // MARK: - Defaults

    func testDefaultsBindEveryAction() {
        for action in KeymapAction.allCases {
            XCTAssertNotNil(Keymap.defaults.chord(for: action), "\(action) has no default binding")
        }
    }

    func testDefaultsHaveNoDuplicateChords() {
        let chords = KeymapAction.allCases.compactMap { Keymap.defaults.chord(for: $0) }
        XCTAssertEqual(Set(chords).count, chords.count, "default keymap has a duplicate chord")
    }

    func testDefaultReverseLookup() {
        let chord = KeyChord(modifiers: [.control, .option], key: "up")
        XCTAssertEqual(Keymap.defaults.action(for: chord), .moveLineUp)
        XCTAssertNil(Keymap.defaults.action(for: KeyChord(modifiers: [.command], key: "z")))
    }

    // MARK: - Loading / merging

    func testLoadOverridesOneBinding() {
        let (keymap, warnings) = Keymap.load(from: ["indent": "cmd+]"])
        XCTAssertEqual(keymap.chord(for: .indent), KeyChord(modifiers: [.command], key: "]"))
        // Everything else keeps its default.
        XCTAssertEqual(keymap.chord(for: .nextNote), Keymap.defaults.chord(for: .nextNote))
        XCTAssertTrue(warnings.isEmpty)
    }

    func testLoadKeepsAllActionsBoundWhenUserFileIsPartial() {
        let (keymap, _) = Keymap.load(from: ["wrapText": "cmd+shift+e"])
        for action in KeymapAction.allCases {
            XCTAssertNotNil(keymap.chord(for: action))
        }
    }

    func testLoadWarnsOnUnknownActionAndKeepsDefaults() {
        let (keymap, warnings) = Keymap.load(from: ["frobnicate": "cmd+f"])
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertEqual(keymap.bindings.count, KeymapAction.allCases.count)
    }

    func testLoadWarnsOnUnparseableChordAndKeepsDefault() {
        let (keymap, warnings) = Keymap.load(from: ["indent": "hyper+q"])
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertEqual(keymap.chord(for: .indent), Keymap.defaults.chord(for: .indent))
    }

    func testLoadWarnsOnDuplicateChord() {
        // Rebind nextNote onto the indent chord => collision.
        let (_, warnings) = Keymap.load(from: ["nextNote": "tab"])
        XCTAssertTrue(warnings.contains { $0.contains("bound to both") })
    }

    func testSerializedContainsEveryAction() {
        let serialized = Keymap.defaults.serialized
        XCTAssertEqual(Set(serialized.keys), Set(KeymapAction.allCases.map(\.rawValue)))
    }
}
