//
//  VisionOCR.swift
//  Lume
//
//  Reconhecimento de texto em imagens usando o framework Vision (nativo, offline,
//  sem dependências). Permite que mesmo modelos sem visão "leiam" imagens anexadas.
//

import Foundation
@preconcurrency import Vision
import AppKit

enum VisionOCR {

    /// Extrai texto de uma única imagem.
    static func recognizeText(in image: NSImage) async -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        return await withCheckedContinuation { continuation in
            // Sem completion handler: o Vision invocaria a closure na PRÓPRIA fila, mas sob
            // a isolação MainActor padrão do projeto a closure seria @MainActor e o runtime
            // abortaria (dispatch_assert_queue_fail). Rodamos `perform` na fila de fundo e
            // lemos `request.results` ali mesmo — síncrono, sem closure isolada.
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["pt-BR", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    let text = (request.results as? [VNRecognizedTextObservation])?
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n") ?? ""
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    /// Extrai texto de várias imagens, rotulando cada uma. Retorna "" se nada for encontrado.
    static func recognizeText(in images: [NSImage]) async -> String {
        guard !images.isEmpty else { return "" }
        var parts: [String] = []
        for (i, image) in images.enumerated() {
            let text = await recognizeText(in: image)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append("[Texto extraído da imagem \(i + 1)]\n\(trimmed)")
            }
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Classificação (rótulos do framework Vision)

    /// Rótulos de classificação da imagem acima de um limiar de confiança.
    static func classify(_ image: NSImage, minConfidence: Float = 0.20, maxLabels: Int = 6) async -> [String] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        return await withCheckedContinuation { continuation in
            // Sem completion handler (ver recognizeText): evita o crash de isolação ao ler
            // os resultados na própria fila de fundo após o `perform` síncrono.
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    let labels = (request.results as? [VNClassificationObservation])?
                        .filter { $0.confidence >= minConfidence }
                        .sorted { $0.confidence > $1.confidence }
                        .prefix(maxLabels)
                        .map { $0.identifier.replacingOccurrences(of: "_", with: " ") } ?? []
                    continuation.resume(returning: Array(labels))
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Descrição local (classificação + OCR)

    /// Gera uma descrição local das imagens (rótulos + texto) para modelos SEM visão.
    /// O modelo não recebe os pixels — apenas esta análise textual.
    static func describe(in images: [NSImage]) async -> String {
        guard !images.isEmpty else { return "" }
        var parts: [String] = []
        for (i, image) in images.enumerated() {
            var lines: [String] = []
            let labels = await classify(image)
            if !labels.isEmpty {
                lines.append("Conteúdo identificado: " + labels.joined(separator: ", "))
            }
            let text = await recognizeText(in: image).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append("Texto na imagem:\n" + text)
            }
            if !lines.isEmpty {
                parts.append("[Imagem \(i + 1)]\n" + lines.joined(separator: "\n"))
            }
        }
        guard !parts.isEmpty else { return "" }
        return "[Análise local das imagens anexadas — você não recebeu os pixels, apenas esta descrição extraída por OCR e classificação. Use-a para interpretar a imagem.]\n\n"
            + parts.joined(separator: "\n\n")
    }
}
