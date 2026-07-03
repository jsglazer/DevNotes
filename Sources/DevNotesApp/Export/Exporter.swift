#if os(macOS)
import AppKit
import DevNotesCore
import SwiftUI
import UniformTypeIdentifiers

/// Exports the currently open note to disk via a save panel. Markdown and plain-text exports write
/// the raw buffer; the PDF export renders the note through the same `StyleApplier` attributes the
/// editor uses, so the printed page matches what the user sees.
@MainActor
enum Exporter {
    static func exportMarkdown(model: AppModel) {
        writeText(model: model, ext: "md", type: UTType(filenameExtension: "md") ?? .plainText)
    }

    static func exportText(model: AppModel) {
        writeText(model: model, ext: "txt", type: .plainText)
    }

    static func exportPDF(model: AppModel) {
        guard model.selectedID != nil,
              let url = savePanel(defaultName: fileName(model, ext: "pdf"), type: .pdf)
        else { return }

        let attributes = StyleApplier().bodyAttributes(from: model.styleSheet)
        let attributed = NSAttributedString(string: model.editor.text, attributes: attributes)

        let pageWidth: CGFloat = 612 // US Letter (8.5" × 72)
        let margin: CGFloat = 36
        let textWidth = pageWidth - margin * 2

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: 10))
        textView.isRichText = false
        textView.backgroundColor = .white
        textView.drawsBackground = true
        textView.textStorage?.setAttributedString(attributed)
        textView.sizeToFit()
        let textHeight = max(textView.frame.height, 1)
        textView.frame = NSRect(x: margin, y: margin, width: textWidth, height: textHeight)

        let page = NSView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: textHeight + margin * 2))
        page.wantsLayer = true
        page.layer?.backgroundColor = NSColor.white.cgColor
        page.addSubview(textView)

        let data = page.dataWithPDF(inside: page.bounds)
        try? data.write(to: url)
    }

    // MARK: - Helpers

    private static func writeText(model: AppModel, ext: String, type: UTType) {
        guard model.selectedID != nil,
              let url = savePanel(defaultName: fileName(model, ext: ext), type: type)
        else { return }
        try? model.editor.text.data(using: .utf8)?.write(to: url, options: [.atomic])
    }

    private static func savePanel(defaultName: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// A filesystem-safe default name derived from the note's title.
    private static func fileName(_ model: AppModel, ext: String) -> String {
        let title = model.summaries.first { $0.id == model.selectedID }?.title ?? "Note"
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let safe = title.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmed.isEmpty ? "Note" : trimmed).\(ext)"
    }
}
#endif
