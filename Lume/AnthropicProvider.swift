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
                    // A API da Anthropic é estrita: papel `system` só no topo (nunca no
                    // array de mensagens), papéis têm de ALTERNAR user/assistant, a 1ª
                    // mensagem precisa ser `user` e não pode haver conteúdo vazio. O app
                    // monta as mensagens "à moda OpenAI" (tolerante), então sanitizamos aqui.
                    var raw = conversationHistory.map { (role: $0.role, content: $0.content) }
                    raw.append((role: "user", content: content))
                    let (systemExtra, messages0) = AnthropicProvider.sanitizeForAnthropic(raw)
                    var messages = messages0

                    // Qualquer texto de mensagens `system` do histórico (ex.: resumo de
                    // contexto) é dobrado no system prompt — onde o Claude espera.
                    let systemText = systemExtra.isEmpty
                        ? systemPrompt
                        : systemPrompt + "\n\n" + systemExtra

                    let systemBlock: Any = usePromptCaching
                        ? [["type": "text", "text": systemText,
                            "cache_control": ["type": "ephemeral"]]]
                        : systemText

                    // Ferramentas: mesma fonte única usada pelos demais providers
                    // (AgentToolExecutor.availableTools), garantindo paridade total.
                    let toolDefs = AnthropicProvider.buildToolDefinitions()
                    var toolsEnabled = !toolDefs.isEmpty

                    // Loop combinado: cobre auto-continuação (stop_reason == "max_tokens")
                    // e rodadas de ferramentas (stop_reason == "tool_use").
                    //
                    // O limite se REINICIA a cada progresso (ferramenta executada, ou texto/
                    // thinking entregue): uma tarefa longa e produtiva continua até a resposta
                    // final, sem parar no meio. Só interrompe se ficar várias rodadas SEGUIDAS
                    // sem progredir (proteção contra loop), com uma trava absoluta de segurança.
                    var idleRounds = 0
                    let maxIdleRounds = 8
                    var totalRounds = 0
                    let hardCap = 200

                    // Orçamento do pacote para CABER na janela do modelo durante o loop. O
                    // histórico (system é separado, no systemBlock) é aparado antes de cada
                    // chamada — as saídas de ferramenta antigas, que mais incham, são truncadas.
                    let ctxWindow = LLMRouter.maxContextWindow(for: model)
                    let win = ctxWindow > 4096 ? ctxWindow : 128_000
                    let sysTok = AnthropicProvider.estTokens(systemBlock)
                    let respReserve = maxTokens > 0 ? maxTokens : 8_192
                    let loopBudget = max(8_000, win - sysTok - respReserve - max(4_000, win / 20))
                    var contextRetries = 0
                    let maxContextRetries = 4

                    while idleRounds < maxIdleRounds && totalRounds < hardCap {
                        totalRounds += 1

                        // Mantém o pacote dentro da janela antes de cada chamada.
                        AnthropicProvider.trimMessagesToBudget(&messages, budgetTokens: loopBudget)

                        var payload: [String: Any] = [
                            "model": model,
                            "max_tokens": maxTokens,
                            "system": systemBlock,
                            "messages": messages,
                            "stream": true
                        ]
                        if toolsEnabled { payload["tools"] = toolDefs }

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
                        guard let http = response as? HTTPURLResponse else {
                            continuation.finish(throwing: AIProviderError.invalidResponse)
                            return
                        }
                        if http.statusCode != 200 {
                            var body = ""
                            for try await line in bytes.lines {
                                body += line
                                if body.count > 4000 { break }
                            }
                            // Erro relacionado a ferramentas: desabilita e tenta de novo sem tools
                            let lower = body.lowercased()
                            if toolsEnabled && (lower.contains("tool") || lower.contains("not supported")) {
                                toolsEnabled = false
                                totalRounds -= 1
                                continue
                            }
                            // Limite de contexto estourado → comprime mais forte e re-tenta,
                            // em vez de falhar a resposta.
                            let ctxErr = (http.statusCode == 400 || http.statusCode == 413)
                                && (lower.contains("context") || lower.contains("too long")
                                    || lower.contains("maximum") || lower.contains("token"))
                            if ctxErr && contextRetries < maxContextRetries {
                                contextRetries += 1
                                let tighter = max(4_000, loopBudget / (1 + contextRetries))
                                AnthropicProvider.trimMessagesToBudget(&messages, budgetTokens: tighter, keepRecent: 4)
                                totalRounds -= 1
                                continue
                            }
                            continuation.finish(throwing: AIProviderError.unknown("HTTP \(http.statusCode): \(body)"))
                            return
                        }

                        var stopReason: String? = nil
                        var chunkText = ""
                        var inThinkingBlock = false
                        // Blocos da resposta acumulados por índice, para reconstruir a
                        // mensagem do assistant na ordem original (thinking → text → tool_use).
                        var blockType: [Int: String] = [:]
                        var blockText: [Int: String] = [:]                       // texto de "text" e "thinking"
                        var blockSignature: [Int: String] = [:]                  // assinatura de "thinking"
                        var toolUses: [Int: (id: String, name: String, json: String)] = [:]

                        for try await line in bytes.lines {
                            guard line.hasPrefix("data: ") else { continue }
                            let jsonString = String(line.dropFirst(6))
                            guard let data = jsonString.data(using: .utf8),
                                  let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
                            else { continue }

                            switch event.type {
                            case "error":
                                // Erro no meio do stream (ex.: overloaded_error). Antes era
                                // ignorado → resposta saía vazia. Agora propaga com mensagem.
                                let msg = event.error?.message ?? "Erro no stream da Anthropic."
                                continuation.finish(throwing: AIProviderError.unknown(msg))
                                return
                            case "message_delta":
                                // Captura stop_reason para decidir continuação/ferramentas
                                stopReason = event.delta?.stopReason
                            case "content_block_start":
                                let idx = event.index ?? 0
                                let type = event.contentBlock?.type ?? "text"
                                blockType[idx] = type
                                if type == "thinking" {
                                    inThinkingBlock = true
                                    continuation.yield("<think>")
                                } else if type == "tool_use" {
                                    inThinkingBlock = false
                                    toolUses[idx] = (
                                        id: event.contentBlock?.id ?? "",
                                        name: event.contentBlock?.name ?? "",
                                        json: ""
                                    )
                                } else {
                                    inThinkingBlock = false
                                }
                            case "content_block_stop":
                                if inThinkingBlock {
                                    continuation.yield("</think>")
                                    inThinkingBlock = false
                                }
                            case "content_block_delta":
                                let idx = event.index ?? 0
                                if let partial = event.delta?.partialJson {
                                    // Argumentos da ferramenta chegam como input_json_delta
                                    if var acc = toolUses[idx] {
                                        acc.json += partial
                                        toolUses[idx] = acc
                                    }
                                } else if let text = event.delta?.text, !text.isEmpty {
                                    continuation.yield(text)
                                    chunkText += text
                                    blockText[idx, default: ""] += text
                                } else if let thinking = event.delta?.thinking, !thinking.isEmpty {
                                    continuation.yield(thinking)
                                    blockText[idx, default: ""] += thinking
                                } else if let signature = event.delta?.signature {
                                    blockSignature[idx] = signature
                                }
                            default:
                                break
                            }
                        }

                        // Progresso desta rodada reinicia o limite (ver topo do loop):
                        // ferramenta executada, ou texto/thinking entregue.
                        let producedThinking = blockType.values.contains("thinking")
                        let producedText = !chunkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if !toolUses.isEmpty || producedText || producedThinking {
                            idleRounds = 0
                        } else {
                            idleRounds += 1
                        }

                        // Nenhuma ferramenta chamada → fluxo de texto puro
                        if toolUses.isEmpty {
                            // Auto-continuação só se houve texto (Claude rejeita assistant vazio).
                            if stopReason == "max_tokens",
                               !chunkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                messages.append(["role": "assistant", "content": chunkText])
                                messages.append(["role": "user", "content": "Continue exatamente de onde parou."])
                                continue
                            }
                            break
                        }

                        // Rodada de ferramentas: reconstrói a mensagem do assistant com TODOS
                        // os blocos na ordem original. Os blocos de thinking precisam ser
                        // reenviados com a assinatura quando extended thinking está ativo.
                        var assistantContent: [[String: Any]] = []
                        for idx in blockType.keys.sorted() {
                            switch blockType[idx] ?? "" {
                            case "thinking":
                                var tb: [String: Any] = ["type": "thinking", "thinking": blockText[idx] ?? ""]
                                if let sig = blockSignature[idx] { tb["signature"] = sig }
                                assistantContent.append(tb)
                            case "text":
                                let t = blockText[idx] ?? ""
                                if !t.isEmpty { assistantContent.append(["type": "text", "text": t]) }
                            case "tool_use":
                                if let tu = toolUses[idx] {
                                    let inputObj = (try? JSONSerialization.jsonObject(with: Data(tu.json.utf8))) as? [String: Any] ?? [:]
                                    assistantContent.append([
                                        "type": "tool_use",
                                        "id": tu.id,
                                        "name": tu.name,
                                        "input": inputObj
                                    ])
                                }
                            default:
                                break
                            }
                        }
                        messages.append(["role": "assistant", "content": assistantContent])

                        // Executa cada ferramenta (em ordem) e monta os tool_result
                        let orderedTools = toolUses.sorted { $0.key < $1.key }.map { $0.value }
                        var resultBlocks: [[String: Any]] = []
                        for tu in orderedTools {
                            var input: [String: String] = [:]
                            if let argsObj = (try? JSONSerialization.jsonObject(with: Data(tu.json.utf8))) as? [String: Any] {
                                for (k, v) in argsObj { input[k] = "\(v)" }
                            }

                            // Sinaliza a atividade em tempo real (mesmo formato do OpenAIProvider)
                            continuation.yield("[[STATUS:\(OpenAIProvider.statusLabel(for: tu.name))]]")
                            // executeStreaming transmite a saída do shell ao vivo para a UI.
                            let result = await AgentToolExecutor.shared.executeStreaming(toolName: tu.name, input: input) { line in
                                continuation.yield("[[STATUS:\(line)]]")
                            }

                            // Base64 garante que o conteúdo (que pode conter |, [[ ]],
                            // quebras de linha, etc.) nunca colida com o delimitador [[TOOL:…]].
                            let inputEnc = Data(tu.json.utf8).base64EncodedString()
                            let outputEnc = Data(String(result.output.prefix(2000)).utf8).base64EncodedString()
                            continuation.yield("\n[[TOOL:\(tu.name)|\(inputEnc)|\(outputEnc)|\(result.success ? "1" : "0")]]\n")

                            resultBlocks.append([
                                "type": "tool_result",
                                "tool_use_id": tu.id,
                                "content": result.output,
                                "is_error": !result.success
                            ])
                        }
                        messages.append(["role": "user", "content": resultBlocks])
                        // Continua o loop: o modelo recebe os resultados e prossegue.
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Orçamento de contexto (janela do modelo)

    nonisolated static func charCount(_ any: Any) -> Int {
        if let s = any as? String { return s.count }
        if let arr = any as? [Any] { return arr.reduce(0) { $0 + charCount($1) } }
        if let dict = any as? [String: Any] { return dict.values.reduce(0) { $0 + charCount($1) } }
        return 0
    }
    nonisolated static func estTokens(_ any: Any) -> Int { charCount(any) / 4 }

    /// Mantém o pacote dentro do orçamento durante o loop de ferramentas truncando o
    /// CONTEÚDO dos `tool_result` mais antigos (que dominam o tamanho), preservando o
    /// pareamento tool_use/tool_result e as últimas `keepRecent` mensagens intactas.
    nonisolated static func trimMessagesToBudget(_ messages: inout [[String: Any]], budgetTokens: Int, keepRecent: Int = 6) {
        func total() -> Int { messages.reduce(0) { $0 + estTokens($1["content"] ?? "") } }
        guard total() > budgetTokens else { return }
        let cutoff = max(0, messages.count - keepRecent)
        for i in 0..<cutoff {
            if total() <= budgetTokens { break }
            guard let content = messages[i]["content"] as? [[String: Any]] else { continue }
            var newContent = content
            var changed = false
            for j in newContent.indices {
                if (newContent[j]["type"] as? String) == "tool_result",
                   let c = newContent[j]["content"] as? String, c.count > 240 {
                    newContent[j]["content"] = String(c.prefix(240))
                        + "\n…[saída de ferramenta antiga truncada para caber no contexto]"
                    changed = true
                }
            }
            if changed { messages[i]["content"] = newContent }
        }
    }

    // MARK: - Tool Definitions

    /// Gera as ferramentas no formato da API da Anthropic (`input_schema`) a partir
    /// da MESMA fonte única usada pelos demais providers: `AgentToolExecutor.availableTools`.
    /// Assim, qualquer ferramenta nova (incl. github_*) fica disponível em todos os providers.
    @MainActor
    static func buildToolDefinitions() -> [[String: Any]] {
        AgentToolExecutor.shared.availableTools.map { tool in
            var properties: [String: Any] = [:]
            var required: [String] = []
            for p in tool.parameters {
                properties[p.name] = ["type": p.type, "description": p.description]
                if p.required { required.append(p.name) }
            }
            var schema: [String: Any] = ["type": "object", "properties": properties]
            if !required.isEmpty { schema["required"] = required }
            return [
                "name": tool.name,
                "description": tool.description,
                "input_schema": schema
            ]
        }
    }

    // MARK: - Sanitização de mensagens (regras estritas da Anthropic)

    /// Converte uma lista de mensagens (montada "à moda OpenAI", tolerante) numa sequência
    /// VÁLIDA para a Anthropic. Regras aplicadas:
    /// - papel `system` nunca entra no array → o texto é devolvido em `systemExtra` para
    ///   ser dobrado no system prompt (onde o Claude espera);
    /// - conteúdo vazio é descartado (Claude rejeita mensagens vazias);
    /// - mensagens consecutivas do mesmo papel são fundidas (Claude exige ALTERNÂNCIA);
    /// - a sequência tem de começar com `user` (assistants iniciais órfãos são removidos).
    static func sanitizeForAnthropic(
        _ raw: [(role: String, content: String)]
    ) -> (systemExtra: String, messages: [[String: Any]]) {
        var systemExtra = ""
        var cleaned: [(role: String, content: String)] = []
        for m in raw {
            let role = m.role.lowercased()
            let content = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { continue }
            if role == "system" {
                systemExtra += (systemExtra.isEmpty ? "" : "\n\n") + content
                continue
            }
            let norm = (role == "assistant") ? "assistant" : "user"
            if var last = cleaned.last, last.role == norm {
                last.content += "\n\n" + content
                cleaned[cleaned.count - 1] = last
            } else {
                cleaned.append((role: norm, content: content))
            }
        }
        while let first = cleaned.first, first.role == "assistant" {
            cleaned.removeFirst()
        }
        let messages = cleaned.map { ["role": $0.role, "content": $0.content] as [String: Any] }
        return (systemExtra, messages)
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
    let index: Int?
    let delta: AnthropicStreamDelta?
    let contentBlock: AnthropicContentBlock?
    let error: AnthropicStreamError?

    enum CodingKeys: String, CodingKey {
        case type, index, delta, error
        case contentBlock = "content_block"
    }
}

struct AnthropicStreamError: Decodable {
    let type: String?
    let message: String?
}

struct AnthropicStreamDelta: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
    let signature: String?
    let stopReason: String?
    let partialJson: String?

    enum CodingKeys: String, CodingKey {
        case type, text, thinking, signature
        case stopReason = "stop_reason"
        case partialJson = "partial_json"
    }
}

struct AnthropicContentBlock: Decodable {
    let type: String?
    let id: String?
    let name: String?
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
