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

        var compressed = filterByRelevance(messages: messages, query: query, budget: budget)

        let afterFilter = compressed.map { estimateTokens($0.content) }.reduce(0, +)
        if afterFilter > budget {
            compressed = truncateLongMessages(messages: compressed, budget: budget)
        }

        compressed = preserveRecentMessages(original: messages, compressed: compressed, keepLast: 4)

        let compressedTokens = compressed.map { estimateTokens($0.content) }.reduce(0, +)
        return CompressionResult(messages: compressed,
                                 originalTokens: originalTokens,
                                 compressedTokens: compressedTokens)
    }

    // MARK: - Relevance Filtering

    private func filterByRelevance(messages: [Message], query: String, budget: Int) -> [Message] {
        guard messages.count > 6 else { return messages }

        let recentMessages = Array(messages.suffix(4))
        let olderMessages = Array(messages.dropLast(4))

        // Scoring por similaridade semântica (variável _ removida)
        let sortedOlder = olderMessages
            .map { msg in (msg, semanticSimilarity(text1: msg.content, text2: query)) }
            .sorted { $0.1 > $1.1 }

        var selected: [Message] = []
        var usedTokens = recentMessages.map { estimateTokens($0.content) }.reduce(0, +)
        let budgetForOlder = budget - usedTokens

        for (msg, _) in sortedOlder {
            let tokens = estimateTokens(msg.content)
            if usedTokens + tokens <= budgetForOlder {
                selected.append(msg)
                usedTokens += tokens
            }
        }

        let selectedIDs = Set(selected.map { $0.id })
        let recentIDs = Set(recentMessages.map { $0.id })
        return messages.filter { selectedIDs.contains($0.id) || recentIDs.contains($0.id) }
    }

    // MARK: - Semantic Similarity

    private func semanticSimilarity(text1: String, text2: String) -> Double {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .portuguese)
                ?? NLEmbedding.sentenceEmbedding(for: .english) else {
            return lexicalSimilarity(text1: text1, text2: text2)
        }
        let t1 = String(text1.prefix(512))
        let t2 = String(text2.prefix(512))
        let dist = embedding.distance(between: t1, and: t2)
        return 1.0 - min(1.0, dist)
    }

    private func lexicalSimilarity(text1: String, text2: String) -> Double {
        let w1 = Set(text1.lowercased().components(separatedBy: .whitespacesAndNewlines))
        let w2 = Set(text2.lowercased().components(separatedBy: .whitespacesAndNewlines))
        let intersection = w1.intersection(w2).count
        let union = w1.union(w2).count
        return union > 0 ? Double(intersection) / Double(union) : 0
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
