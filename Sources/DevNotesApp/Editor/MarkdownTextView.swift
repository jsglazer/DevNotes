import DevNotesCore
import SwiftUI

/// A native **TextKit 2** editing surface (NOT a WebView) — required for launch speed and for
/// the cursor/selection control the outline operations depend on. It binds two-way to the
/// editor's `text` and `selection` and applies the sanitised `StyleSheet` to the text container.
struct MarkdownTextView: View {
    @Binding var text: String
    @Binding var selection: DevNotesCore.TextSelection
    var style: StyleSheet

    var body: some View {
        MarkdownTextViewRepresentable(text: $text, selection: $selection, style: style)
    }
}

#if os(macOS)
import AppKit

private struct MarkdownTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: DevNotesCore.TextSelection
    var style: StyleSheet

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // `usingTextLayoutManager: true` selects the TextKit 2 stack.
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
        }
        let attributes = StyleApplier().bodyAttributes(from: style)
        textView.typingAttributes = attributes
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.textStorage?.setAttributes(attributes, range: fullRange)

        let desired = NSRange(location: selection.location, length: selection.length)
        if textView.selectedRange() != desired, NSMaxRange(desired) <= fullRange.length {
            textView.setSelectedRange(desired)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextViewRepresentable
        weak var textView: NSTextView?

        init(_ parent: MarkdownTextViewRepresentable) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.selection = DevNotesCore.TextSelection(location: textView.selectedRange().location, length: textView.selectedRange().length)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            parent.selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
        }
    }
}

#elseif os(iOS)
import UIKit

private struct MarkdownTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: DevNotesCore.TextSelection
    var style: StyleSheet

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        // UITextView uses the TextKit 2 stack by default on iOS 16+.
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.autocorrectionType = .no
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            textView.text = text
        }
        textView.typingAttributes = StyleApplier().bodyAttributes(from: style)
        let length = (textView.text as NSString).length
        let desired = NSRange(location: selection.location, length: selection.length)
        if NSMaxRange(desired) <= length {
            textView.selectedRange = desired
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextViewRepresentable
        init(_ parent: MarkdownTextViewRepresentable) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            let range = textView.selectedRange
            parent.selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            parent.selection = DevNotesCore.TextSelection(location: range.location, length: range.length)
        }
    }
}
#endif
