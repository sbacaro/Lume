//
//  RAGEngine.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//
//  Indexação e busca semântica de documentos para RAG.
//  Embeddings via NLContextualEmbedding (transformer multilíngue, contextual,
//  nativo e offline), com fallback para NLEmbedding (word2vec) quando os assets
//  do modelo contextual não estão disponíveis.
//

import Foundation
import CryptoKit
import NaturalLanguage

// MARK: - Chunk

nonisolated struct RAGChunk: Sendable, Codable {
    let id: String
    let documentName: String
    let content: String
    let summary: String
    let embedding: [Float]
    let chunkIndex: Int
    let totalChunks: Int
}

// MARK: - Persistência do índice

/// Documento indexado serializável (chunks + resumo + embeddings) para cache em disco.
nonisolated struct PersistedDocument: Codable {
    let documentName: String
    let contentHash: String
    let backendID: String
    let dimension: Int
    let summary: String
    let summaryEmbedding: [Float]
    let chunks: [RAGChunk]
}

/// Cache em disco do índice RAG (Application Support/Lume/RAGIndex), um arquivo por
/// documento. Invalidação por hash de conteúdo + identidade do backend de embedding.
enum RAGIndexStore {

    private nonisolated static let directory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Lume/RAGIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }()

    /// SHA-256 hex de uma string (usado como hash de conteúdo e nome de arquivo).
    nonisolated static func contentHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func fileURL(for document: String) -> URL {
        directory.appendingPathComponent(contentHash(document) + ".json")
    }

    nonisolated static func load(document: String) -> PersistedDocument? {
        guard let data = try? Data(contentsOf: fileURL(for: document)) else { return nil }
        return try? JSONDecoder().decode(PersistedDocument.self, from: data)
    }

    nonisolated static func save(_ doc: PersistedDocument) {
        guard let data = try? JSONEncoder().encode(doc) else { return }
        try? data.write(to: fileURL(for: doc.documentName), options: .atomic)
    }

    nonisolated static func delete(document: String) {
        try? FileManager.default.removeItem(at: fileURL(for: document))
    }
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
    /// Embedding do resumo de cada documento — calculado no index() e reutilizado
    /// em toda query (antes era recomputado a cada busca).
    private var documentSummaryEmbeddings: [String: [Float]] = [:]
    private let embedder = TextEmbedder()
    private let chunkSize = 512
    private let chunkOverlap = 64
    private let topK = 5
    private let summaryTopK = 2

    // MARK: - Index

    func index(file: FileIngestionManager.IngestedFile) async {
        clearInMemory(name: file.name)
        await embedder.loadIfNeeded()
        let backendID = await embedder.backendID
        let dimension = await embedder.dimension
        let hash = RAGIndexStore.contentHash(file.content)

        // Cache hit: mesmo conteúdo e mesmo backend de embedding → reaproveita do disco
        // (evita re-embedar tudo a cada abertura do app).
        if let cached = RAGIndexStore.load(document: file.name),
           cached.contentHash == hash,
           cached.backendID == backendID,
           cached.dimension == dimension {
            documentSummaries[file.name] = cached.summary
            documentSummaryEmbeddings[file.name] = cached.summaryEmbedding
            chunks.append(contentsOf: cached.chunks)
            return
        }

        // Cache miss: (re)processa e grava no disco.
        let rawChunks = splitIntoChunks(text: file.content, name: file.name)
        let docSummary = summarize(text: file.content, maxSentences: 5)
        let summaryEmbedding = await embedder.embed(text: docSummary)
        documentSummaries[file.name] = docSummary
        documentSummaryEmbeddings[file.name] = summaryEmbedding

        var indexed: [RAGChunk] = []
        for (i, chunkText) in rawChunks.enumerated() {
            let summary = summarize(text: chunkText, maxSentences: 2)
            let embedding = await embedder.embed(text: chunkText)
            indexed.append(RAGChunk(
                id: UUID().uuidString,
                documentName: file.name,
                content: chunkText,
                summary: summary,
                embedding: embedding,
                chunkIndex: i,
                totalChunks: rawChunks.count
            ))
        }
        chunks.append(contentsOf: indexed)

        RAGIndexStore.save(PersistedDocument(
            documentName: file.name,
            contentHash: hash,
            backendID: backendID,
            dimension: dimension,
            summary: docSummary,
            summaryEmbedding: summaryEmbedding,
            chunks: indexed
        ))
    }

    // MARK: - Retrieve

    /// Compatibilidade: retorna apenas o texto de contexto.
    func buildContext(for query: String) async -> String? {
        await buildRetrieval(for: query)?.context
    }

    /// Recuperação híbrida (vetorial + lexical) com fontes para citação.
    func buildRetrieval(for query: String) async -> RAGRetrieval? {
        guard !chunks.isEmpty else { return nil }
        await embedder.loadIfNeeded()

        let queryEmbedding = await embedder.embed(text: query)
        let queryTerms = Self.tokenize(query)

        // Documentos mais relevantes pela similaridade do resumo (semântica),
        // usando os embeddings de resumo já cacheados no index().
        let rankedDocs = documentSummaryEmbeddings
            .map { (name, emb) -> (String, String, Float) in
                (name, documentSummaries[name] ?? "", Self.cosineSimilarity(queryEmbedding, emb))
            }
            .sorted { $0.2 > $1.2 }
            .prefix(summaryTopK)

        let relevantDocNames = Set(rankedDocs.map { $0.0 })
        let candidateChunks = chunks.filter { relevantDocNames.contains($0.documentName) }
        guard !candidateChunks.isEmpty else { return nil }

        // Pontuação por chunk: cosine (semântica) + lexical (BM25-lite), normalizada.
        let cosineScores = candidateChunks.map { Self.cosineSimilarity(queryEmbedding, $0.embedding) }
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

    /// Limpa o estado em memória de um documento, sem tocar no cache em disco.
    private func clearInMemory(name: String) {
        chunks.removeAll { $0.documentName == name }
        documentSummaries.removeValue(forKey: name)
        documentSummaryEmbeddings.removeValue(forKey: name)
    }

    /// Remove um documento do índice em memória **e** do cache em disco.
    func removeDocument(name: String) {
        clearInMemory(name: name)
        RAGIndexStore.delete(document: name)
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

    // MARK: - Pure scoring helpers (nonisolated — testáveis)

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }

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

/// Gera embeddings de texto. Prioriza `NLContextualEmbedding` (transformer
/// multilíngue, contextual) e cai para `NLEmbedding` (word2vec, média de
/// vetores por palavra) quando os assets do modelo contextual não existem.
///
/// É um `actor` para confinar o estado não-`Sendable` dos modelos do
/// NaturalLanguage sob strict concurrency. A dimensão do vetor é fixada na
/// primeira carga e mantida durante toda a sessão (índice + queries casam).
actor TextEmbedder {

    private enum Backend {
        case contextual(NLContextualEmbedding)
        case word(NLEmbedding)
        case none
    }

    private var backend: Backend = .none
    private var loaded = false
    /// Dimensão do vetor produzido (definida na carga).
    private(set) var dimension = 512
    /// Identidade do backend ("contextual" | "word" | "none") — usada para invalidar
    /// o cache em disco quando o modelo de embedding muda entre versões.
    private(set) var backendID = "none"

    /// Carrega o melhor backend disponível uma única vez.
    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true

        // 1) Modelo contextual multilíngue (script latino cobre PT + EN).
        //    load() carrega os assets se já presentes no sistema; se ainda não
        //    baixados, lança e caímos no fallback word-embedding nesta sessão.
        if let ce = NLContextualEmbedding(script: .latin), (try? ce.load()) != nil {
            backend = .contextual(ce)
            dimension = ce.dimension
            backendID = "contextual"
            return
        }

        // 2) Fallback: word embedding (legado).
        if let we = NLEmbedding.wordEmbedding(for: .english)
            ?? NLEmbedding.wordEmbedding(for: .portuguese) {
            backend = .word(we)
            dimension = we.dimension
            backendID = "word"
            return
        }

        backend = .none
        backendID = "none"
    }

    func embed(text: String) async -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return zeros }

        switch backend {
        case .contextual(let ce):
            return contextualVector(ce, text: trimmed)
        case .word(let we):
            return wordMeanVector(we, text: trimmed)
        case .none:
            return zeros
        }
    }

    private var zeros: [Float] { Array(repeating: 0, count: dimension) }

    // MARK: - Contextual (transformer) — mean pooling dos vetores de token

    private func contextualVector(_ ce: NLContextualEmbedding, text: String) -> [Float] {
        let language = NLLanguageRecognizer.dominantLanguage(for: text) ?? .english
        guard let result = try? ce.embeddingResult(for: text, language: language) else {
            return zeros
        }
        var mean = [Double](repeating: 0, count: dimension)
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            if vector.count == self.dimension {
                for i in 0..<self.dimension { mean[i] += vector[i] }
                count += 1
            }
            return true
        }
        guard count > 0 else { return zeros }
        let n = Double(count)
        return mean.map { Float($0 / n) }
    }

    // MARK: - Word2vec (fallback) — média dos vetores de palavra

    private func wordMeanVector(_ embedding: NLEmbedding, text: String) -> [Float] {
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
        guard !vectors.isEmpty else { return zeros }
        let dim = vectors[0].count
        var mean = [Double](repeating: 0, count: dim)
        for v in vectors { for i in 0..<dim { mean[i] += v[i] } }
        let n = Double(vectors.count)
        return mean.map { Float($0 / n) }
    }
}
