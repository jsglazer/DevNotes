import Foundation

/// Every editor/navigation function that a keyboard shortcut can be bound to. This is the closed
/// catalog the shell dispatches against and that the seeded `keymap.json` + Settings list are
/// generated from — so "which functions can be bound?" has exactly one source of truth.
///
/// The `rawValue` is the stable key written to `keymap.json` (user-editable), so renaming a case
/// is a breaking change to existing user files. `title` is the human label shown in menus/Settings.
public enum KeymapAction: String, Sendable, CaseIterable, Equatable {
    case indent
    case unindent
    case moveLineUp
    case moveLineDown
    case nextNote
    case previousNote
    case selectToTop
    case selectToBottom
    case wrapText
    case showLineNumbers

    /// Human-readable label for menus and the Settings shortcuts list.
    public var title: String {
        switch self {
        case .indent: return "Indent"
        case .unindent: return "Unindent"
        case .moveLineUp: return "Move Line Up"
        case .moveLineDown: return "Move Line Down"
        case .nextNote: return "Next Note"
        case .previousNote: return "Previous Note"
        case .selectToTop: return "Select to Top of Note"
        case .selectToBottom: return "Select to Bottom of Note"
        case .wrapText: return "Wrap Text"
        case .showLineNumbers: return "Show Line Numbers"
        }
    }
}
