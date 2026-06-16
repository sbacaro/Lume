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

                var iterationCount = 0
                let maxIterations = 20
                var consecutiveToolFailures = 0
                let maxConsecutiveFailures = 5
                // Acumula texto entre iterações para auto-continuação silenciosa
                var accumulatedResponseText = ""

                while iterationCount < maxIterations {
                    iterationCount += 1

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
                    } else if !self.isReasoningModel(model) {
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
                            iterationCount -= 1 // não conta essa iteração
                            continue
                        }
                        throw AIProviderError.unknown("HTTP \(http.statusCode): \(bodyStr)")
                    }

                    var textBuffer = ""
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

    private func buildToolDefinitions() -> [[String: Any]] {
        return [
            [
                "type": "function",
                "function": [
                    "name": "run_shell",
                    "description": "Executa um comando shell/bash no macOS do usuário. Use para git, npm, python, compilar código, mover arquivos, instalar dependências, etc. Sempre use caminhos absolutos.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "command": [
                                "type": "string",
                                "description": "O comando shell completo a executar"
                            ],
                            "working_directory": [
                                "type": "string",
                                "description": "Diretório de trabalho opcional (caminho absoluto)"
                            ]
                        ],
                        "required": ["command"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "read_file",
                    "description": "Lê o conteúdo de um arquivo no disco do usuário.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "Caminho absoluto do arquivo a ler"
                            ]
                        ],
                        "required": ["path"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "write_file",
                    "description": "Escreve ou sobrescreve um arquivo no disco do usuário.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "Caminho absoluto do arquivo a criar/sobrescrever"
                            ],
                            "content": [
                                "type": "string",
                                "description": "Conteúdo a escrever no arquivo"
                            ]
                        ],
                        "required": ["path", "content"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "list_directory",
                    "description": "Lista arquivos e pastas em um diretório.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "Caminho absoluto do diretório a listar"
                            ]
                        ],
                        "required": ["path"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "create_directory",
                    "description": "Cria um diretório (e subdiretórios) no disco.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "Caminho absoluto do diretório a criar"
                            ]
                        ],
                        "required": ["path"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "web_search",
                    "description": "Busca informações na web via DuckDuckGo ou Google.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Termo de busca"
                            ],
                            "max_results": [
                                "type": "string",
                                "description": "Número máximo de resultados (padrão: 5)"
                            ]
                        ],
                        "required": ["query"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "web_fetch",
                    "description": "Acessa e lê o conteúdo de uma URL específica.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "url": [
                                "type": "string",
                                "description": "URL completa a acessar"
                            ],
                            "max_chars": [
                                "type": "string",
                                "description": "Número máximo de caracteres a retornar (padrão: 8000)"
                            ]
                        ],
                        "required": ["url"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "github_list_repos",
                    "description": "Lista os repositórios do GitHub do usuário conectado. Requer GitHub conectado em Configurações.",
                    "parameters": ["type": "object", "properties": [:] as [String: Any]]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "github_get_repo",
                    "description": "Mostra detalhes de um repositório do GitHub (descrição, linguagem, stars, issues abertas, branch padrão).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "repo": ["type": "string", "description": "Repositório no formato 'owner/repo' (ou só 'repo' para o usuário conectado)"]
                        ],
                        "required": ["repo"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "github_list_issues",
                    "description": "Lista issues de um repositório do GitHub (não inclui pull requests).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "repo": ["type": "string", "description": "Repositório 'owner/repo'"],
                            "state": ["type": "string", "description": "open, closed ou all (padrão: open)"]
                        ],
                        "required": ["repo"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "github_list_prs",
                    "description": "Lista pull requests de um repositório do GitHub.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "repo": ["type": "string", "description": "Repositório 'owner/repo'"],
                            "state": ["type": "string", "description": "open, closed ou all (padrão: open)"]
                        ],
                        "required": ["repo"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "github_create_issue",
                    "description": "Cria uma nova issue em um repositório do GitHub.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "repo": ["type": "string", "description": "Repositório 'owner/repo'"],
                            "title": ["type": "string", "description": "Título da issue"],
                            "body": ["type": "string", "description": "Corpo/descrição (Markdown, opcional)"]
                        ],
                        "required": ["repo", "title"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "github_create_repo",
                    "description": "Cria um novo repositório no GitHub do usuário conectado.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string", "description": "Nome do repositório"],
                            "description": ["type": "string", "description": "Descrição (opcional)"],
                            "private": ["type": "string", "description": "'true' para privado, 'false' para público (padrão: false)"]
                        ],
                        "required": ["name"]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Helpers

    /// Rótulo de atividade exibido ao usuário durante a execução de uma ferramenta.
    static func statusLabel(for toolName: String) -> String {
        switch toolName {
        case "web_search":      return "Pesquisando na web…"
        case "web_fetch":       return "Lendo página…"
        case "run_shell":       return "Executando comando…"
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
