//
//  ConversationExporter.swift
//  Lume
//
//  Exporta uma conversa para arquivo Markdown (.md) ou PDF paginado.
//  O Markdown copiado para a área de transferência continua disponível à parte.
//

import AppKit
import UniformTypeIdentifiers

enum ConversationExporter {

    // MARK: - Markdown

    /// Constrói o Markdown completo da conversa.
    static func markdown(for conversation: Conversation) -> String {
        var out = "# \(conversation.title)\n\n"
        out += "_Exportado em \(Date().formatted(date: .long, time: .shortened)) · Modelo: \(conversation.modelName)_\n\n---\n\n"
        let msgs = conversation.messages.sorted { $0.timestamp < $1.timestamp }
        for m in msgs where m.role != .system {
            let who = m.role == .user ? "Você" : "Assistente"
            out += "## \(who)\n\n\(stripImageData(m.content))\n\n"
        }
        return out
    }

    /// Salva a conversa como arquivo .md via painel de salvar.
    static func saveMarkdown(_ conversation: Conversation) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = filename(for: conversation) + ".md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? markdown(for: conversation).data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// Copia o Markdown da conversa para a área de transferência.
    static func copyMarkdown(_ conversation: Conversation) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown(for: conversation), forType: .string)
    }

    // MARK: - PDF

    /// Salva a conversa como PDF paginado (US Letter).
    static func savePDF(_ conversation: Conversation) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = filename(for: conversation) + ".pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writePDF(attributed(for: conversation), to: url)
    }

    /// Monta a representação rica (NSAttributedString) usada na geração do PDF.
    private static func attributed(for conversation: Conversation) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let titlePara = NSMutableParagraphStyle()
        titlePara.paragraphSpacing = 6
        result.append(NSAttributedString(
            string: conversation.title + "\n",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 22), .paragraphStyle: titlePara]
        ))
        result.append(NSAttributedString(
            string: "Modelo: \(conversation.modelName) · \(Date().formatted(date: .long, time: .shortened))\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
        ))

        let bodyPara = NSMutableParagraphStyle()
        bodyPara.paragraphSpacing = 12
        bodyPara.lineSpacing = 2

        for m in conversation.messages.sorted(by: { $0.timestamp < $1.timestamp }) where m.role != .system {
            let who = m.role == .user ? "Você" : "Assistente"
            let headerColor: NSColor = m.role == .user ? .systemBlue : .systemOrange
            result.append(NSAttributedString(
                string: who + "\n",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: headerColor]
            ))
            result.append(NSAttributedString(
                string: stripImageData(m.content) + "\n\n",
                attributes: [.font: NSFont.systemFont(ofSize: 12),
                             .foregroundColor: NSColor.textColor,
                             .paragraphStyle: bodyPara]
            ))
        }
        return result
    }

    /// Renderiza o texto em PDF paginado e grava na URL.
    private static func writePDF(_ attr: NSAttributedString, to url: URL) {
        let pageW: CGFloat = 612, pageH: CGFloat = 792   // US Letter (pt)
        let margin: CGFloat = 48
        let textW = pageW - margin * 2

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textW, height: pageH))
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: textW, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attr)
        textView.sizeToFit()

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: pageW, height: pageH)
        printInfo.topMargin = margin
        printInfo.bottomMargin = margin
        printInfo.leftMargin = margin
        printInfo.rightMargin = margin
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue as NSString] = url as NSURL

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.run()
    }

    // MARK: - Helpers

    /// Remove blobs de imagem embutidos ([IMAGE:data:...]) do texto.
    private static func stripImageData(_ text: String) -> String {
        guard text.contains("[IMAGE:") else { return text }
        var s = text
        while let start = s.range(of: "[IMAGE:"),
              let end = s.range(of: "]", range: start.lowerBound..<s.endIndex) {
            s.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nome de arquivo seguro derivado do título da conversa.
    private static func filename(for conversation: Conversation) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let base = conversation.title
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "Conversa" : String(base.prefix(80))
    }
}
