//
//  PromptCache.swift
//  Lume
//
//  Prompt Caching nativo para Anthropic (cache_control) e OpenAI (seed + caching automático).
//  Reduz custo e latência em até 90% para prompts repetidos.
//

import Foundation

// MARK: - Cache Strategy

enum CacheStrategy {
    case none
    case anthropicEphemeral
    case anthropicPersistent
    case openAIAutomatic
}

// MARK: - Cached Message

struct CachedMessage: Encodable {
    let role: String
    let content: CachedContent

    enum CachedContent: Encodable {
        case text(String)
        case withCacheControl(text: String, cacheControl: CacheControl)

        func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let text):
                var container = encoder.singleValueContainer()
                try container.encode(text)
            case .withCacheControl(let text, let cache):
                var container = encoder.singleValueContainer()
                try container.encode([ContentBlock(type: "text", text: text, cacheControl: cache)])
            }
        }
    }

    struct ContentBlock: Encodable {
        let type: String
        let text: String
        let cacheControl: CacheControl
        enum CodingKeys: String, CodingKey {
            case type, text
            case cacheControl = "cache_control"
        }
    }

    struct CacheControl: Encodable {
        let type: String
    }
}

// MARK: - Prompt Cache Builder

enum PromptCacheBuilder {

    /// Aplica cache_control ao system prompt para Anthropic
    static func buildAnthropicSystemPrompt(_ text: String, strategy: CacheStrategy) -> [Any] {
        guard strategy != .none, !text.isEmpty else {
            return [["type": "text", "text": text]]
        }
        return [[
            "type": "text",
            "text": text,
            "cache_control": ["type": "ephemeral"]
        ]]
    }

    /// Aplica cache nas primeiras mensagens do histórico (as mais estáveis)
    static func buildAnthropicMessages(
        _ messages: [Message],
        cacheThreshold: Int = 3
    ) -> [[String: Any]] {
        let count = messages.count
        return messages.enumerated().map { idx, msg in
            let shouldCache = idx < cacheThreshold && idx == min(cacheThreshold - 1, count - 2)
            let role = msg.role == .user ? "user" : "assistant"
            if shouldCache && msg.content.count > 1024 {
                return [
                    "role": role,
                    "content": [[
                        "type": "text",
                        "text": msg.content,
                        "cache_control": ["type": "ephemeral"]
                    ]]
                ]
            } else {
                return ["role": role, "content": msg.content]
            }
        }
    }

    /// Para OpenAI: seed determinístico baseado no system prompt
    static func openAISeed(for systemPrompt: String) -> Int {
        abs(systemPrompt.hashValue) % 2_147_483_647
    }

    /// Verifica se o prompt é longo o suficiente para cache (mínimo 1024 tokens)
    static func shouldCache(text: String, provider: String) -> Bool {
        text.count / 4 >= 1024
    }

    /// Estima a economia de custo com caching
    static func estimateSavings(tokens: Int, provider: String) -> String {
        switch provider {
        case "anthropic":
            return "~\(Int(Double(tokens) * 0.90)) tokens economizados (90% desconto Anthropic)"
        case "openai":
            return "~\(Int(Double(tokens) * 0.50)) tokens economizados (50% desconto OpenAI)"
        default:
            return ""
        }
    }
}
