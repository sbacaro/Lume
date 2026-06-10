//
//  ContextManager.swift
//  Lume
//

import Foundation
import NaturalLanguage

// MARK: - Context Config

struct ContextConfig {
    var maxTokens: Int = 12_000
    var reservedForResponse: Int = 2_000
    var recentMessageCount: Int = 6
    var summaryMaxTokens: Int = 800
    var compressionEnabled: Bool = true
    var cacheEnabled: Bool = true
}

// MARK: - ContextManager

final class ContextManager {
    let config: ContextConfig

    init(config: ContextConfig = ContextConfig()) {
        self.config = config
    }

    private var availableTokens: Int {
        config.maxTokens - config.reservedForResponse
    }

    // MARK: - Sliding Window

    func applyWindow(to messages: [Message], systemPrompt: String, query: String = "") -> [Message] {
        let systemTokens = estimateTokens(systemPrompt)
        let budget = availableTokens - systemTokens

        if config.compressionEnabled && messages.count > config.recentMessageCount {
            let result = ContextCompressor.shared.compress(
                messages: messages,
                query: query,
                targetTokens: budget,
                systemPrompt: systemPrompt
            )
            return result.messages
        }

        let recent = Array(messages.suffix(config.recentMessageCount))
        let older = Array(messages.dropLast(config.recentMessageCount))
        let recentTokens = recent.map { estimateTokens($0.content) }.reduce(0, +)

        if recentTokens > budget {
            return recent.map { truncateMessage($0, toTokens: budget / config.recentMessageCount) }
        }

        var remaining = budget - recentTokens
        var included: [Message] = []
        for msg in older.reversed() {
            let tokens = estimateTokens(msg.content)
            if tokens <= remaining {
                included.insert(msg, at: 0)
                remaining -= tokens
            } else if remaining > 100 {
                included.insert(truncateMessage(msg, toTokens: remaining), at: 0)
                break
            } else { break }
        }

        return included + recent
    }

    // MARK: - System Prompt

    func optimizeSystemPrompt(_ prompt: String) -> String {
        let base = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        let instruction = "Responda no idioma do usuário. Quando listar tarefas ou passos, use checklist Markdown (- [ ] tarefa). Quando o pedido for ambíguo, use o formato ```suggestions { \"question\": \"...\", \"options\": [...] }``` para apresentar opções clicáveis ao usuário."

        if base.isEmpty {
            return instruction
        }
        return base + "\n\n" + instruction
    }

    func optimizeSystemPromptForCustomProvider(_ prompt: String) -> String {
        return optimizeSystemPrompt(prompt)
    }

    // MARK: - Parser de tarefas do Markdown

    static func extractTasks(from content: String, messageID: String) -> [ConversationTask] {
        var tasks: [ConversationTask] = []
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("- [ ] ") {
                let text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    tasks.append(ConversationTask(text: text, isDone: false, sourceMessageID: messageID))
                }
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    tasks.append(ConversationTask(text: text, isDone: true, sourceMessageID: messageID))
                }
            } else if trimmed.hasPrefix("* [ ] ") {
                let text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    tasks.append(ConversationTask(text: text, isDone: false, sourceMessageID: messageID))
                }
            } else if trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") {
                let text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    tasks.append(ConversationTask(text: text, isDone: true, sourceMessageID: messageID))
                }
            }
        }

        return tasks
    }

    // MARK: - Parser de suggestions

    struct SuggestionBlock {
        let question: String
        let options: [String]
        let textBefore: String
        let textAfter: String
    }

    static func extractSuggestions(from content: String) -> SuggestionBlock? {
        let marker = "```suggestions"
        guard let start = content.range(of: marker),
              let end = content.range(of: "```", range: start.upperBound..<content.endIndex) else {
            return nil
        }

        let jsonString = String(content[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let question = json["question"] as? String,
              let options = json["options"] as? [String] else {
            return nil
        }

        let textBefore = String(content[content.startIndex..<start.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let textAfter = String(content[end.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SuggestionBlock(
            question: question,
            options: options,
            textBefore: textBefore,
            textAfter: textAfter
        )
    }

    // MARK: - Summarization

    func needsSummarization(messages: [Message], systemPrompt: String) -> Bool {
        let total = messages.map { estimateTokens($0.content) }.reduce(0, +)
                  + estimateTokens(systemPrompt)
        return total > availableTokens
    }

    func buildSummarizationPrompt(for messages: [Message]) -> String {
        let history = messages.map { "\($0.role.rawValue.uppercased()): \($0.content)" }
            .joined(separator: "\n\n")
        return """
        Resuma a conversa abaixo em \(config.summaryMaxTokens / 4) palavras ou menos.
        Foque em: decisões tomadas, contexto importante, questões não resolvidas.
        Seja conciso e factual.

        CONVERSA:
        \(history)

        RESUMO:
        """
    }

    // MARK: - Helpers

    func estimateTokens(_ text: String) -> Int { max(1, text.count / 4) }

    private func truncateMessage(_ message: Message, toTokens: Int) -> Message {
        let truncated = String(message.content.prefix(toTokens * 4))
        return Message(role: message.role, content: truncated + "…")
    }
}
