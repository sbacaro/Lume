//
//  AIProvider.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation

struct MessageSnapshot: Sendable {
    let role: String
    let content: String
}

protocol AIProvider: AnyObject {
    var name: String { get }
    var baseURL: URL { get set }
    var apiKey: String { get set }
    var defaultModel: String { get set }
    var temperature: Double { get set }
    var maxTokens: Int { get set }

    func validateAPIKey() async throws -> Bool
    func fetchAvailableModels() async throws -> [String]

    func sendMessage(
        content: String,
        conversationHistory: [MessageSnapshot],
        systemPrompt: String
    ) async throws -> String

    func streamMessage(
        content: String,
        conversationHistory: [MessageSnapshot],
        systemPrompt: String
    ) -> AsyncThrowingStream<String, Error>
}

// MARK: - Default implementations

extension AIProvider {

    func fetchAvailableModels() async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("/models"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.unknown("HTTP \(http.statusCode): \(body.prefix(200))")
        }

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)

        // Only exclude pure utility models — keep everything else
        let excluded = ["whisper", "tts", "dall-e", "davinci", "babbage",
                        "ada", "curie", "embed", "rerank"]

        return decoded.data
            .map { $0.id }
            .filter { id in
                let lower = id.lowercased()
                return !excluded.contains(where: { lower.contains($0) })
            }
            .sorted()
    }

    func sendMessage(
        content: String,
        conversationHistory: [Message],
        systemPrompt: String
    ) async throws -> String {
        try await sendMessage(
            content: content,
            conversationHistory: conversationHistory.map {
                MessageSnapshot(role: $0.role.rawValue, content: $0.content)
            },
            systemPrompt: systemPrompt
        )
    }

    func streamMessage(
        content: String,
        conversationHistory: [Message],
        systemPrompt: String
    ) -> AsyncThrowingStream<String, Error> {
        streamMessage(
            content: content,
            conversationHistory: conversationHistory.map {
                MessageSnapshot(role: $0.role.rawValue, content: $0.content)
            },
            systemPrompt: systemPrompt
        )
    }
}

// MARK: - Models response

struct OpenAIModelsResponse: Decodable {
    let data: [OpenAIModelItem]
}

struct OpenAIModelItem: Decodable {
    let id: String
}
