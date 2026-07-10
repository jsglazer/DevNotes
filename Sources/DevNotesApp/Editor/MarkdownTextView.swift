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
    var spellCheck: Bool = true
    /// Text-zoom multiplier (⌘+/⌘-) applied to the note's fonts.
    var zoom: Double = 1
    /// Background band painted behind the caret's line, or nil when the current-line highlight is
    /// off. Already resolved for the active light/dark theme by the model.
    var currentLineHighlight: PlatformColor?
    /// Extra scrollable space kept below the last line (points), so the caret never sits against
    /// the bottom edge and the final lines can scroll up into view.
    var bottomPadding: Double = 0
    /// Find/Replace overlay: every match range (highlighted faintly) and the current one
    /// (highlighted strongly). macOS only; empty/nil elsewhere.
    var searchMatches: [DevNotesCore.TextSelection] = []
    var currentMatch: DevNotesCore.TextSelection?
    /// Bumped by the model to ask the editor to take keyboard focus (new/opened note).
    var focusRequest = 0
    /// Resolves a pressed key chord to a keymap action; returns true when handled so the editor
    /// consumes the event. Provided by the shell (macOS only); iOS ignores it.
    var onKeyChord: (@MainActor (DevNotesCore.KeyChord) -> Bool)?

    var body: some View {
        MarkdownTextViewRepresentable(
            text: $text,
            selection: $selection,
            style: style,
            wrapText: wrapText,
            showLineNumbers: showLineNumbers,
            spellCheck: spellCheck,
            zoom: zoom,
            currentLineHighlight: currentLineHighlight,
            bottomPadding: bottomPadding,
            searchMatches: searchMatches,
            currentMatch: currentMatch,
            focusRequest: focusRequest,
            onKeyChord: onKeyChord
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
    var spellCheck: Bool
    var zoom: Double
    var currentLineHighlight: PlatformColor?
    var bottomPadding: Double
    var searchMatches: [DevNotesCore.TextSelection]
    var currentMatch: DevNotesCore.TextSelection?
    var focusRequest: Int
    var onKeyChord: (@MainActor (DevNotesCore.KeyChord) -> Bool)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // `usingTextLayoutManager: true` selects the TextKit 2 stack. `EditorTextView` overrides
        // `keyDown` so the user's keymap (indent/outdent/select-to-edge) is honoured before the
        // field editor's default handling.
        let textView = EditorTextView(usingTextLayoutManager: true)
        textView.onKeyChord = onKeyChord
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        // Basic spell checking only: continuous red-squiggle checking, but never grammar checks or
        // automatic text/spelling substitutions (those rewrite code and identifiers unbidden).
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isGrammarCheckingEnabled = false
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        // A bottom content inset is scroll-past-end room: the caret on the last line no longer sits
        // flush against the window edge, and the final lines can scroll up into view.
        scrollView.automaticallyAdjustsContentInsets = false

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
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        context.coordinator.parent = self
        textView.onKeyChord = onKeyChord

        // Current-line band: hand the colour to the view and force a redraw when it changes (toggled
        // on/off, theme switched, or a new colour picked in Settings).
        if context.coordinator.currentLineHighlightChanged(currentLineHighlight) {
            textView.currentLineHighlight = currentLineHighlight
            textView.needsDisplay = true
        }
        // A zoom change must re-run the (font-sizing) syntax pass over the whole note.
        if context.coordinator.zoomChanged(zoom) {
            context.coordinator.invalidateHighlight()
        }

        let bottomInset = CGFloat(max(0, bottomPadding))
        if scrollView.contentInsets.bottom != bottomInset {
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        }

        if textView.string != text {
            textView.string = text
            // Resetting the string wipes attribute runs — re-colour is mandatory.
            context.coordinator.invalidateHighlight()
        }
        applyWrapping(to: textView, in: scrollView, coordinator: context.coordinator)

        if textView.isContinuousSpellCheckingEnabled != spellCheck {
            textView.isContinuousSpellCheckingEnabled = spellCheck
        }
        // Toggling the gutter must never change the note's font colour.
        if context.coordinator.showLineNumbersChanged(showLineNumbers) {
            context.coordinator.invalidateHighlight()
        }

        textView.typingAttributes = StyleApplier(zoom: CGFloat(zoom)).bodyAttributes(from: style)
        // Re-highlight only when the text or style actually changed. The delegate callbacks
        // already highlight after each edit, and this update pass runs right behind them — without
        // this guard every keystroke paid for the full syntax pass twice.
        if context.coordinator.needsHighlight(text: textView.string, style: style),
           let storage = textView.textStorage {
            // Re-colouring re-lays the TextKit 2 viewport, which can shake the scroll position;
            // pin it so a background re-highlight never makes the screen jump under the reader.
            context.coordinator.preservingScroll(of: scrollView) {
                MarkdownHighlighter(style: style, zoom: CGFloat(zoom)).apply(to: storage)
            }
            context.coordinator.didHighlight(text: textView.string, style: style)
        }
        context.coordinator.applySearchHighlight(matches: searchMatches, current: currentMatch)
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)

        let desired = NSRange(location: selection.location, length: selection.length)
        if textView.selectedRange() != desired, NSMaxRange(desired) <= fullRange.length {
            textView.setSelectedRange(desired)
            // Keep the caret on-screen after a command-driven selection change (move line,
            // select-to-edge, open-at-last-line) — the view no longer scrolls it off the bottom.
            textView.scrollRangeToVisible(desired)
        }

        // A bumped focus token asks the editor to take first responder (new/opened note) so the
        // caret is live without a click. Deferred so it runs after this layout pass settles.
        if context.coordinator.focusRequestChanged(focusRequest) {
            DispatchQueue.main.async { [weak textView] in
                guard let textView, let window = textView.window else { return }
                window.makeFirstResponder(textView)
            }
        }

        scrollView.rulersVisible = showLineNumbers
        context.coordinator.ruler?.needsDisplay = true
    }

    /// Configures soft-wrap vs. horizontal-scroll on the text container. Idempotent: skips the work
    /// when the mode and width already match what was last applied — re-setting the container size
    /// every observable update (each keystroke, each autosave refresh) forced a relayout that
    /// jostled the scroll position.
    private func applyWrapping(to textView: NSTextView, in scrollView: NSScrollView, coordinator: Coordinator) {
        guard let container = textView.textContainer else { return }
        let width = scrollView.contentSize.width
        if coordinator.wrappingUnchanged(wrapText: wrapText, width: width) { return }
        if wrapText {
            container.widthTracksTextView = true
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

        /// The text/style the highlighter last ran over, so the SwiftUI update pass can skip
        /// re-highlighting content the delegate callbacks already styled.
        private var highlightedText: String?
        private var highlightedStyle: StyleSheet?
        /// Last-seen gutter state, so a line-number toggle can force a re-colour.
        private var lastShowLineNumbers: Bool?
        /// Last-honoured focus token, so a note open focuses the editor exactly once per bump.
        private var lastFocusRequest = 0
        /// True while find-match backgrounds are painted, so we only pay to clear them when some
        /// were actually applied (never on the ordinary typing path with the bar closed).
        private var hasSearchHighlight = false

        /// Last wrap mode + width applied to the container, so `applyWrapping` can skip redundant
        /// (relayout-inducing) reconfiguration on every observable update.
        private var appliedWrapText: Bool?
        private var appliedWrapWidth: CGFloat?

        /// Last current-line colour + zoom pushed to the view, so an unchanged value doesn't force a
        /// wasteful full redraw / re-highlight on every keystroke.
        private var lastCurrentLineHighlight: PlatformColor?
        private var didApplyCurrentLineHighlight = false
        private var lastZoom: Double?

        func needsHighlight(text: String, style: StyleSheet) -> Bool {
            highlightedText != text || highlightedStyle != style
        }

        /// True when the current-line colour changed since the last update (records the new value).
        func currentLineHighlightChanged(_ color: PlatformColor?) -> Bool {
            defer { lastCurrentLineHighlight = color; didApplyCurrentLineHighlight = true }
            guard didApplyCurrentLineHighlight else { return true }
            return lastCurrentLineHighlight != color
        }

        /// True when the zoom changed since the last update (records the new value).
        func zoomChanged(_ value: Double) -> Bool {
            defer { lastZoom = value }
            return lastZoom != value
        }

        /// True when the wrap mode + width already match the last-applied configuration (and records
        /// the requested values so the first call for a given mode/width always applies).
        func wrappingUnchanged(wrapText: Bool, width: CGFloat) -> Bool {
            let unchanged = appliedWrapText == wrapText && appliedWrapWidth == width
            appliedWrapText = wrapText
            appliedWrapWidth = width
            return unchanged
        }

        /// Runs `work` (which re-applies attributes and can shake the TextKit 2 viewport) while
        /// pinning the clip view's scroll origin, so a re-colour never makes the screen jump.
        @MainActor
        func preservingScroll(of scrollView: NSScrollView, _ work: () -> Void) {
            let origin = scrollView.contentView.bounds.origin
            work()
            if scrollView.contentView.bounds.origin != origin {
                scrollView.contentView.setBoundsOrigin(origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        /// True when the model bumped the focus token since the last pass (records the new value).
        func focusRequestChanged(_ value: Int) -> Bool {
            defer { lastFocusRequest = value }
            return lastFocusRequest != value
        }

        /// Paints a faint background over every Find match and a stronger one over the current
        /// match. Cleared and repainted each pass so a changed query/cursor stays in sync; skipped
        /// entirely when there's nothing to show and nothing was shown last time.
        @MainActor
        func applySearchHighlight(matches: [DevNotesCore.TextSelection], current: DevNotesCore.TextSelection?) {
            guard let storage = textView?.textStorage else { return }
            guard matches.isEmpty == false || hasSearchHighlight else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: full)
            let all = NSColor.systemYellow.withAlphaComponent(0.35)
            let focused = NSColor.systemOrange.withAlphaComponent(0.6)
            for match in matches {
                let range = NSRange(location: match.location, length: match.length)
                guard NSMaxRange(range) <= storage.length else { continue }
                let color = (match == current) ? focused : all
                storage.addAttribute(.backgroundColor, value: color, range: range)
            }
            hasSearchHighlight = matches.isEmpty == false
        }

        func didHighlight(text: String, style: StyleSheet) {
            highlightedText = text
            highlightedStyle = style
        }

        /// Drops the highlight cache so the next update pass re-colours the whole note. Called
        /// whenever the storage is reset (`textView.string = …`), which wipes attribute runs: the
        /// syntax colours must be re-applied or the text falls back to the uniform default colour.
        func invalidateHighlight() {
            highlightedText = nil
        }

        /// True when the gutter visibility changed since the last update (and records the new
        /// value). Toggling line numbers must not leave the note text in the default colour.
        func showLineNumbersChanged(_ value: Bool) -> Bool {
            defer { lastShowLineNumbers = value }
            return lastShowLineNumbers != value
        }

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
                MarkdownHighlighter(style: parent.style, zoom: CGFloat(parent.zoom)).apply(to: storage)
                didHighlight(text: edit.text, style: parent.style)
            }
            textView.scrollRangeToVisible(textView.selectedRange())
            textView.needsDisplay = true
            ruler?.needsDisplay = true
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            let range = textView.selectedRange()
            parent.selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
            if let storage = textView.textStorage {
                // Pin the scroll position across the full-document re-colour, then follow the caret
                // ourselves — so re-colouring never jumps the view, but typing at the bottom still
                // keeps the caret on-screen.
                if let scrollView = textView.enclosingScrollView {
                    preservingScroll(of: scrollView) {
                        MarkdownHighlighter(style: parent.style, zoom: CGFloat(parent.zoom)).apply(to: storage)
                    }
                } else {
                    MarkdownHighlighter(style: parent.style, zoom: CGFloat(parent.zoom)).apply(to: storage)
                }
                didHighlight(text: textView.string, style: parent.style)
            }
            // Follow the caret as the user types so text added at the bottom isn't clipped.
            textView.scrollRangeToVisible(range)
            textView.needsDisplay = true
            ruler?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            parent.selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
            // Repaint so the current-line band follows the caret to its new line.
            if parent.currentLineHighlight != nil { textView.needsDisplay = true }
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
    var spellCheck: Bool
    var zoom: Double
    var currentLineHighlight: PlatformColor?
    var bottomPadding: Double
    /// Accepted for signature parity with macOS; the Find bar is macOS-only, so iOS ignores these.
    var searchMatches: [DevNotesCore.TextSelection]
    var currentMatch: DevNotesCore.TextSelection?
    var focusRequest: Int
    /// Accepted for signature parity with macOS; iOS uses hardware-keyboard commands elsewhere and
    /// does not route key events through the keymap here.
    var onKeyChord: (@MainActor (DevNotesCore.KeyChord) -> Bool)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> EditorContainerView {
        // UITextView uses the TextKit 2 stack by default on iOS 16+.
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.autocorrectionType = .no
        textView.spellCheckingType = spellCheck ? .yes : .no
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.backgroundColor = .clear
        let container = EditorContainerView(textView: textView)
        context.coordinator.container = container
        return container
    }

    func updateUIView(_ container: EditorContainerView, context: Context) {
        context.coordinator.parent = self
        let textView = container.textView
        let desiredSpellCheck: UITextSpellCheckingType = spellCheck ? .yes : .no
        if textView.spellCheckingType != desiredSpellCheck {
            textView.spellCheckingType = desiredSpellCheck
        }
        // Scroll-past-end room so the caret on the last line clears the keyboard/bottom edge.
        let bottomInset = CGFloat(max(0, bottomPadding))
        if textView.contentInset.bottom != bottomInset {
            textView.contentInset.bottom = bottomInset
        }
        // A text mismatch here means the model changed the text out-of-band (an outline command,
        // find/replace) — assigning `.text` resets the scroll position and selection, which was the
        // "screen jumps / goes blank after a menu command" report. Pin the scroll offset across the
        // reset so the view stays put.
        let preservedOffset = textView.contentOffset
        var didResetText = false
        if textView.text != text {
            textView.text = text
            // Resetting the string wipes attribute runs — re-colour is mandatory.
            context.coordinator.invalidateHighlight()
            didResetText = true
        }
        // Toggling the gutter must never change the note's font colour.
        if context.coordinator.showLineNumbersChanged(showLineNumbers) {
            context.coordinator.invalidateHighlight()
        }
        // A zoom change must re-run the (font-sizing) syntax pass over the whole note.
        if context.coordinator.zoomChanged(zoom) {
            context.coordinator.invalidateHighlight()
        }
        textView.typingAttributes = StyleApplier(zoom: CGFloat(zoom)).bodyAttributes(from: style)
        // Skip the syntax pass when the delegate callbacks already highlighted this exact
        // text/style — otherwise every keystroke runs the highlighter twice.
        if context.coordinator.needsHighlight(text: textView.text, style: style) {
            MarkdownHighlighter(style: style, zoom: CGFloat(zoom)).apply(to: textView.textStorage)
            context.coordinator.didHighlight(text: textView.text, style: style)
        }

        let length = (textView.text as NSString).length
        let desired = NSRange(location: selection.location, length: selection.length)
        if NSMaxRange(desired) <= length {
            textView.selectedRange = desired
        }
        if didResetText, textView.contentOffset != preservedOffset {
            textView.setContentOffset(preservedOffset, animated: false)
        }
        if container.showLineNumbers != showLineNumbers {
            container.showLineNumbers = showLineNumbers
        }
        container.currentLineHighlight = currentLineHighlight
        // Honour a focus request (new/opened note) so the caret is live without a tap.
        if context.coordinator.focusRequestChanged(focusRequest) {
            DispatchQueue.main.async { [weak textView] in textView?.becomeFirstResponder() }
        }
        container.refreshOverlays()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextViewRepresentable
        weak var container: EditorContainerView?
        private let engine = OutlineEngine()

        /// The text/style the highlighter last ran over, so the SwiftUI update pass can skip
        /// re-highlighting content the delegate callbacks already styled.
        private var highlightedText: String?
        private var highlightedStyle: StyleSheet?
        /// Last-seen gutter state, so a line-number toggle can force a re-colour.
        private var lastShowLineNumbers: Bool?
        /// Last-seen zoom + focus token so a change forces a re-colour / focus grab exactly once.
        private var lastZoom: Double?
        private var lastFocusRequest = 0

        func needsHighlight(text: String, style: StyleSheet) -> Bool {
            highlightedText != text || highlightedStyle != style
        }

        func zoomChanged(_ value: Double) -> Bool {
            defer { lastZoom = value }
            return lastZoom != value
        }

        func focusRequestChanged(_ value: Int) -> Bool {
            defer { lastFocusRequest = value }
            return lastFocusRequest != value
        }

        func didHighlight(text: String, style: StyleSheet) {
            highlightedText = text
            highlightedStyle = style
        }

        /// Drops the highlight cache so the next update pass re-colours the whole note. Called
        /// whenever the storage is reset (`textView.string = …`), which wipes attribute runs: the
        /// syntax colours must be re-applied or the text falls back to the uniform default colour.
        func invalidateHighlight() {
            highlightedText = nil
        }

        /// True when the gutter visibility changed since the last update (and records the new
        /// value). Toggling line numbers must not leave the note text in the default colour.
        func showLineNumbersChanged(_ value: Bool) -> Bool {
            defer { lastShowLineNumbers = value }
            return lastShowLineNumbers != value
        }

        init(_ parent: MarkdownTextViewRepresentable) { self.parent = parent }

        /// Intercepts Return to continue (or exit) a list marker via the pure `OutlineEngine`.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            let selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
            let edit = engine.insertNewline(text: textView.text, selection: selection)
            let offset = textView.contentOffset
            textView.text = edit.text
            textView.typingAttributes = StyleApplier(zoom: CGFloat(parent.zoom)).bodyAttributes(from: parent.style)
            MarkdownHighlighter(style: parent.style, zoom: CGFloat(parent.zoom)).apply(to: textView.textStorage)
            didHighlight(text: edit.text, style: parent.style)
            textView.selectedRange = NSRange(location: edit.selection.location, length: edit.selection.length)
            // Resetting `.text` snaps the scroll to the top; pin it so list-continuation on Return
            // doesn't jump the view (worse on longer notes).
            if textView.contentOffset != offset { textView.setContentOffset(offset, animated: false) }
            parent.text = edit.text
            parent.selection = edit.selection
            container?.refreshOverlays()
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            let range = textView.selectedRange
            parent.selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
            // Don't re-apply attributes while the system is mid-composition (dictation / IME marked
            // text). Rewriting the storage under a live dictation session both jumped the view and
            // duplicated spaces ("extra spaces after voice-to-text"); defer the colour pass until
            // composition commits and this fires again with no marked range.
            guard textView.markedTextRange == nil else {
                container?.refreshOverlays()
                return
            }
            MarkdownHighlighter(style: parent.style, zoom: CGFloat(parent.zoom)).apply(to: textView.textStorage)
            didHighlight(text: textView.text, style: parent.style)
            container?.refreshOverlays()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            parent.selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
            // Move the current-line band to the caret's new line.
            container?.refreshOverlays()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            container?.refreshOverlays()
        }
    }
}

/// Hosts the editor's `UITextView` and an optional line-number gutter drawn to its left. The
/// gutter is a non-scrolling overlay that reads the text view's live layout + scroll offset, so it
/// stays aligned as the user types and scrolls.
final class EditorContainerView: UIView {
    let textView: UITextView
    let gutter: IOSLineNumberGutter
    /// Non-interactive overlay that draws a real horizontal line over every `---` thematic break.
    let ruleOverlay: IOSThematicBreakOverlay
    /// Underlay (behind the clear-backed text view) that fills the caret's line with a band.
    let currentLineView: IOSCurrentLineOverlay
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

    /// Band colour for the caret's line, or nil to hide it.
    var currentLineHighlight: UIColor? {
        didSet {
            guard currentLineHighlight != oldValue else { return }
            currentLineView.color = currentLineHighlight
            currentLineView.isHidden = currentLineHighlight == nil
            currentLineView.setNeedsDisplay()
        }
    }

    init(textView: UITextView) {
        self.textView = textView
        self.gutter = IOSLineNumberGutter(textView: textView)
        self.ruleOverlay = IOSThematicBreakOverlay(textView: textView)
        self.currentLineView = IOSCurrentLineOverlay(textView: textView)
        super.init(frame: .zero)
        // Order matters: the current-line band sits UNDER the (clear) text view; the rule + gutter
        // sit over it.
        addSubview(currentLineView)
        addSubview(textView)
        addSubview(ruleOverlay)
        addSubview(gutter)
        gutter.isHidden = true
        currentLineView.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Redraws the overlays that track the text view's live layout/scroll (band, rules, line numbers).
    func refreshOverlays() {
        gutter.setNeedsDisplay()
        ruleOverlay.setNeedsDisplay()
        currentLineView.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        ruleOverlay.frame = bounds
        currentLineView.frame = bounds
        gutter.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        refreshOverlays()
    }
}

/// Fills the caret's line with a background band, tracking the text view's layout + scroll offset.
/// A non-interactive underlay drawn beneath the clear-backed `UITextView`, so the band appears
/// behind the text rather than over it.
final class IOSCurrentLineOverlay: UIView {
    private weak var textView: UITextView?
    var color: UIColor?

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
        guard let color, let textView,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return }
        let ns = textView.text as NSString
        let caret = min(textView.selectedRange.location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let insetTop = textView.textContainerInset.top
        let offsetY = textView.contentOffset.y
        let documentStart = contentManager.documentRange.location

        color.setFill()
        layoutManager.enumerateTextLayoutFragments(from: documentStart, options: [.ensuresLayout]) { fragment in
            let offset = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
            guard offset <= ns.length else { return true }
            let fragmentLine = ns.lineRange(for: NSRange(location: min(offset, ns.length), length: 0))
            guard NSEqualRanges(fragmentLine, lineRange) else {
                return offset <= lineRange.location
            }
            let frame = fragment.layoutFragmentFrame
            let bandRect = CGRect(x: 0, y: frame.minY + insetTop - offsetY, width: bounds.width, height: frame.height)
            UIRectFill(bandRect)
            return true
        }
    }
}

/// Draws a real full-width horizontal line across each Markdown thematic-break line (`---`, `***`,
/// `___`), tracking the text view's layout + scroll offset like the line-number gutter does. The
/// dashes stay editable underneath (dimmed by `MarkdownHighlighter`); this just paints the rule.
final class IOSThematicBreakOverlay: UIView {
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

        let ns = textView.text as NSString
        guard ns.length > 0 else { return }
        let insetTop = textView.textContainerInset.top
        let offsetY = textView.contentOffset.y
        let leftInset = textView.textContainerInset.left
        let rightInset = textView.textContainerInset.right
        let documentStart = contentManager.documentRange.location

        UIColor.separator.setStroke()
        layoutManager.enumerateTextLayoutFragments(from: documentStart, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let y = frame.midY + insetTop - offsetY
            guard y >= rect.minY - 1, y <= rect.maxY + 1 else { return true }

            let offset = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
            guard offset <= ns.length else { return true }
            let lineRange = ns.lineRange(for: NSRange(location: offset, length: 0))
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard DevNotesCore.Markdown.isThematicBreak(line) else { return true }

            let path = UIBezierPath()
            path.lineWidth = 1
            let pixelY = (y * UIScreen.main.scale).rounded() / UIScreen.main.scale
            path.move(to: CGPoint(x: leftInset, y: pixelY))
            path.addLine(to: CGPoint(x: bounds.width - rightInset, y: pixelY))
            path.stroke()
            return true
        }
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
