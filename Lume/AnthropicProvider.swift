//
//  AnthropicProvider.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation

/// Budget de tokens para extended thinking do Claude
enum ThinkingBudget: Int, CaseIterable {
    case off      = 0
    case low      = 1024
    case medium   = 5000
    case high     = 10000
    case max      = 16000

    var label: String {
        switch self {
        case .off:    return "Desligado"
        case .low:    return "Rápido (1k)"
        case .medium: return "Balanceado (5k)"
        case .high:   return "Profundo (10k)"
        case .max:    return "Máximo (16k)"
        }
    }
}

final class AnthropicProvider: AIProvider {
    let name = "Anthropic"
    var baseURL = URL(string: "https://api.anthropic.com/v1")!
    var apiKey: String
    var defaultModel: String = "claude-opus-4-8"
    var temperature: Double = 0.7
    var maxTokens: Int = 8192
    var usePromptCaching = true

    /// Extended thinking — quando .off, desabilitado
    var thinkingBudget: ThinkingBudget = .off

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func validateAPIKey() async throws -> Bool {
        let body: [String: Any] = [
            "model": defaultModel,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        let request = URLRequest.createAnthropicRequest(
            endpoint: "/messages",
            method: "POST",
            apiKey: apiKey,
            baseURL: baseURL,
            usePromptCaching: false,
            body: body
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200 || http.statusCode == 403
    }

    func sendMessage(
        content: String,
        conversationHistory: [MessageSnapshot],
        systemPrompt: String
    ) async throws -> String {
        var accumulated = ""
        for try await chunk in streamMessage(
            content: content,
            conversationHistory: conversationHistory,
            systemPrompt: systemPrompt
        ) { accumulated += chunk }
        return accumulated
    }

    func streamMessage(
        content: String,
        conversationHistory: [MessageSnapshot],
        systemPrompt: String
    ) -> AsyncThrowingStream<String, Error> {
        let apiKey           = self.apiKey
        let baseURL          = self.baseURL
        let model            = self.defaultModel
        var maxTokens        = self.maxTokens
        let usePromptCaching = self.usePromptCaching
        let thinkingBudget   = self.thinkingBudget
        let temperature      = self.temperature

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var messages: [[String: Any]] = []
                    for msg in conversationHistory {
                        messages.append(["role": msg.role, "content": msg.content])
                    }
                    messages.append(["role": "user", "content": content])

                    let systemBlock: Any = usePromptCaching
                        ? [["type": "text", "text": systemPrompt,
                            "cache_control": ["type": "ephemeral"]]]
                        : systemPrompt

                    // Auto-continuação: loop até stop_reason != "max_tokens"
                    var accumulatedText = ""
                    var iterationCount = 0
                    let maxContinuations = 10

                    while iterationCount < maxContinuations {
                        iterationCount += 1

                        var payload: [String: Any] = [
                            "model": model,
                            "max_tokens": maxTokens,
                            "system": systemBlock,
                            "messages": messages,
                            "stream": true
                        ]

                        // Extended thinking
                        if thinkingBudget != .off {
                            payload["thinking"] = [
                                "type": "enabled",
                                "budget_tokens": thinkingBudget.rawValue
                            ]
                            maxTokens = max(maxTokens, thinkingBudget.rawValue + 1024)
                            payload["max_tokens"] = maxTokens
                            payload["temperature"] = 1
                        } else {
                            payload["temperature"] = temperature
                        }

                        let request = URLRequest.createAnthropicRequest(
                            endpoint: "/messages",
                            method: "POST",
                            apiKey: apiKey,
                            baseURL: baseURL,
                            usePromptCaching: usePromptCaching,
                            useThinking: thinkingBudget != .off,
                            body: payload
                        )

                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 200 else {
                            continuation.finish(throwing: AIProviderError.invalidResponse)
                            return
                        }

                        var stopReason: String? = nil
                        var chunkText = ""
                        var inThinkingBlock = false

                        for try await line in bytes.lines {
                            guard line.hasPrefix("data: ") else { continue }
                            let jsonString = String(line.dropFirst(6))
                            guard let data = jsonString.data(using: .utf8),
                                  let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
                            else { continue }

                            switch event.type {
                            case "message_delta":
                                // Captura stop_reason para decidir se continua
                                stopReason = event.delta?.stopReason
                            case "content_block_start":
                                if event.contentBlock?.type == "thinking" {
                                    inThinkingBlock = true
                                    continuation.yield("<think>")
                                } else {
                                    inThinkingBlock = false
                                }
                            case "content_block_stop":
                                if inThinkingBlock {
                                    continuation.yield("</think>")
                                    inThinkingBlock = false
                                }
                            case "content_block_delta":
                                if let text = event.delta?.text, !text.isEmpty {
                                    continuation.yield(text)
                                    chunkText += text
                                } else if let thinking = event.delta?.thinking, !thinking.isEmpty {
                                    continuation.yield(thinking)
                                }
                            default:
                                break
                            }
                        }

                        accumulatedText += chunkText

                        // Terminou naturalmente — encerra loop
                        if stopReason != "max_tokens" {
                            break
                        }

                        // Auto-continuação silenciosa: o usuário vê o texto chegando sem interrupção
                        messages.append(["role": "assistant", "content": accumulatedText])
                        messages.append(["role": "user", "content": "Continue exatamente de onde parou."])
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Fetch Models (Anthropic usa x-api-key, não Authorization: Bearer)

    func fetchAvailableModels() async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("/models"))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // Fallback para lista estática se a API não responder
            return [
                "claude-opus-4-8",
                "claude-sonnet-4-6",
                "claude-haiku-4-5-20251001"
            ]
        }

        struct AnthropicModelsResponse: Decodable {
            let data: [AnthropicModelItem]
            struct AnthropicModelItem: Decodable { let id: String }
        }

        guard let decoded = try? JSONDecoder().decode(AnthropicModelsResponse.self, from: data) else {
            return ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
        }

        return decoded.data.map { $0.id }
    }
}

// MARK: - Streaming Types

struct AnthropicStreamEvent: Decodable {
    let type: String
    let delta: AnthropicStreamDelta?
    let contentBlock: AnthropicContentBlock?

    enum CodingKeys: String, CodingKey {
        case type, delta
        case contentBlock = "content_block"
    }
}

struct AnthropicStreamDelta: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case type, text, thinking
        case stopReason = "stop_reason"
    }
}

struct AnthropicContentBlock: Decodable {
    let type: String?
}

struct AnthropicResponse: Decodable {
    let content: [AnthropicContent]
}

struct AnthropicContent: Decodable {
    let text: String
}

// MARK: - URLRequest Extension

extension URLRequest {
    static func createAnthropicRequest(
        endpoint: String,
        method: String = "GET",
        apiKey: String,
        baseURL: URL,
        usePromptCaching: Bool = false,
        useThinking: Bool = false,
        body: [String: Any]? = nil
    ) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var betas: [String] = []
        if usePromptCaching { betas.append("prompt-caching-2024-07-31") }
        if useThinking { betas.append("interleaved-thinking-2025-05-14") }
        if !betas.isEmpty {
            request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }

        if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        return request
    }
}
