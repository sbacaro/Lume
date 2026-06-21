//
//  ContextCompressor.swift
//  Lume
//

import Foundation
import NaturalLanguage

// MARK: - Compression Result

struct CompressionResult {
    let messages: [Message]
    let originalTokens: Int
    let compressedTokens: Int
    var compressionRatio: Double {
        guard originalTokens > 0 else { return 1.0 }
        return 1.0 - Double(compressedTokens) / Double(originalTokens)
    }
}

// MARK: - Context Compressor

final class ContextCompressor {
    static let shared = ContextCompressor()
    private init() {}

    func compress(
        messages: [Message],
        query: String,
        targetTokens: Int,
        systemPrompt: String = ""
    ) -> CompressionResult {
        let originalTokens = messages.map { estimateTokens($0.content) }.reduce(0, +)
        let systemTokens = estimateTokens(systemPrompt)
        let queryTokens = estimateTokens(query)
        let budget = targetTokens - systemTokens - queryTokens - 500

        if originalTokens <= budget {
            return CompressionResult(messages: messages,
                                     originalTokens: originalTokens,
                                     compressedTokens: originalTokens)
        }

        // Corte por RECÊNCIA (barato): mantém as mensagens mais recentes que cabem no
        // orçamento e trunca a do limite. Antes usávamos relevância semântica
        // (`filterByRelevance` com `NLEmbedding` por mensagem), que em conversas longas
        // rodava embedding em todo o histórico A CADA TURNO — travando o app antes do
        // streaming começar (tempo até o 1º token enorme → "0 tok/s"). A relevância de
        // documentos já é coberta pelo RAG, injetado à parte.
        var compressed = truncateLongMessages(messages: messages, budget: budget)
        compressed = preserveRecentMessages(original: messages, compressed: compressed, keepLast: 4)

        let compressedTokens = compressed.map { estimateTokens($0.content) }.reduce(0, +)
        return CompressionResult(messages: compressed,
                                 originalTokens: originalTokens,
                                 compressedTokens: compressedTokens)
    }


    // MARK: - Truncation

    private func truncateLongMessages(messages: [Message], budget: Int) -> [Message] {
        var remaining = budget
        var result: [Message] = []
        for msg in messages.reversed() {
            let tokens = estimateTokens(msg.content)
            if remaining <= 0 { break }
            if tokens <= remaining {
                result.insert(msg, at: 0)
                remaining -= tokens
            } else {
                let truncated = smartTruncate(text: msg.content, targetTokens: max(50, remaining))
                result.insert(Message(role: msg.role, content: truncated), at: 0)
                remaining = 0
            }
        }
        return result
    }

    private func smartTruncate(text: String, targetTokens: Int) -> String {
        let targetChars = targetTokens * 4
        guard text.count > targetChars else { return text }
        let keepStart = Int(Double(targetChars) * 0.6)
        let keepEnd = targetChars - keepStart - 20
        let startIdx = text.index(text.startIndex, offsetBy: min(keepStart, text.count))
        let endIdx = text.index(text.endIndex, offsetBy: -min(keepEnd, text.count))
        let start = String(text[..<startIdx])
        let end = keepEnd > 0 && endIdx < text.endIndex ? String(text[endIdx...]) : ""
        return start + "\n[…]\n" + end
    }

    private func preserveRecentMessages(original: [Message], compressed: [Message], keepLast: Int) -> [Message] {
        let recentOriginal = Array(original.suffix(keepLast))
        let recentIDs = Set(recentOriginal.map { $0.id })
        var withoutRecent = compressed.filter { !recentIDs.contains($0.id) }
        withoutRecent.append(contentsOf: recentOriginal)
        return withoutRecent
    }

    func estimateTokens(_ text: String) -> Int { max(1, text.count / 4) }
}
