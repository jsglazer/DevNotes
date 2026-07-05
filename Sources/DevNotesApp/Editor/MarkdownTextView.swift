import DevNotesCore
import SwiftUI

/// A native **TextKit 2** editing surface (NOT a WebView) — required for launch speed and for
/// the cursor/selection control the outline operations depend on. It binds two-way to the
/// editor's `text` and `selection`, applies the sanitised `StyleSheet` (plus live Markdown syntax
/// coloring) to the text container, continues list markers on Return, and honours the View-menu
/// preferences for soft-wrapping and the line-number gutter.
struct MarkdownTextView: View {
    @Binding var text: String
    @Binding var selection: DevNotesCore.TextSelection
    var style: StyleSheet
    var wrapText: Bool = true
    var showLineNumbers: Bool = false

    var body: some View {
        MarkdownTextViewRepresentable(
            text: $text,
            selection: $selection,
            style: style,
            wrapText: wrapText,
            showLineNumbers: showLineNumbers
        )
    }
}

#if os(macOS)
import AppKit

private struct MarkdownTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: DevNotesCore.TextSelection
    var style: StyleSheet
    var wrapText: Bool
    var showLineNumbers: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // `usingTextLayoutManager: true` selects the TextKit 2 stack.
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        // Line-number gutter (drawn on demand; visibility toggled in updateNSView).
        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        context.coordinator.ruler = ruler

        // Invalidate the gutter as the user scrolls.
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observeBoundsChanges(of: scrollView.contentView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
        }
        applyWrapping(to: textView, in: scrollView)

        textView.typingAttributes = StyleApplier().bodyAttributes(from: style)
        if let storage = textView.textStorage {
            MarkdownHighlighter(style: style).apply(to: storage)
        }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)

        let desired = NSRange(location: selection.location, length: selection.length)
        if textView.selectedRange() != desired, NSMaxRange(desired) <= fullRange.length {
            textView.setSelectedRange(desired)
        }

        scrollView.rulersVisible = showLineNumbers
        context.coordinator.ruler?.needsDisplay = true
    }

    /// Configures soft-wrap vs. horizontal-scroll on the text container.
    private func applyWrapping(to textView: NSTextView, in scrollView: NSScrollView) {
        guard let container = textView.textContainer else { return }
        if wrapText {
            container.widthTracksTextView = true
            let width = scrollView.contentSize.width
            container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = false
        } else {
            container.widthTracksTextView = false
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = [.width, .height]
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextViewRepresentable
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?
        private let engine = OutlineEngine()

        init(_ parent: MarkdownTextViewRepresentable) { self.parent = parent }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func observeBoundsChanges(of view: NSView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: view
            )
        }

        @MainActor @objc private func boundsDidChange(_ notification: Notification) {
            ruler?.needsDisplay = true
        }

        /// Intercepts Return to continue (or exit) a list marker via the pure `OutlineEngine`,
        /// so bullets and numbered items auto-continue on the next line.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let range = textView.selectedRange()
            let selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
            let edit = engine.insertNewline(text: textView.string, selection: selection)

            let full = NSRange(location: 0, length: (textView.string as NSString).length)
            if textView.shouldChangeText(in: full, replacementString: edit.text) {
                textView.textStorage?.replaceCharacters(in: full, with: edit.text)
                textView.didChangeText()
            }
            textView.setSelectedRange(NSRange(location: edit.selection.location, length: edit.selection.length))
            parent.text = edit.text
            parent.selection = edit.selection
            if let storage = textView.textStorage {
                MarkdownHighlighter(style: parent.style).apply(to: storage)
            }
            ruler?.needsDisplay = true
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.selection = DevNotesCore.TextSelection(location: textView.selectedRange().location, length: textView.selectedRange().length)
            if let storage = textView.textStorage {
                MarkdownHighlighter(style: parent.style).apply(to: storage)
            }
            ruler?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            parent.selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
        }
    }
}

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

        // Gutter background + trailing separator.
        NSColor.textBackgroundColor.withAlphaComponent(0.4).setFill()
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

#elseif os(iOS)
import UIKit

private struct MarkdownTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: DevNotesCore.TextSelection
    var style: StyleSheet
    var wrapText: Bool
    var showLineNumbers: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> EditorContainerView {
        // UITextView uses the TextKit 2 stack by default on iOS 16+.
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.autocorrectionType = .no
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.backgroundColor = .clear
        let container = EditorContainerView(textView: textView)
        context.coordinator.container = container
        return container
    }

    func updateUIView(_ container: EditorContainerView, context: Context) {
        context.coordinator.parent = self
        let textView = container.textView
        if textView.text != text {
            textView.text = text
        }
        textView.typingAttributes = StyleApplier().bodyAttributes(from: style)
        MarkdownHighlighter(style: style).apply(to: textView.textStorage)

        let length = (textView.text as NSString).length
        let desired = NSRange(location: selection.location, length: selection.length)
        if NSMaxRange(desired) <= length {
            textView.selectedRange = desired
        }
        if container.showLineNumbers != showLineNumbers {
            container.showLineNumbers = showLineNumbers
        }
        container.gutter.setNeedsDisplay()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextViewRepresentable
        weak var container: EditorContainerView?
        private let engine = OutlineEngine()

        init(_ parent: MarkdownTextViewRepresentable) { self.parent = parent }

        /// Intercepts Return to continue (or exit) a list marker via the pure `OutlineEngine`.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            let selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
            let edit = engine.insertNewline(text: textView.text, selection: selection)
            textView.text = edit.text
            textView.typingAttributes = StyleApplier().bodyAttributes(from: parent.style)
            MarkdownHighlighter(style: parent.style).apply(to: textView.textStorage)
            textView.selectedRange = NSRange(location: edit.selection.location, length: edit.selection.length)
            parent.text = edit.text
            parent.selection = edit.selection
            container?.gutter.setNeedsDisplay()
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            MarkdownHighlighter(style: parent.style).apply(to: textView.textStorage)
            let range = textView.selectedRange
            parent.selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
            container?.gutter.setNeedsDisplay()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            parent.selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            container?.gutter.setNeedsDisplay()
        }
    }
}

/// Hosts the editor's `UITextView` and an optional line-number gutter drawn to its left. The
/// gutter is a non-scrolling overlay that reads the text view's live layout + scroll offset, so it
/// stays aligned as the user types and scrolls.
final class EditorContainerView: UIView {
    let textView: UITextView
    let gutter: IOSLineNumberGutter
    private let gutterWidth: CGFloat = 40

    var showLineNumbers = false {
        didSet {
            gutter.isHidden = !showLineNumbers
            var inset = textView.textContainerInset
            inset.left = showLineNumbers ? gutterWidth + 4 : 8
            textView.textContainerInset = inset
            gutter.setNeedsDisplay()
        }
    }

    init(textView: UITextView) {
        self.textView = textView
        self.gutter = IOSLineNumberGutter(textView: textView)
        super.init(frame: .zero)
        addSubview(textView)
        addSubview(gutter)
        gutter.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        gutter.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        gutter.setNeedsDisplay()
    }
}

/// The iOS counterpart to `LineNumberRulerView`: numbers logical lines by enumerating the layout
/// fragments and counting preceding newlines, offset by the text view's scroll position.
final class IOSLineNumberGutter: UIView {
    private weak var textView: UITextView?

    init(textView: UITextView) {
        self.textView = textView
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let textView,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return }

        UIColor.secondarySystemBackground.withAlphaComponent(0.6).setFill()
        UIRectFill(rect)
        let separator = UIBezierPath()
        separator.move(to: CGPoint(x: bounds.maxX - 0.5, y: rect.minY))
        separator.addLine(to: CGPoint(x: bounds.maxX - 0.5, y: rect.maxY))
        UIColor.separator.setStroke()
        separator.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]

        let string = textView.text as NSString
        let insetTop = textView.textContainerInset.top
        let offsetY = textView.contentOffset.y
        let documentStart = contentManager.documentRange.location

        layoutManager.enumerateTextLayoutFragments(
            from: contentManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame
            let y = fragmentFrame.minY + insetTop - offsetY

            if y + fragmentFrame.height >= rect.minY, y <= rect.maxY {
                let offset = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
                let lineNumber = string.substring(to: min(offset, string.length))
                    .reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
                let label = "\(lineNumber)" as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: CGPoint(x: bounds.maxX - size.width - 6, y: y),
                    withAttributes: attributes
                )
            }
            return true
        }
    }
}
#endif
