//
//  OpenAIProvider.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation

/// Effort level for extended reasoning (o1, o3, o4-mini series)
enum ReasoningEffort: String, CaseIterable {
    case low    = "low"
    case medium = "medium"
    case high   = "high"

    var label: String {
        switch self {
        case .low:    return "Rápido"
        case .medium: return "Balanceado"
        case .high:   return "Profundo"
        }
    }
}

// MARK: - Tool Call resultado do streaming

struct ToolCallAccumulator {
    var id: String = ""
    var name: String = ""
    var arguments: String = ""
}

final class OpenAIProvider: AIProvider {
    let name = "OpenAI"
    var baseURL: URL
    var apiKey: String
    var defaultModel: String = "gpt-4o"
    var temperature: Double = 0.7
    var maxTokens: Int = 4096
    var extraHeaders: [String: String] = [:]
    var reasoningEffort: ReasoningEffort? = nil

    init(apiKey: String, baseURL: URL? = nil, extraHeaders: [String: String] = [:]) {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? URL(string: "https://api.openai.com/v1")!
        self.extraHeaders = extraHeaders
    }

    // MARK: - Validate

    func validateAPIKey() async throws -> Bool {
        let payload: [String: Any] = [
            "model": defaultModel,
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1,
            "stream": false
        ]
        var request = buildRequest(endpoint: "/chat/completions", method: "POST", body: payload)
        request.timeoutInterval = 15
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200 || http.statusCode == 403
    }

    // MARK: - Send (non-streaming)

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

    // MARK: - Stream com function calling + agentic loop

    func streamMessage(
    content: String,
    conversationHistory: [MessageSnapshot],
    systemPrompt: String
) -> AsyncThrowingStream<String, Error> {
    let model       = self.defaultModel
    let temperature = self.temperature
    let maxTokens   = self.maxTokens
    let effort      = self.reasoningEffort

    return AsyncThrowingStream { continuation in
        Task {
            do {
                var messages: [[String: Any]] = []
                if !systemPrompt.isEmpty {
                    messages.append(["role": "system", "content": systemPrompt])
                }
                for msg in conversationHistory {
                    messages.append(["role": msg.role, "content": msg.content])
                }
                messages.append(["role": "user", "content": content])

                let tools = self.buildToolDefinitions()
                // Detecta se o modelo suporta function calling antes de enviar
                var modelSupportsTools = self.modelSupportsTools(model)

                // Limite que se REINICIA a cada progresso (ferramenta executada, ou texto/
                // raciocínio entregue): tarefas longas seguem até a resposta final, sem parar
                // no meio. Só interrompe após várias rodadas SEGUIDAS sem progresso (proteção
                // contra loop), com uma trava absoluta de segurança.
                var idleRounds = 0
                let maxIdleRounds = 8
                var totalRounds = 0
                let hardCap = 200
                var consecutiveToolFailures = 0
                let maxConsecutiveFailures = 5
                // Acumula texto entre iterações para auto-continuação silenciosa
                var accumulatedResponseText = ""

                // Orçamento do pacote para CABER na janela do modelo durante o loop. No formato
                // OpenAI o system já está em `messages`, então a estimativa cobre tudo. O histórico
                // é aparado antes de cada chamada (saídas de ferramenta antigas truncadas).
                let ctxWindow = LLMRouter.maxContextWindow(for: model)
                let win = ctxWindow > 4096 ? ctxWindow : 128_000
                let respReserve = maxTokens > 0 ? maxTokens : 8_192
                let loopBudget = max(8_000, win - respReserve - max(4_000, win / 20))
                var contextRetries = 0
                let maxContextRetries = 4
                // Alguns modelos (ex.: Claude via gateways OpenAI-compatible) rejeitam
                // `temperature` ("deprecated/unsupported"). Ao detectar, desligamos e re-tentamos.
                var allowTemperature = true

                while idleRounds < maxIdleRounds && totalRounds < hardCap {
                    totalRounds += 1

                    // Mantém o pacote dentro da janela antes de cada chamada.
                    OpenAIProvider.trimMessagesToBudget(&messages, budgetTokens: loopBudget)

                    var payload: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "stream": true,
                    ]

                    // Só inclui tools se o modelo suportar function calling
                    if modelSupportsTools {
                        payload["tools"] = tools
                        payload["tool_choice"] = "auto"
                    }

                    // max_tokens: usa apenas o parâmetro correto por tipo de modelo
                    if maxTokens > 0 {
                        if self.isReasoningModel(model) {
                            payload["max_completion_tokens"] = maxTokens
                        } else {
                            payload["max_tokens"] = maxTokens
                        }
                    }

                    if let effort, self.isReasoningModel(model) {
                        payload["reasoning_effort"] = effort.rawValue
                    } else if !self.isReasoningModel(model), allowTemperature {
                        payload["temperature"] = temperature
                    }

                    var request = self.buildRequest(
                        endpoint: "/chat/completions", method: "POST", body: payload)
                    request.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 4000 { break }
                        }
                        let bodyStr = body
                        // Se o erro menciona tools/functions, desabilita e tenta novamente
                        let toolRelatedError = bodyStr.lowercased().contains("tool") ||
                            bodyStr.lowercased().contains("function") ||
                            bodyStr.lowercased().contains("not supported")
                        if modelSupportsTools && toolRelatedError {
                            modelSupportsTools = false
                            totalRounds -= 1 // não conta essa iteração
                            continue
                        }
                        let lowerBody = bodyStr.lowercased()
                        // `temperature` rejeitada por este modelo → desliga e re-tenta sem ela.
                        if allowTemperature && lowerBody.contains("temperature")
                            && (lowerBody.contains("deprecat") || lowerBody.contains("unsupported")
                                || lowerBody.contains("not support") || lowerBody.contains("400")) {
                            allowTemperature = false
                            totalRounds -= 1
                            continue
                        }
                        // Limite de contexto estourado → comprime mais forte e re-tenta.
                        let ctxErr = (http.statusCode == 400 || http.statusCode == 413)
                            && (lowerBody.contains("context") || lowerBody.contains("too long")
                                || lowerBody.contains("maximum") || lowerBody.contains("token"))
                        if ctxErr && contextRetries < maxContextRetries {
                            contextRetries += 1
                            let tighter = max(4_000, loopBudget / (1 + contextRetries))
                            OpenAIProvider.trimMessagesToBudget(&messages, budgetTokens: tighter, keepRecent: 4)
                            totalRounds -= 1
                            continue
                        }
                        throw AIProviderError.unknown("HTTP \(http.statusCode): \(bodyStr)")
                    }

                    var textBuffer = ""
                    var producedReasoning = false
                    var toolCalls: [Int: ToolCallAccumulator] = [:]
                    var finishReason = ""
                    var inReasoning = false

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]" else { break }
                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let choice = choices.first else { continue }

                        if let fr = choice["finish_reason"] as? String, !fr.isEmpty {
                            finishReason = fr
                        }

                        guard let delta = choice["delta"] as? [String: Any] else { continue }

                        // Raciocínio (GLM/DeepSeek/o-series via compat): delta.reasoning_content / reasoning.
                        // Envelopa em <think>…</think> para o painel de raciocínio renderizar.
                        if let reasoning = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String),
                           !reasoning.isEmpty {
                            if !inReasoning { inReasoning = true; continuation.yield("<think>") }
                            producedReasoning = true
                            continuation.yield(reasoning)
                        }

                        if let text = delta["content"] as? String, !text.isEmpty {
                            if inReasoning { inReasoning = false; continuation.yield("</think>") }
                            textBuffer += text
                            continuation.yield(text)
                        }

                        if let deltaToolCalls = delta["tool_calls"] as? [[String: Any]] {
                            for tc in deltaToolCalls {
                                let idx = tc["index"] as? Int ?? 0
                                var acc = toolCalls[idx] ?? ToolCallAccumulator()
                                if let id = tc["id"] as? String { acc.id = id }
                                if let fn = tc["function"] as? [String: Any] {
                                    if let nm = fn["name"] as? String { acc.name = nm }
                                    if let args = fn["arguments"] as? String { acc.arguments += args }
                                }
                                toolCalls[idx] = acc
                            }
                        }
                    }

                    // Fecha o bloco de raciocínio se ainda estiver aberto.
                    if inReasoning { continuation.yield("</think>"); inReasoning = false }

                    // Progresso desta rodada reinicia o limite (ver topo do loop):
                    // ferramenta chamada, ou texto/raciocínio entregue.
                    if !toolCalls.isEmpty
                        || !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || producedReasoning {
                        idleRounds = 0
                    } else {
                        idleRounds += 1
                    }

                    // Auto-continuação silenciosa: quando o modelo atingiu max_tokens
                    if finishReason == "length" {
                        accumulatedResponseText += textBuffer
                        messages.append(["role": "assistant", "content": accumulatedResponseText])
                        messages.append(["role": "user", "content": "Continue exatamente de onde parou."])
                        continue
                    }

                    // Se o modelo não suporta tools ou não retornou nenhuma, encerra
                    if !modelSupportsTools || toolCalls.isEmpty || finishReason == "stop" {
                        break
                    }

                    accumulatedResponseText += textBuffer
                    var assistantMessage: [String: Any] = ["role": "assistant"]
                    if !textBuffer.isEmpty { assistantMessage["content"] = textBuffer }
                    var toolCallsJSON: [[String: Any]] = []
                    for (_, acc) in toolCalls.sorted(by: { $0.key < $1.key }) {
                        toolCallsJSON.append([
                            "id": acc.id,
                            "type": "function",
                            "function": ["name": acc.name, "arguments": acc.arguments]
                        ])
                    }
                    assistantMessage["tool_calls"] = toolCallsJSON
                    messages.append(assistantMessage)

                    var allToolsFailed = true
                    for (_, acc) in toolCalls.sorted(by: { $0.key < $1.key }) {
                        let toolName = acc.name
                        let argsString = acc.arguments

                        var input: [String: String] = [:]
                        if let argsData = argsString.data(using: .utf8),
                           let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                            for (k, v) in argsDict {
                                input[k] = "\(v)"
                            }
                        }

                        // Sinaliza a atividade em tempo real (interceptado pelo manager).
                        continuation.yield("[[STATUS:\(Self.statusLabel(for: toolName))]]")

                        // executeStreaming transmite a saída do shell ao vivo (linha a linha)
                        // para a UI acompanhar o processo enquanto roda.
                        let result = await AgentToolExecutor.shared.executeStreaming(
                            toolName: toolName, input: input
                        ) { line in
                            continuation.yield("[[STATUS:\(line)]]")
                        }

                        // Emite bloco estruturado [[TOOL:...]] — renderizado como ToolCallBlockView.
                        // Base64 garante que o conteúdo (que pode conter |, [[ ]], quebras de
                        // linha, etc.) nunca colida com o delimitador [[TOOL:…]].
                        let inputEnc = Data(argsString.utf8).base64EncodedString()
                        let outputEnc = Data(String(result.output.prefix(2000)).utf8).base64EncodedString()
                        let successFlag = result.success ? "1" : "0"

                        continuation.yield("\n[[TOOL:\(toolName)|\(inputEnc)|\(outputEnc)|\(successFlag)]]\n")

                        if result.success {
                            allToolsFailed = false
                        }

                        messages.append([
                            "role": "tool",
                            "tool_call_id": acc.id,
                            "content": result.output
                        ])
                    }

                    if allToolsFailed {
                        consecutiveToolFailures += 1
                        if consecutiveToolFailures >= maxConsecutiveFailures {
                            continuation.yield("\n\n*Não foi possível executar as ferramentas necessárias. Respondendo com base no conhecimento disponível.*\n\n")
                            break
                        }
                    } else {
                        consecutiveToolFailures = 0
                    }
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

    // MARK: - Fetch models

    func fetchAvailableModels() async throws -> [String] {
        var request = buildRequest(endpoint: "/models", method: "GET", body: nil)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIProviderError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        let excluded = ["whisper", "tts", "dall-e", "davinci", "babbage", "ada", "curie", "embed", "rerank"]
        return decoded.data
            .map { $0.id }
            .filter { id in
                let lower = id.lowercased()
                return !excluded.contains(where: { lower.contains($0) })
            }
            .sorted()
    }

    // MARK: - Tool Definitions

    /// Gera as ferramentas no formato "tools" da API da OpenAI a partir da MESMA
    /// fonte única usada pelo Anthropic: `AgentToolExecutor.availableTools`
    /// (inclui as ferramentas GitHub e as descobertas via MCP). Mantém paridade
    /// total entre os providers — toda ferramenta nova aparece automaticamente.
    private func buildToolDefinitions() -> [[String: Any]] {
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
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": schema
                ]
            ]
        }
    }

    // MARK: - Helpers

    /// Rótulo de atividade exibido ao usuário durante a execução de uma ferramenta.
    // MARK: - Orçamento de contexto (janela do modelo)

    nonisolated static func charCount(_ any: Any) -> Int {
        if let s = any as? String { return s.count }
        if let arr = any as? [Any] { return arr.reduce(0) { $0 + charCount($1) } }
        if let dict = any as? [String: Any] { return dict.values.reduce(0) { $0 + charCount($1) } }
        return 0
    }
    nonisolated static func estTokens(_ any: Any) -> Int { charCount(any) / 4 }

    /// Mantém o pacote dentro do orçamento durante o loop de ferramentas truncando o
    /// CONTEÚDO das mensagens `tool` mais antigas (que dominam o tamanho), preservando a
    /// ordem assistant→tool e as últimas `keepRecent` mensagens intactas.
    nonisolated static func trimMessagesToBudget(_ messages: inout [[String: Any]], budgetTokens: Int, keepRecent: Int = 6) {
        func total() -> Int { messages.reduce(0) { $0 + estTokens($1["content"] ?? "") } }
        guard total() > budgetTokens else { return }
        let cutoff = max(0, messages.count - keepRecent)
        for i in 0..<cutoff {
            if total() <= budgetTokens { break }
            if (messages[i]["role"] as? String) == "tool",
               let c = messages[i]["content"] as? String, c.count > 240 {
                messages[i]["content"] = String(c.prefix(240))
                    + "\n…[saída de ferramenta antiga truncada para caber no contexto]"
            }
        }
    }

    static func statusLabel(for toolName: String) -> String {
        switch toolName {
        case "web_search":      return "Pesquisando na web…"
        case "web_fetch":       return "Lendo página…"
        case "run_shell":       return "Executando comando…"
        case "install_tool":    return "Instalando ferramenta…"
        case "write_file":      return String(localized: "Writing file…")
        case "read_file":       return String(localized: "Reading file…")
        case "list_directory":  return "Listando arquivos…"
        case "create_directory":return "Criando diretório…"
        case "github_list_repos":   return "Listando repositórios…"
        case "github_get_repo":     return "Lendo repositório…"
        case "github_list_issues":  return "Listando issues…"
        case "github_list_prs":     return "Listando pull requests…"
        case "github_create_issue": return "Criando issue…"
        case "github_create_repo":  return "Criando repositório…"
        default:                return "Trabalhando…"
        }
    }

    private func isReasoningModel(_ model: String) -> Bool {
        let bare = LLMRouter.bareModelName(model).lowercased()
        return bare.hasPrefix("o1") || bare.hasPrefix("o3") || bare.hasPrefix("o4")
    }

    /// Detecta se o modelo suporta OpenAI-format function calling.
    /// A maioria dos modelos modernos suporta (incluindo via LiteLLM translation),
    /// mas alguns modelos mais antigos ou especializados não suportam.
    /// Em caso de dúvida, tenta com tools — se der erro 400, faz retry sem.
    func modelSupportsTools(_ model: String) -> Bool {
        let bare = LLMRouter.bareModelName(model).lowercased()
        // Modelos conhecidos por NÃO suportar tools.
        // (GLM-4.5/4.6 suportam function calling — removidos daqui; se algum modelo
        //  GLM antigo não suportar, o retry-sem-tools cobre automaticamente.)
        let noToolsPatterns = [
            "imagen",          // Modelos de imagem — não são chat
            "embedding",       // Modelos de embedding
            "rerank",          // Modelos de reranking
            "whisper",         // Modelos de áudio
            "tts",             // Text-to-speech
            "dall-e",          // Geração de imagem
            "stable-diffusion",
            "codestral",       // Mistral codestral não suporta consistentemente
        ]
        if noToolsPatterns.contains(where: { bare.contains($0) }) { return false }
        // Modelos com suporte confirmado
        let toolsPatterns = [
            "gpt-4", "gpt-3.5", "gpt-5",          // OpenAI
            "o1", "o3", "o4",                       // OpenAI reasoning
            "claude",                                // Anthropic (via LiteLLM)
            "gemini",                                // Google (via LiteLLM)
            "llama-3.1", "llama-3.2", "llama-3.3", // Llama 3.1+ suporta
            "mistral-large", "mistral-medium",       // Mistral (algumas versões)
            "mixtral",                               // Mixtral suporta
            "deepseek",                              // DeepSeek
            "nova",                                  // Amazon Nova
            "qwen",                                  // Qwen2+
            "glm-4.5", "glm-4.6", "glm-4-plus",     // GLM modernos
        ]
        if toolsPatterns.contains(where: { bare.contains($0) }) { return true }
        // Para modelos desconhecidos: tenta com tools (retry sem se der erro)
        return true
    }

    private func buildRequest(endpoint: String, method: String, body: [String: Any]?) -> URLRequest {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        let ep = endpoint.hasPrefix("/") ? endpoint : "/\(endpoint)"
        let url = URL(string: base + ep) ?? baseURL
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("https://lume.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Lume", forHTTPHeaderField: "X-Title")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }
}

// MARK: - Streaming types

struct OpenAIStreamChunk: Decodable {
    let choices: [OpenAIStreamChoice]
}
struct OpenAIStreamChoice: Decodable {
    let delta: OpenAIStreamDelta
}
struct OpenAIStreamDelta: Decodable {
    let content: String?
}

struct OpenAIResponse: Decodable {
    let choices: [OpenAIChoice]
}
struct OpenAIChoice: Decodable {
    let message: OpenAIMessage?
}
struct OpenAIMessage: Decodable {
    let content: String
}
