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
        // Smart-dash / smart-quote substitution rewrites the very characters Markdown depends on:
        // typing `--` becomes an em-dash, so `---` never forms a thematic break ("the second dash
        // collapses into a single dash"), and straight quotes turn curly inside code. These are
        // SEPARATE from text replacement above, so they must be disabled explicitly — otherwise a
        // typed rule fails while a pasted one (substitution never runs on paste) renders fine.
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        // The text view must NOT paint its own (opaque) background: it draws right over the
        // current-line band `draw(_:)` lays down first, which was why the highlight never appeared.
        // The scroll view supplies the editor background instead, so the band shows behind the text.
        textView.drawsBackground = false
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        // Draw a solid editor background across the whole scroll area (text + ruler strip + corner),
        // so turning the line-number gutter on can't let a translucent/grey control background bleed
        // through and make the editor look dimmed.
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        // A bottom content inset is scroll-past-end room: the caret on the last line no longer sits
        // flush against the window edge, and the final lines can scroll up into view.
        scrollView.automaticallyAdjustsContentInsets = false

        // Line-number gutter: a FIXED overlay floated over a left text inset (visibility toggled in
        // updateNSView), NOT an NSRulerView — toggling `rulersVisible` on a TextKit 2 view retiled
        // the scroll view and blanked the viewport (see `MacLineNumberGutter`). As a floating
        // subview it stays put while the text scrolls beneath it.
        let gutter = MacLineNumberGutter(textView: textView, scrollView: scrollView)
        gutter.frame = NSRect(x: 0, y: 0, width: MacLineNumberGutter.width, height: scrollView.bounds.height)
        gutter.isHidden = true
        scrollView.addFloatingSubview(gutter, for: .vertical)
        context.coordinator.gutter = gutter

        // Redraw the gutter (and resize it to the visible height) as the user scrolls or the view
        // resizes.
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

        // Show/hide the gutter by toggling its overlay and the text view's LEFT inset (so the text
        // clears the numbers) — never `rulersVisible`, which retiled the scroll view and blanked the
        // TextKit 2 viewport. Changing `textContainerInset` is a routine relayout the text view
        // handles in place (iOS toggles the same way and never blanks), so the text stays visible.
        if context.coordinator.showLineNumbersChanged(showLineNumbers) {
            context.coordinator.gutter?.isHidden = !showLineNumbers
            var inset = textView.textContainerInset
            inset.width = showLineNumbers ? MacLineNumberGutter.width : 8
            textView.textContainerInset = inset
            context.coordinator.gutter?.needsDisplay = true
            textView.needsDisplay = true
        }
        // Keep the floating gutter sized to the visible height and repainted this pass.
        if let gutter = context.coordinator.gutter {
            gutter.frame = NSRect(x: 0, y: 0, width: MacLineNumberGutter.width,
                                  height: scrollView.contentView.bounds.height)
        }

        if textView.string != text {
            // A model-driven text change (outline command, find/replace) reassigns the whole string,
            // which snaps the scroll to the top and wipes attribute runs. Pin the scroll offset
            // across the swap so a toolbar action can't fling the view — the "toolbar causes massive
            // jumping / text disappears" report.
            context.coordinator.preservingScroll(of: scrollView) {
                textView.string = text
            }
            context.coordinator.invalidateHighlight()
        }
        applyWrapping(to: textView, in: scrollView, coordinator: context.coordinator)

        if textView.isContinuousSpellCheckingEnabled != spellCheck {
            textView.isContinuousSpellCheckingEnabled = spellCheck
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
        // `lastReportedSelection` guard: SwiftUI update passes can lag the delegate callbacks, so
        // a fast typist's binding value may describe where the caret WAS one keystroke ago.
        // Re-applying that stale echo snapped the caret (and scroll) backwards — one source of the
        // "screen randomly jumps while typing" report. Only a selection the view didn't itself
        // report (an outline command, find/replace, open-at-last-line) is applied here.
        if textView.selectedRange() != desired,
           selection != context.coordinator.lastReportedSelection,
           NSMaxRange(desired) <= fullRange.length {
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

        context.coordinator.gutter?.needsDisplay = true
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
        weak var gutter: MacLineNumberGutter?
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

        /// The character range an in-progress edit will land on (from `shouldChangeText`), so the
        /// following `textDidChange` re-colours only the edited paragraph(s) instead of the whole
        /// note. `nil` means "range unknown" → fall back to a full re-colour.
        private var pendingEditRange: NSRange?

        /// Last wrap mode + width applied to the container, so `applyWrapping` can skip redundant
        /// (relayout-inducing) reconfiguration on every observable update.
        private var appliedWrapText: Bool?
        private var appliedWrapWidth: CGFloat?

        /// Last current-line colour + zoom pushed to the view, so an unchanged value doesn't force a
        /// wasteful full redraw / re-highlight on every keystroke.
        private var lastCurrentLineHighlight: PlatformColor?
        private var didApplyCurrentLineHighlight = false
        private var lastZoom: Double?

        /// The selection this view itself last reported through the delegate callbacks, so the
        /// SwiftUI update pass can tell a stale binding echo from a real model-driven selection
        /// change and never snap the caret backwards mid-typing.
        var lastReportedSelection: DevNotesCore.TextSelection?

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
            // Re-fit the floating gutter to the (possibly resized) visible height and repaint it so
            // its numbers track the text as it scrolls.
            if let gutter, let scrollView = textView?.enclosingScrollView {
                gutter.frame = NSRect(x: 0, y: 0, width: MacLineNumberGutter.width,
                                      height: scrollView.contentView.bounds.height)
            }
            gutter?.needsDisplay = true
        }

        /// Records where the pending edit will land (and how long the inserted text is) so the
        /// `textDidChange` that follows can re-colour only the affected paragraph(s). Always returns
        /// true — this observes, it never blocks the edit.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            let insertedLength = (replacementString as NSString?)?.length ?? 0
            pendingEditRange = NSRange(location: affectedCharRange.location, length: insertedLength)
            return true
        }

        /// Intercepts Return to continue (or exit) a list marker via the pure `OutlineEngine`,
        /// so bullets and numbered items auto-continue on the next line. A plain newline (no
        /// marker involved) falls through to AppKit's native insertion, and a list edit is applied
        /// as the smallest possible replacement — the old code replaced the WHOLE string on every
        /// Return, re-laying the entire TextKit 2 viewport and lurching the scroll each time.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let range = textView.selectedRange()
            let selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
            let edit = engine.insertNewline(text: textView.string, selection: selection)

            let plain = (textView.string as NSString).replacingCharacters(in: range, with: "\n")
            if edit.text == plain, edit.selection == .caret(range.location + 1) { return false }

            guard let change = TextDiff.minimalEdit(from: textView.string, to: edit.text) else { return true }
            // The `shouldChangeText`/`didChangeText` pair keeps undo working and routes through
            // `textDidChange`, which updates the bindings and re-colours just the edited lines.
            if textView.shouldChangeText(in: change.range, replacementString: change.replacement) {
                textView.textStorage?.replaceCharacters(in: change.range, with: change.replacement)
                textView.didChangeText()
            }
            textView.setSelectedRange(NSRange(location: edit.selection.location, length: edit.selection.length))
            textView.scrollRangeToVisible(textView.selectedRange())
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            let range = textView.selectedRange()
            let reported = DevNotesCore.TextSelection(location: range.location, length: range.length)
            lastReportedSelection = reported
            parent.selection = reported
            // Re-colour only the paragraph(s) this edit touched (see `MarkdownHighlighter.apply`).
            // Colouring the whole document on every keystroke re-laid the entire TextKit 2 viewport,
            // which on longer notes left freshly-typed glyphs unrendered until a relayout (Return) —
            // the "text disappears after ~500 words until Return is pressed" report.
            let editedRange = pendingEditRange
            pendingEditRange = nil
            if let storage = textView.textStorage {
                // Pin the scroll position across the re-colour, then follow the caret ourselves — so
                // re-colouring never jumps the view, but typing at the bottom still keeps the caret
                // on-screen.
                if let scrollView = textView.enclosingScrollView {
                    preservingScroll(of: scrollView) {
                        MarkdownHighlighter(style: parent.style, zoom: CGFloat(parent.zoom)).apply(to: storage, editedRange: editedRange)
                    }
                } else {
                    MarkdownHighlighter(style: parent.style, zoom: CGFloat(parent.zoom)).apply(to: storage, editedRange: editedRange)
                }
                didHighlight(text: textView.string, style: parent.style)
            }
            // Follow the caret as the user types so text added at the bottom isn't clipped.
            textView.scrollRangeToVisible(range)
            textView.needsDisplay = true
            gutter?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let reported = DevNotesCore.TextSelection(location: range.location, length: range.length)
            lastReportedSelection = reported
            parent.selection = reported
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
        // Smart dashes turn a typed `--` into an em-dash, so `---` never becomes a thematic break
        // ("the second dash collapses into a single dash"); smart quotes rewrite straight quotes in
        // code. Both are separate from autocorrection above, so disable them explicitly — pasted
        // Markdown skips substitution and renders fine, but typed Markdown needs these off to match.
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.backgroundColor = .clear
        // Keyboard-dismiss button pinned above the keyboard. A SwiftUI `.toolbar(placement:.keyboard)`
        // never attaches to this UIKit text view, so the button was missing; an inputAccessoryView is
        // the reliable way to give the editor a "hide keyboard" affordance on iOS.
        let accessory = UIToolbar()
        accessory.sizeToFit()
        accessory.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(
                image: UIImage(systemName: "keyboard.chevron.compact.down"),
                style: .plain,
                target: textView,
                action: #selector(UIResponder.resignFirstResponder)
            )
        ]
        textView.inputAccessoryView = accessory
        let container = EditorContainerView(textView: textView)
        context.coordinator.container = container
        context.coordinator.startObservingKeyboard()
        // Re-measure the keyboard overlap whenever the container is re-laid: SwiftUI's own keyboard
        // avoidance can resize the editor AFTER the keyboard notification fired, and an inset based
        // on the stale pre-layout frame double-counted the keyboard (text scrolled up past the top).
        container.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.applyBottomInset()
        }
        return container
    }

    func updateUIView(_ container: EditorContainerView, context: Context) {
        context.coordinator.parent = self
        let textView = container.textView
        let desiredSpellCheck: UITextSpellCheckingType = spellCheck ? .yes : .no
        if textView.spellCheckingType != desiredSpellCheck {
            textView.spellCheckingType = desiredSpellCheck
        }
        // Scroll-past-end room so the caret on the last line clears the keyboard/bottom edge. Uses
        // whichever is larger — the configured padding or the current keyboard overlap — so a SwiftUI
        // refresh mid-typing can't wipe the keyboard inset.
        context.coordinator.applyBottomInset()
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
        // Only apply a selection the view didn't itself report (outline command, open-note jump):
        // re-applying the binding's stale echo of a fast typist's caret snapped it backwards and
        // triggered UIKit's own caret auto-scroll — more mid-typing jumping.
        if textView.selectedRange != desired,
           selection != context.coordinator.lastReportedSelection,
           NSMaxRange(desired) <= length {
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
        /// Last-seen zoom + focus token so a change forces a re-colour / focus grab exactly once.
        private var lastZoom: Double?
        private var lastFocusRequest = 0

        /// The selection this view itself last reported through the delegate callbacks, so the
        /// SwiftUI update pass can tell a stale binding echo from a real model-driven selection
        /// change and never snap the caret backwards mid-typing.
        var lastReportedSelection: DevNotesCore.TextSelection?

        /// The character range an in-progress edit will land on (from `shouldChangeText`), so the
        /// following `textViewDidChange` re-colours only the edited paragraph(s). `nil` → full pass.
        private var pendingEditRange: NSRange?

        /// The keyboard's frame in screen coordinates from the most recent frame-change
        /// notification, or nil while it's hidden. The overlap is re-derived from this at every
        /// layout pass rather than captured once: SwiftUI's keyboard avoidance can resize the
        /// editor after the notification fires, and a frozen overlap then double-counted the
        /// keyboard — the "text scrolls up beyond the top edge" report.
        private var keyboardScreenFrame: CGRect?

        /// How far the keyboard currently overlaps the editor (points), measured against the text
        /// view's LIVE frame.
        private var keyboardOverlap: CGFloat {
            guard let keyboardScreenFrame,
                  let textView = container?.textView,
                  let window = textView.window else { return 0 }
            let keyboardFrame = window.convert(keyboardScreenFrame, from: window.screen.coordinateSpace)
            let textFrame = textView.convert(textView.bounds, to: window)
            return max(0, textFrame.maxY - keyboardFrame.minY)
        }

        func needsHighlight(text: String, style: StyleSheet) -> Bool {
            highlightedText != text || highlightedStyle != style
        }

        /// Sets the text view's bottom scroll-past-end inset to whichever is larger: the note's
        /// configured `bottomPadding`, or the height the keyboard currently covers. Called from the
        /// keyboard handler, `updateUIView`, and the container's layout pass, so neither a SwiftUI
        /// refresh nor a post-keyboard resize can leave a stale inset behind.
        func applyBottomInset() {
            guard let textView = container?.textView else { return }
            let bottom = max(CGFloat(max(0, parent.bottomPadding)), keyboardOverlap)
            if textView.contentInset.bottom != bottom {
                textView.contentInset.bottom = bottom
                textView.verticalScrollIndicatorInsets.bottom = bottom
            }
        }

        /// Subscribes to keyboard-frame changes so the editor can inset itself out from under the
        /// keyboard and keep the caret visible — without this the last lines slid behind the keyboard
        /// with no way to scroll them back into view.
        func startObservingKeyboard() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardFrameWillChange(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillHide(_:)),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )
        }

        @objc private func keyboardFrameWillChange(_ note: Notification) {
            guard let value = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
            keyboardScreenFrame = value.cgRectValue
            applyBottomInset()
            if let textView = container?.textView {
                scrollCaretToVisible(in: textView, animated: true)
            }
        }

        @objc private func keyboardWillHide(_ note: Notification) {
            keyboardScreenFrame = nil
            applyBottomInset()
        }

        /// Scrolls the caret's rect into view above the keyboard after an inset change.
        private func scrollCaretToVisible(in textView: UITextView, animated: Bool) {
            guard let selectedRange = textView.selectedTextRange else { return }
            let caret = textView.caretRect(for: selectedRange.end)
            guard caret.isNull == false, caret.isInfinite == false else { return }
            textView.scrollRectToVisible(caret.insetBy(dx: 0, dy: -8), animated: animated)
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

        init(_ parent: MarkdownTextViewRepresentable) { self.parent = parent }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        /// Intercepts Return to continue (or exit) a list marker via the pure `OutlineEngine`.
        /// A plain newline (no marker involved) goes through UIKit's native insertion — the path
        /// that never disturbs the scroll — and a list edit is applied as the smallest possible
        /// replacement. The old code reassigned `.text` wholesale, which re-laid the entire
        /// document and snapped the scroll to the top before the pin put it back: the "screen
        /// flashes up and back down on Return" report.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else {
                // Record where non-newline input lands so `textViewDidChange` re-colours only the
                // edited paragraph(s) rather than the whole note on every keystroke.
                pendingEditRange = NSRange(location: range.location, length: (text as NSString).length)
                return true
            }
            let selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
            let edit = engine.insertNewline(text: textView.text, selection: selection)

            let plain = (textView.text as NSString).replacingCharacters(in: range, with: "\n")
            if edit.text == plain, edit.selection == .caret(range.location + 1) {
                pendingEditRange = NSRange(location: range.location, length: 1)
                return true
            }

            guard let change = TextDiff.minimalEdit(from: textView.text, to: edit.text) else { return false }
            textView.textStorage.replaceCharacters(in: change.range, with: change.replacement)
            textView.selectedRange = NSRange(location: edit.selection.location, length: edit.selection.length)
            textView.typingAttributes = StyleApplier(zoom: CGFloat(parent.zoom)).bodyAttributes(from: parent.style)
            // Storage-level edits bypass `textViewDidChange`, so do its work here, scoped to the
            // paragraphs the replacement touched.
            let recolour = NSRange(location: change.range.location, length: (change.replacement as NSString).length)
            MarkdownHighlighter(style: parent.style, zoom: CGFloat(parent.zoom)).apply(to: textView.textStorage, editedRange: recolour)
            didHighlight(text: textView.text, style: parent.style)
            parent.text = textView.text
            parent.selection = edit.selection
            lastReportedSelection = edit.selection
            scrollCaretToVisible(in: textView, animated: false)
            container?.refreshOverlays()
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            let range = textView.selectedRange
            let reported = DevNotesCore.TextSelection(location: range.location, length: range.length)
            lastReportedSelection = reported
            parent.selection = reported
            // Don't re-apply attributes while the system is mid-composition (dictation / IME marked
            // text). Rewriting the storage under a live dictation session both jumped the view and
            // duplicated spaces ("extra spaces after voice-to-text"); defer the colour pass until
            // composition commits and this fires again with no marked range.
            guard textView.markedTextRange == nil else {
                // Mid-composition: defer colouring until commit, and force that commit to re-colour
                // in full (the small pending range no longer maps onto the finished text).
                pendingEditRange = nil
                container?.refreshOverlays()
                return
            }
            // Re-colour only the paragraph(s) this edit touched (see `MarkdownHighlighter.apply`).
            // Colouring the whole note on every keystroke re-laid the entire TextKit 2 viewport and,
            // past ~500 words, left freshly-typed glyphs unrendered until a relayout — the "typed
            // text disappears until Return" report. Pin the scroll offset across the pass so typing
            // never moves the view out from under the caret.
            let editedRange = pendingEditRange
            pendingEditRange = nil
            let offset = textView.contentOffset
            MarkdownHighlighter(style: parent.style, zoom: CGFloat(parent.zoom)).apply(to: textView.textStorage, editedRange: editedRange)
            didHighlight(text: textView.text, style: parent.style)
            if textView.contentOffset != offset {
                textView.setContentOffset(offset, animated: false)
            }
            container?.refreshOverlays()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            let reported = DevNotesCore.TextSelection(location: range.location, length: range.length)
            lastReportedSelection = reported
            parent.selection = reported
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
    /// Called after each layout pass so the coordinator can re-measure the keyboard overlap
    /// against the view's LIVE frame (SwiftUI may resize the editor after the keyboard shows).
    var onLayout: (() -> Void)?

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
        onLayout?()
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
              let contentManager = layoutManager.textContentManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange else { return }
        let ns = textView.text as NSString
        let caret = min(textView.selectedRange.location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let insetTop = textView.textContainerInset.top
        let offsetY = textView.contentOffset.y
        let documentStart = contentManager.documentRange.location

        color.setFill()
        // Walk only the fragments the viewport has ALREADY laid out. Enumerating from the document
        // start with `.ensuresLayout` forced a full-document layout on every redraw — and this
        // overlay redraws on every keystroke, caret move, and scroll tick, which is what kept the
        // scroll position churning.
        layoutManager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            guard fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedAscending else {
                return false
            }
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
              let contentManager = layoutManager.textContentManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange
        else { return }

        let ns = textView.text as NSString
        guard ns.length > 0 else { return }
        let insetTop = textView.textContainerInset.top
        let offsetY = textView.contentOffset.y
        let leftInset = textView.textContainerInset.left
        let rightInset = textView.textContainerInset.right
        let documentStart = contentManager.documentRange.location

        // A 1-pt `.separator` hairline was effectively invisible, so `---` looked like it produced no
        // rule. Draw a clearly visible mid-grey line instead, snapped to the device pixel grid.
        // Enumeration is viewport-scoped and never forces layout: the old whole-document
        // `.ensuresLayout` walk destabilised fragment frames mid-draw, which is why a freshly typed
        // `---` rule could appear and immediately vanish.
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        UIColor.secondaryLabel.setStroke()
        layoutManager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            guard fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedAscending else {
                return false
            }
            let frame = fragment.layoutFragmentFrame
            let y = frame.midY + insetTop - offsetY
            guard y >= rect.minY - 1, y <= rect.maxY + 1 else { return true }

            let offset = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
            guard offset <= ns.length else { return true }
            let lineRange = ns.lineRange(for: NSRange(location: offset, length: 0))
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard DevNotesCore.Markdown.isThematicBreak(line) else { return true }

            let path = UIBezierPath()
            path.lineWidth = 1.5
            let pixelY = (y * scale).rounded() / scale
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

        // Number only the fragments the viewport has ALREADY laid out — the old enumeration from
        // the document start with `.ensuresLayout` forced a full-document layout on every redraw
        // (each keystroke and scroll tick while the gutter was on). Advance the line count from
        // one fragment to the next instead of rescanning the whole prefix per fragment.
        guard let viewport = layoutManager.textViewportLayoutController.viewportRange else { return }

        let string = textView.text as NSString
        let insetTop = textView.textContainerInset.top
        let offsetY = textView.contentOffset.y
        let documentStart = contentManager.documentRange.location

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
            let y = fragmentFrame.minY + insetTop - offsetY
            if y + fragmentFrame.height >= rect.minY, y <= rect.maxY {
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
