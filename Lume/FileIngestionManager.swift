//
//  FileIngestionManager.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import PDFKit
import Vision
import AppKit
import UniformTypeIdentifiers

/// Extrai texto de arquivos para injetar no contexto do LLM.
actor FileIngestionManager {
    static let shared = FileIngestionManager()

    struct IngestedFile {
        let name: String
        let content: String
        let type: FileType
        let tokenEstimate: Int

        enum FileType: String {
            case pdf, image, text, docx, xlsx, unknown
        }
    }

    // MARK: - Main entry point

    func ingest(url: URL) async throws -> IngestedFile {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent

        switch ext {
        case "pdf":
            let text = try extractPDF(url: url)
            return IngestedFile(name: name, content: text, type: .pdf,
                                tokenEstimate: text.count / 4)
        case "png", "jpg", "jpeg", "heic", "webp", "gif", "tiff":
            let text = try await extractImageText(url: url)
            return IngestedFile(name: name, content: text, type: .image,
                                tokenEstimate: text.count / 4)
        case "txt", "md", "swift", "py", "js", "ts", "html", "css",
             "json", "yaml", "yml", "xml", "csv":
            let text = try String(contentsOf: url, encoding: .utf8)
            return IngestedFile(name: name, content: text, type: .text,
                                tokenEstimate: text.count / 4)
        case "docx":
            let text = try extractDocx(url: url)
            return IngestedFile(name: name, content: text, type: .docx,
                                tokenEstimate: text.count / 4)
        default:
            // Try UTF-8 fallback
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return IngestedFile(name: name, content: text, type: .text,
                                    tokenEstimate: text.count / 4)
            }
            throw IngestionError.unsupportedFormat(ext)
        }
    }

    // MARK: - PDF

    private func extractPDF(url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw IngestionError.cannotOpenFile(url.lastPathComponent)
        }
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i),
               let text = page.string, !text.isEmpty {
                pages.append("--- Page \(i + 1) ---\n\(text)")
            }
        }
        guard !pages.isEmpty else { throw IngestionError.noTextContent }
        return pages.joined(separator: "\n\n")
    }

    // MARK: - Image OCR via Vision

    private func extractImageText(url: URL) async throws -> String {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw IngestionError.cannotOpenFile(url.lastPathComponent)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text.isEmpty ? "[No text found in image]" : text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - DOCX (basic XML extraction)

    private func extractDocx(url: URL) throws -> String {
        // DOCX is a ZIP — extract word/document.xml
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Use Process to unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", url.path, "word/document.xml", "-d", tempDir.path]
        try process.run()
        process.waitUntilExit()

        let xmlURL = tempDir.appendingPathComponent("word/document.xml")
        let xmlData = try Data(contentsOf: xmlURL)
        let xmlString = String(data: xmlData, encoding: .utf8) ?? ""

        // Strip XML tags — extract text between <w:t> tags
        let pattern = /<w:t[^>]*>(.*?)<\/w:t>/
        let matches = xmlString.matches(of: pattern)
        let text = matches.map { String($0.1) }.joined(separator: " ")
        return text.isEmpty ? "[No text content found]" : text
    }

    // MARK: - Errors

    enum IngestionError: LocalizedError {
        case unsupportedFormat(String)
        case cannotOpenFile(String)
        case noTextContent

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext): return "Formato .\(ext) não suportado"
            case .cannotOpenFile(let name):   return "Não foi possível abrir \(name)"
            case .noTextContent:              return "Nenhum texto encontrado no arquivo"
            }
        }
    }
}
