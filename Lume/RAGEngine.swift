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

// MARK: - Source / Retrieval

/// Fonte usada para responder — exibida como citação clicável na mensagem.
struct RAGSource: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var document: String
    var chunkIndex: Int
    var totalChunks: Int
    var snippet: String
    var score: Double
}

/// Resultado da recuperação: contexto para o modelo + fontes para a UI.
struct RAGRetrieval {
    let context: String
    let sources: [RAGSource]
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

    /// Compatibilidade: retorna apenas o texto de contexto.
    func buildContext(for query: String) async -> String? {
        await buildRetrieval(for: query)?.context
    }

    /// Recuperação híbrida (vetorial + lexical) com fontes para citação.
    func buildRetrieval(for query: String) async -> RAGRetrieval? {
        guard !chunks.isEmpty else { return nil }

        let queryEmbedding = await embedder.embed(text: query)
        let queryTerms = Self.tokenize(query)

        // Documentos mais relevantes pela similaridade do resumo (semântica).
        let rankedDocs = documentSummaries
            .map { (name, summary) -> (String, String, Float) in
                let summaryEmbedding = self.embedder.embedSync(text: summary)
                return (name, summary, cosineSimilarity(queryEmbedding, summaryEmbedding))
            }
            .sorted { $0.2 > $1.2 }
            .prefix(summaryTopK)

        let relevantDocNames = Set(rankedDocs.map { $0.0 })
        let candidateChunks = chunks.filter { relevantDocNames.contains($0.documentName) }
        guard !candidateChunks.isEmpty else { return nil }

        // Pontuação por chunk: cosine (semântica) + lexical (BM25-lite), normalizada.
        let cosineScores = candidateChunks.map { cosineSimilarity(queryEmbedding, $0.embedding) }
        let lexicalRaw = candidateChunks.map { Self.lexicalScore(queryTerms: queryTerms, text: $0.content) }
        let lexNorm = Self.normalize(lexicalRaw)

        let ranked = zip(candidateChunks.indices, candidateChunks)
            .map { (i, chunk) -> (RAGChunk, Float) in
                let hybrid = 0.65 * cosineScores[i] + 0.35 * lexNorm[i]
                return (chunk, hybrid)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)

        guard !ranked.isEmpty else { return nil }

        var context = "## Contexto Relevante\n\n"
        context += "### Visão Geral dos Documentos\n"
        for (name, summary, _) in rankedDocs {
            context += "**\(name):** \(summary)\n\n"
        }
        context += "### Trechos Detalhados\n"
        context += "Use estes trechos para responder e cite a origem como [documento — trecho N].\n\n"
        var sources: [RAGSource] = []
        for (chunk, score) in ranked {
            let cite = "\(chunk.documentName) — trecho \(chunk.chunkIndex + 1)/\(chunk.totalChunks)"
            context += "[\(cite), relevância: \(String(format: "%.2f", score))]\n"
            context += chunk.content + "\n\n"
            sources.append(RAGSource(
                document: chunk.documentName,
                chunkIndex: chunk.chunkIndex,
                totalChunks: chunk.totalChunks,
                snippet: String(chunk.content.prefix(280)),
                score: Double(score)
            ))
        }
        return RAGRetrieval(context: context, sources: sources)
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

    // MARK: - Lexical (BM25-lite) helpers

    /// Tokeniza em termos minúsculos com 3+ caracteres.
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    /// Frequência (normalizada pelo tamanho) dos termos da query no texto.
    static func lexicalScore(queryTerms: [String], text: String) -> Float {
        guard !queryTerms.isEmpty else { return 0 }
        let terms = tokenize(text)
        guard !terms.isEmpty else { return 0 }
        var tf: [String: Int] = [:]
        for t in terms { tf[t, default: 0] += 1 }
        var score: Float = 0
        for q in Set(queryTerms) {
            if let count = tf[q] {
                // saturação estilo BM25: ganho decrescente por repetição
                score += Float(count) / (Float(count) + 1.0)
            }
        }
        return score / sqrt(Float(terms.count))
    }

    /// Normaliza um vetor de scores para [0, 1] (min-max).
    static func normalize(_ values: [Float]) -> [Float] {
        guard let mn = values.min(), let mx = values.max(), mx > mn else {
            return values.map { _ in 0 }
        }
        return values.map { ($0 - mn) / (mx - mn) }
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
