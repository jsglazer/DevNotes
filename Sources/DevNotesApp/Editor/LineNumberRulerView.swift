#if os(macOS)
import AppKit

/// A gutter that numbers logical (paragraph) lines beside the TextKit 2 text view. It enumerates
/// the layout fragments the layout manager has produced and labels each one by the number of
/// newlines that precede its start — soft-wrapped continuations keep the paragraph's single
/// number, matching common editor behaviour.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return }

        // Gutter background + trailing separator. Painted OPAQUE (the editor background plus a faint
        // tint) so the gutter reads as a distinct strip without the old translucent fill, which let
        // the window background show through and made the whole editor look dimmed.
        NSColor.textBackgroundColor.setFill()
        rect.fill()
        NSColor.gray.withAlphaComponent(0.08).setFill()
        rect.fill()
        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.maxX - 0.5, y: rect.minY))
        separator.line(to: NSPoint(x: bounds.maxX - 0.5, y: rect.maxY))
        separator.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let string = textView.string as NSString
        let inset = textView.textContainerInset.height
        let yOffset = convert(NSPoint.zero, from: textView).y
        let documentStart = contentManager.documentRange.location

        layoutManager.enumerateTextLayoutFragments(
            from: contentManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame
            let y = yOffset + fragmentFrame.minY + inset

            // Only draw fragments that fall within the dirty rect.
            if y + fragmentFrame.height >= rect.minY, y <= rect.maxY {
                let offset = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
                let lineNumber = string.substring(to: min(offset, string.length))
                    .reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
                let label = "\(lineNumber)" as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: NSPoint(x: bounds.maxX - size.width - 6, y: y),
                    withAttributes: attributes
                )
            }
            return true
        }
    }
}
#endif
