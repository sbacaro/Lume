//
//  RAGEngineTests.swift
//  LumeTests
//
//  Cobre os helpers puros de pontuação do RAG (cosine, lexical, normalize, tokenize).
//

import Testing
import Foundation
@testable import Lume

@MainActor
struct RAGEngineTests {

    // MARK: - cosineSimilarity

    @Test func cosineIdenticalVectorsIsOne() {
        let v: [Float] = [1, 2, 3, 4]
        #expect(abs(RAGEngine.cosineSimilarity(v, v) - 1.0) < 1e-5)
    }

    @Test func cosineOrthogonalVectorsIsZero() {
        #expect(abs(RAGEngine.cosineSimilarity([1, 0], [0, 1])) < 1e-6)
    }

    @Test func cosineOppositeVectorsIsMinusOne() {
        #expect(abs(RAGEngine.cosineSimilarity([1, 1], [-1, -1]) - (-1.0)) < 1e-5)
    }

    @Test func cosineMismatchedOrEmptyIsZero() {
        #expect(RAGEngine.cosineSimilarity([1, 2, 3], [1, 2]) == 0)
        #expect(RAGEngine.cosineSimilarity([], []) == 0)
        #expect(RAGEngine.cosineSimilarity([0, 0], [0, 0]) == 0)
    }

    // MARK: - tokenize

    @Test func tokenizeLowercasesAndDropsShortTokens() {
        let tokens = RAGEngine.tokenize("O Gato, a Casa e um PC!")
        // "o", "a", "e", "um", "pc" têm < 3 chars; sobram "gato", "casa".
        #expect(tokens == ["gato", "casa"])
    }

    @Test func tokenizeSplitsOnNonAlphanumerics() {
        let tokens = RAGEngine.tokenize("swift6_concurrency-model")
        #expect(tokens.contains("swift6"))
        #expect(tokens.contains("concurrency"))
        #expect(tokens.contains("model"))
    }

    // MARK: - lexicalScore

    @Test func lexicalScoreZeroWhenNoOverlap() {
        let score = RAGEngine.lexicalScore(queryTerms: ["banana"], text: "o gato dorme na casa")
        #expect(score == 0)
    }

    @Test func lexicalScorePositiveWhenTermsMatch() {
        let score = RAGEngine.lexicalScore(queryTerms: ["gato"], text: "o gato dorme; o gato ronrona")
        #expect(score > 0)
    }

    @Test func lexicalScoreEmptyQueryIsZero() {
        #expect(RAGEngine.lexicalScore(queryTerms: [], text: "qualquer texto aqui") == 0)
    }

    // MARK: - normalize

    @Test func normalizeMapsToUnitRange() {
        let result = RAGEngine.normalize([0, 5, 10])
        #expect(result[0] == 0)
        #expect(abs(result[1] - 0.5) < 1e-6)
        #expect(result[2] == 1)
    }

    @Test func normalizeFlatVectorReturnsZeros() {
        // min == max → evita divisão por zero, retorna zeros.
        #expect(RAGEngine.normalize([3, 3, 3]) == [0, 0, 0])
    }

    // MARK: - Persistência do índice

    @Test func contentHashIsDeterministicAndDistinct() {
        let a = RAGIndexStore.contentHash("hello world")
        #expect(a == RAGIndexStore.contentHash("hello world"))
        #expect(a != RAGIndexStore.contentHash("hello world!"))
        #expect(a.count == 64) // SHA-256 em hex
    }

    @Test func persistedDocumentRoundTrips() throws {
        let doc = PersistedDocument(
            documentName: "notes.txt",
            contentHash: "abc",
            backendID: "contextual",
            dimension: 512,
            summary: "resumo",
            summaryEmbedding: [0.25, 0.5],
            chunks: [
                RAGChunk(id: "1", documentName: "notes.txt", content: "x",
                         summary: "s", embedding: [0.5], chunkIndex: 0, totalChunks: 1)
            ]
        )
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(PersistedDocument.self, from: data)
        #expect(decoded.documentName == "notes.txt")
        #expect(decoded.backendID == "contextual")
        #expect(decoded.summaryEmbedding == [0.25, 0.5])
        #expect(decoded.chunks.count == 1)
        #expect(decoded.chunks[0].embedding == [0.5])
    }
}
