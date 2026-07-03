import Foundation

/// The outline operations the editor UI can invoke. The shell routes every toolbar button and
/// keyboard shortcut through `OutlineEngine.apply(_:text:selection:)`, so command dispatch is
/// pure and headless-testable and the UI layer holds no outline logic of its own.
public enum OutlineCommand: String, Sendable, Equatable, CaseIterable {
    case toggleBullet
    case toggleNumber
    case indent
    case outdent
    case moveLineUp
    case moveLineDown
    case insertNewline
}

public extension OutlineEngine {
    func apply(_ command: OutlineCommand, text: String, selection: TextSelection) -> TextEdit {
        switch command {
        case .toggleBullet: return toggleBullet(text: text, selection: selection)
        case .toggleNumber: return toggleNumber(text: text, selection: selection)
        case .indent: return indent(text: text, selection: selection)
        case .outdent: return outdent(text: text, selection: selection)
        case .moveLineUp: return moveLineUp(text: text, selection: selection)
        case .moveLineDown: return moveLineDown(text: text, selection: selection)
        case .insertNewline: return insertNewline(text: text, selection: selection)
        }
    }
}
