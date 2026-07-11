#if os(macOS)
import AppKit

/// A line-number gutter for the macOS editor, drawn as a **fixed (non-scrolling) overlay** over a
/// left text inset — the same design the iOS editor uses (`IOSLineNumberGutter`), NOT an
/// `NSRulerView`.
///
/// The ruler approach was abandoned: toggling `NSScrollView.rulersVisible` on a TextKit 2 text view
/// retiles the scroll view and reliably left the viewport blank — the text vanished the instant line
/// numbers were switched on and nothing (scroll, click, forced relayout) brought it back. This
/// gutter never touches the scroll view's tiling: the text view keeps its full width and simply
/// gains a left `textContainerInset`, and the gutter floats over that inset reading the text view's
/// live layout + scroll offset. Changing an inset is a routine TextKit 2 operation (iOS does exactly
/// this and never blanks), so the text stays put.
final class MacLineNumberGutter: NSView {
    /// Width of the gutter strip; the editor sets the text view's left inset to match when the gutter
    /// is shown, so the text clears the numbers.
    static let width: CGFloat = 40

    private weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 0))
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Draw top-down so fragment Y (measured from the top of the text) maps straight to a label Y.
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Opaque background + trailing separator, so the strip reads as a distinct gutter and the
        // text's left inset never shows the window background through it.
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        NSColor.gray.withAlphaComponent(0.08).setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        separator.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        separator.stroke()

        guard let textView,
              let scrollView,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange
        else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let string = textView.string as NSString
        let inset = textView.textContainerInset.height
        // How far the document is scrolled: a fragment at document-Y = D shows at visible-Y =
        // D + inset − scrollY, and this flipped gutter's Y=0 is pinned to the top of the visible area.
        let scrollY = scrollView.contentView.bounds.origin.y
        let documentStart = contentManager.documentRange.location

        // Number only the fragments the viewport has ALREADY laid out (never `.ensuresLayout`, which
        // would force a full-document layout on every gutter redraw), advancing the line count from
        // one fragment to the next instead of rescanning the whole prefix per fragment.
        var lineNumber = 1
        var countedTo = 0
        layoutManager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            guard fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedAscending else {
                return false
            }
            let offset = min(contentManager.offset(from: documentStart, to: fragment.rangeInElement.location), string.length)
            lineNumber += string.newlineCount(in: NSRange(location: countedTo, length: max(0, offset - countedTo)))
            countedTo = max(countedTo, offset)

            let fragmentFrame = fragment.layoutFragmentFrame
            let y = fragmentFrame.minY + inset - scrollY
            // Only draw fragments within the visible strip.
            if y + fragmentFrame.height >= bounds.minY, y <= bounds.maxY {
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
