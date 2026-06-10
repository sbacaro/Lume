//
//  RAGEngine.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import NaturalLanguage

// MARK: - Chunk

struct RAGChunk: Sendable {
    let id: String
    let documentName: String
    let content: String
    let summary: String
    let embedding: [Float]
    let chunkIndex: Int
    let totalChunks: Int
}

// MARK: - RAGEngine

actor RAGEngine {
    static let shared = RAGEngine()

    private var chunks: [RAGChunk] = []
    private var documentSummaries: [String: String] = [:]
    // Removido nonisolated(unsafe) — TextEmbedder é Sendable, não é necessário
    private let embedder: TextEmbedder = TextEmbedder()
    private let chunkSize = 512
    private let chunkOverlap = 64
    private let topK = 5
    private let summaryTopK = 2

    // MARK: - Index

    func index(file: FileIngestionManager.IngestedFile) async {
        removeDocument(name: file.name)

        let rawChunks = splitIntoChunks(text: file.content, name: file.name)
        let docSummary = summarize(text: file.content, maxSentences: 5)
        documentSummaries[file.name] = docSummary

        var indexed: [RAGChunk] = []
        for (i, chunkText) in rawChunks.enumerated() {
            let summary = summarize(text: chunkText, maxSentences: 2)
            let embedding = await embedder.embed(text: chunkText)
            let chunk = RAGChunk(
                id: UUID().uuidString,
                documentName: file.name,
                content: chunkText,
                summary: summary,
                embedding: embedding,
                chunkIndex: i,
                totalChunks: rawChunks.count
            )
            indexed.append(chunk)
        }
        chunks.append(contentsOf: indexed)
    }

    // MARK: - Retrieve

    func buildContext(for query: String) async -> String? {
        guard !chunks.isEmpty else { return nil }

        let queryEmbedding = await embedder.embed(text: query)

        let rankedDocs = documentSummaries
            .map { (name, summary) -> (String, String, Float) in
                let summaryEmbedding = self.embedder.embedSync(text: summary)
                let score = cosineSimilarity(queryEmbedding, summaryEmbedding)
                return (name, summary, score)
            }
            .sorted { $0.2 > $1.2 }
            .prefix(summaryTopK)

        let relevantDocNames = Set(rankedDocs.map { $0.0 })
        let candidateChunks = chunks.filter { relevantDocNames.contains($0.documentName) }

        let rankedChunks = candidateChunks
            .map { chunk -> (RAGChunk, Float) in
                let score = cosineSimilarity(queryEmbedding, chunk.embedding)
                return (chunk, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)

        guard !rankedChunks.isEmpty else { return nil }

        var context = "## Contexto Relevante\n\n"
        context += "### Visão Geral dos Documentos\n"
        for (name, summary, _) in rankedDocs {
            context += "**\(name):** \(summary)\n\n"
        }
        context += "### Trechos Detalhados\n"
        for (chunk, score) in rankedChunks {
            context += "[\(chunk.documentName) — trecho \(chunk.chunkIndex + 1)/\(chunk.totalChunks), relevância: \(String(format: "%.2f", score))]\n"
            context += chunk.content + "\n\n"
        }
        return context
    }

    // MARK: - Remove

    func removeDocument(name: String) {
        chunks.removeAll { $0.documentName == name }
        documentSummaries.removeValue(forKey: name)
    }

    // MARK: - Private

    private func splitIntoChunks(text: String, name: String) -> [String] {
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        var result: [String] = []
        var start = 0
        while start < words.count {
            let end = min(start + chunkSize, words.count)
            result.append(words[start..<end].joined(separator: " "))
            start += chunkSize - chunkOverlap
        }
        return result
    }

    private func summarize(text: String, maxSentences: Int) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        guard sentences.count > maxSentences else { return sentences.joined(separator: " ") }
        var picked: [String] = [sentences[0]]
        let step = max(1, sentences.count / (maxSentences - 1))
        var i = step
        while i < sentences.count - 1 && picked.count < maxSentences - 1 {
            picked.append(sentences[i])
            i += step
        }
        picked.append(sentences[sentences.count - 1])
        return picked.joined(separator: " ")
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }
}

// MARK: - TextEmbedder

final class TextEmbedder: Sendable {
    private nonisolated(unsafe) let embedding: NLEmbedding?

    nonisolated init() {
        self.embedding = NLEmbedding.wordEmbedding(for: .english)
            ?? NLEmbedding.wordEmbedding(for: .portuguese)
    }

    func embed(text: String) async -> [Float] {
        embedSync(text: text)
    }

    nonisolated func embedSync(text: String) -> [Float] {
        guard let embedding else { return Array(repeating: 0, count: 300) }
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = text
        var vectors: [[Double]] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .tokenType
        ) { _, range in
            let word = String(text[range]).lowercased()
            if let vector = embedding.vector(for: word) { vectors.append(vector) }
            return true
        }
        guard !vectors.isEmpty else { return Array(repeating: 0, count: 300) }
        let dim = vectors[0].count
        var mean = Array(repeating: Double(0), count: dim)
        for v in vectors { for i in 0..<dim { mean[i] += v[i] } }
        let n = Double(vectors.count)
        return mean.map { Float($0 / n) }
    }
}
