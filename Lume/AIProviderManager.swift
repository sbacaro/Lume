//
//  AIProviderManager.swift
//  Lume
//

import Foundation
import Observation

@Observable
final class AIProviderManager {
    var activeProvider: AIProvider?
    var isLoading = false
    var error: AIProviderError?
    var streamingMessageID: String?
    var latestArtifactMessageID: String?
    var lastRoutingDecision: RoutingDecision?
    var lastCacheHit = false
    var streamingTokenCount: Int = 0
    var streamingElapsed: TimeInterval = 0

    var lastCompressionRatio: Double = 0
    var totalTokensSaved: Int = 0
    var cacheHitRate: Double = 0
    private var totalRequests = 0
    private var cacheHits = 0

    private let keychainManager = KeychainManager.shared
    private let contextManager = ContextManager()
    private var streamingTask: Task<String, Error>?
    private var streamingStartTime: Date?
    private var activeConfig: AIProviderConfig?

    // MARK: - Setup

    func setActiveProvider(configID: String, config: AIProviderConfig, context: Any? = nil) async throws {
        self.activeConfig = config
        let apiKey = await keychainManager.retrieveAPIKey(for: configID)
        guard !apiKey.isEmpty else { return }

        let provider: AIProvider
        if let gateway = AIGatewayManager.shared.currentGateway {
            provider = OpenAIProvider(
                apiKey: gateway.apiKey.isEmpty ? apiKey : gateway.apiKey,
                baseURL: gateway.baseURL,
                extraHeaders: gateway.resolvedHeaders
            )
        } else {
            switch config.providerType {
            case "openai":
                provider = OpenAIProvider(apiKey: apiKey)
            case "openai_custom":
                guard let url = URL(string: config.baseURL) else {
                    throw AIProviderError.unknown("URL base inválida: \(config.baseURL)")
                }
                provider = OpenAIProvider(apiKey: apiKey, baseURL: url, extraHeaders: [
                    "HTTP-Referer": "https://lume.app",
                    "X-Title": "Lume"
                ])
            case "anthropic":
                provider = AnthropicProvider(apiKey: apiKey)
            case "litellm", "portkey", "vllm", "tgi", "ollama":
                guard let url = URL(string: config.baseURL) else {
                    throw AIProviderError.unknown("URL inválida para \(config.providerType)")
                }
                provider = OpenAIProvider(apiKey: apiKey, baseURL: url)
            default:
                throw AIProviderError.unknown("Provider desconhecido: \(config.providerType)")
            }
        }

        provider.temperature = config.temperature
        provider.maxTokens = config.maxTokens
        provider.defaultModel = config.defaultModel
        self.activeProvider = provider
    }

    func activateProvider(config: AIProviderConfig, apiKey: String) async throws {
        self.activeConfig = config
        guard !apiKey.isEmpty else { return }

        let provider: AIProvider
        if let gateway = AIGatewayManager.shared.currentGateway {
            provider = OpenAIProvider(
                apiKey: gateway.apiKey.isEmpty ? apiKey : gateway.apiKey,
                baseURL: gateway.baseURL,
                extraHeaders: gateway.resolvedHeaders
            )
        } else {
            switch config.providerType {
            case "openai":
                provider = OpenAIProvider(apiKey: apiKey)
            case "openai_custom":
                guard let url = URL(string: config.baseURL) else {
                    throw AIProviderError.unknown("URL base inválida: \(config.baseURL)")
                }
                provider = OpenAIProvider(apiKey: apiKey, baseURL: url, extraHeaders: [
                    "HTTP-Referer": "https://lume.app",
                    "X-Title": "Lume"
                ])
            case "anthropic":
                provider = AnthropicProvider(apiKey: apiKey)
            case "litellm", "portkey", "vllm", "tgi", "ollama":
                guard let url = URL(string: config.baseURL) else {
                    throw AIProviderError.unknown("URL inválida para \(config.providerType)")
                }
                provider = OpenAIProvider(apiKey: apiKey, baseURL: url)
            default:
                throw AIProviderError.unknown("Provider desconhecido: \(config.providerType)")
            }
        }

        provider.temperature = config.temperature
        provider.maxTokens = config.maxTokens
        provider.defaultModel = config.defaultModel
        self.activeProvider = provider
    }

    func changeModel(_ modelName: String) {
        guard !modelName.isEmpty else { return }
        activeProvider?.defaultModel = modelName
        activeConfig?.defaultModel = modelName
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        streamingMessageID = nil
        isLoading = false
        streamingTokenCount = 0
        streamingElapsed = 0
    }

    // MARK: - Stream Message

    @discardableResult
    func streamMessage(content: String, conversation: Conversation) async throws -> String {
        guard let provider = activeProvider else {
            throw AIProviderError.unknown("Nenhum provider ativo. Configure em Configurações (⌘,).")
        }

        isLoading = true
        streamingTokenCount = 0
        streamingStartTime = Date()
        totalRequests += 1
        defer {
            isLoading = false
            streamingTokenCount = 0
            streamingElapsed = 0
        }

        // ── ROTEAMENTO ────────────────────────────────────────────
        let originalModel = provider.defaultModel
        let isCustomProvider = isCustom(conversation.providerType)

        if !isCustomProvider {
            let routing = LLMRouter.route(
                prompt: content,
                history: conversation.messages,
                provider: conversation.providerType,
                preferredModel: conversation.modelName,
                forceMode: .preferred
            )
            lastRoutingDecision = routing
            provider.defaultModel = routing.model
        } else {
            provider.defaultModel = conversation.modelName.isEmpty ? originalModel : conversation.modelName
        }

        defer { provider.defaultModel = originalModel }

        // ── CACHE ────────────────────────────────────────────────
        let cacheKey = buildCacheKey(content: content, conversation: conversation)
        if let cached = await SemanticCache.shared.get(prompt: cacheKey, model: provider.defaultModel) {
            lastCacheHit = true
            cacheHits += 1
            cacheHitRate = Double(cacheHits) / Double(totalRequests)
            let assistantMsg = Message(role: .assistant, content: "")
            conversation.messages.append(assistantMsg)
            streamingMessageID = assistantMsg.id
            await streamCachedResponse(cached, into: assistantMsg)
            streamingMessageID = nil
            detectAndAttachArtifact(to: assistantMsg, response: cached)
            autoRenameConversation(conversation, from: content)
            return cached
        }
        lastCacheHit = false
        cacheHitRate = Double(cacheHits) / Double(totalRequests)

        // ── SYSTEM PROMPT ────────────────────────────────────────
        var baseSystemPrompt = isCustomProvider
            ? contextManager.optimizeSystemPromptForCustomProvider(conversation.systemPrompt)
            : contextManager.optimizeSystemPrompt(conversation.systemPrompt)

        // ── CONTEXTO DO PROJETO (Cowork) ──────────────────────────
        if let project = conversation.project {
            var projectContext = "\n\n## Projeto Atual\n"
                + "Você está trabalhando no projeto \"\(project.name)\".\n"
                + "Todas as respostas devem ser contextualizadas para este projeto.\n"
                + "Não pergunte sobre qual projeto trabalhar — você já está nele."

            if let resolvedURL = resolveBookmark(for: project) {
                let isFirst = conversation.messages.filter { $0.role == .user }.count <= 1
                let fileContext = await buildProjectFileContext(
                    projectURL: resolvedURL,
                    projectName: project.name,
                    isFirstMessage: isFirst
                )
                if !fileContext.isEmpty { projectContext += "\n\n" + fileContext }
            } else if let localURL = project.localURL {
                let isFirst = conversation.messages.filter { $0.role == .user }.count <= 1
                let fileContext = await buildProjectFileContext(
                    projectURL: localURL,
                    projectName: project.name,
                    isFirstMessage: isFirst
                )
                if !fileContext.isEmpty { projectContext += "\n\n" + fileContext }
            }

            baseSystemPrompt += projectContext
        }

        // ── CONTEXTO DE WORKSPACE DE CODE ────────────────────────
        // Injeta arquivos do workspace Code quando a conversa não pertence a um projeto
        if conversation.project == nil,
           let codePath = UserDefaults.standard.string(forKey: "code_workspace_path") {
            let codeURL: URL
            var codeAccessing = false
            if let bookmarkData = UserDefaults.standard.data(forKey: "code_workspace_bookmark") {
                var isStale = false
                if let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    codeURL = resolved
                    codeAccessing = codeURL.startAccessingSecurityScopedResource()
                } else {
                    codeURL = URL(fileURLWithPath: codePath)
                }
            } else {
                codeURL = URL(fileURLWithPath: codePath)
                codeAccessing = codeURL.startAccessingSecurityScopedResource()
            }
            let isFirst = conversation.messages.filter { $0.role == .user }.count <= 1
            let fileContext = await buildProjectFileContext(
                projectURL: codeURL,
                projectName: codeURL.lastPathComponent,
                isFirstMessage: isFirst
            )
            if codeAccessing { codeURL.stopAccessingSecurityScopedResource() }
            if !fileContext.isEmpty {
                baseSystemPrompt += "\n\n## Workspace de Código"
                    + "\nVocê está trabalhando no workspace: \(codePath)"
                    + "\nOpere apenas dentro desta pasta.\n\n"
                    + fileContext
            }
        }

        let optimizedSystemPrompt = baseSystemPrompt

        // ── BUSCA WEB (apenas para providers não-custom) ─────────
        var finalContent = content
        if !isCustomProvider {
            if let webContext = await buildWebSearchContext(for: content) {
                finalContent = content + "\n\n" + webContext
            }
        }
        if let ragContext = await RAGEngine.shared.buildContext(for: content) {
            finalContent = ragContext + "\n\nPergunta do usuário: " + finalContent
        }

        // ── COMPRESSÃO DE CONTEXTO ───────────────────────────────
        let rawMessages = conversation.messages.filter { $0.role != .assistant || !$0.content.isEmpty }
        let compressionResult = ContextCompressor.shared.compress(
            messages: rawMessages,
            query: content,
            targetTokens: isCustomProvider ? 100_000 : 10_000,
            systemPrompt: optimizedSystemPrompt
        )
        lastCompressionRatio = compressionResult.compressionRatio
        totalTokensSaved += compressionResult.originalTokens - compressionResult.compressedTokens
        var contextMessages = compressionResult.messages

        // ── SUMARIZAÇÃO SE NECESSÁRIO ────────────────────────────
        if !isCustomProvider &&
           contextManager.needsSummarization(messages: contextMessages, systemPrompt: optimizedSystemPrompt) {
            let oldMessages = Array(contextMessages.dropLast(contextManager.config.recentMessageCount))
            if !oldMessages.isEmpty,
               let summary = try? await provider.sendMessage(
                   content: contextManager.buildSummarizationPrompt(for: oldMessages),
                   conversationHistory: [],
                   systemPrompt: "Você é um assistente de sumarização. Seja breve e factual."
               ) {
                let summaryMsg = Message(role: .system, content: "[Resumo anterior]\n" + summary)
                let recent = Array(contextMessages.suffix(contextManager.config.recentMessageCount))
                contextMessages = [summaryMsg] + recent
            }
        }

        // ── STREAMING ────────────────────────────────────────────
        let assistantMsg = Message(role: .assistant, content: "")
        conversation.messages.append(assistantMsg)
        streamingMessageID = assistantMsg.id

        var fullResponse = ""

        let task = Task<String, Error> {
            var accumulated = ""
            var tokenCount = 0
            for try await chunk in provider.streamMessage(
                content: finalContent,
                conversationHistory: contextMessages.filter { $0.role != .assistant || !$0.content.isEmpty },
                systemPrompt: optimizedSystemPrompt
            ) {
                try Task.checkCancellation()
                accumulated += chunk
                tokenCount += max(1, chunk.count / 4)
                await MainActor.run {
                    assistantMsg.content = accumulated
                    self.streamingTokenCount = tokenCount
                    if let start = self.streamingStartTime {
                        self.streamingElapsed = Date().timeIntervalSince(start)
                    }
                }
            }
            return accumulated
        }
        streamingTask = task

        do {
            fullResponse = try await task.value
        } catch is CancellationError {
            fullResponse = assistantMsg.content
            if fullResponse.isEmpty { conversation.messages.removeAll { $0.id == assistantMsg.id } }
            streamingMessageID = nil
            streamingTask = nil
            return fullResponse
        } catch {
            if fullResponse.isEmpty { conversation.messages.removeAll { $0.id == assistantMsg.id } }
            streamingMessageID = nil
            streamingTask = nil
            let aiError = error as? AIProviderError ?? AIProviderError.networkError(error)
            self.error = aiError
            throw aiError
        }

        streamingMessageID = nil
        streamingTask = nil

        await SemanticCache.shared.set(prompt: cacheKey, model: provider.defaultModel, response: fullResponse)
        detectAndAttachArtifact(to: assistantMsg, response: fullResponse)
        autoRenameConversation(conversation, from: content)

        return fullResponse
    }

    // MARK: - Security-scoped Bookmark

    static func saveBookmark(for url: URL, projectID: String) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: "bookmark_\(projectID)")
    }

    private func resolveBookmark(for project: Project) -> URL? {
        let key = "bookmark_\(project.id)"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return url
    }

    // MARK: - Project File Context

    private func buildProjectFileContext(
        projectURL: URL,
        projectName: String,
        isFirstMessage: Bool
    ) async -> String {
        let fm = FileManager.default

        let accessing = projectURL.startAccessingSecurityScopedResource()
        defer { if accessing { projectURL.stopAccessingSecurityScopedResource() } }

        guard let items = try? fm.contentsOfDirectory(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "Pasta: \(projectURL.path)\n[Não foi possível ler os arquivos — verifique as permissões]"
        }

        let textExtensions: Set<String> = [
            "swift", "py", "js", "ts", "go", "rs", "cpp", "c", "h", "java", "kt",
            "md", "txt", "json", "yaml", "yml", "toml", "sh", "bash",
            "html", "css", "sql", "xml", "rb", "php"
        ]

        let priorityFiles = ["README.md", "Package.swift", "main.swift", "App.swift", "index.js", "main.py"]

        let allFiles = items
            .filter { url in
                guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      vals.isRegularFile == true else { return false }
                let ext = url.pathExtension.lowercased()
                let size = vals.fileSize ?? 0
                return textExtensions.contains(ext) && size < 500_000
            }
            .sorted { a, b in
                let aP = priorityFiles.contains(a.lastPathComponent)
                let bP = priorityFiles.contains(b.lastPathComponent)
                if aP != bP { return aP }
                return a.lastPathComponent < b.lastPathComponent
            }

        if allFiles.isEmpty {
            return "Pasta: \(projectURL.path)\nA pasta existe mas não contém arquivos de código reconhecíveis. Total de itens: \(items.count)"
        }

        var parts: [String] = []
        parts.append("Pasta: \(projectURL.path)\nTotal de arquivos de código: \(allFiles.count)")

        let maxTotalChars = isFirstMessage ? 400_000 : 150_000
        let maxPerFile    = isFirstMessage ? 30_000  : 15_000
        var totalChars = 0
        var filesIncluded = 0

        for url in allFiles {
            guard totalChars < maxTotalChars else {
                parts.append("\n[+\(allFiles.count - filesIncluded) arquivos omitidos — limite de contexto atingido]")
                break
            }

            let content: String
            if let c = try? String(contentsOf: url, encoding: .utf8) {
                content = c
            } else if let c = try? String(contentsOf: url, encoding: .isoLatin1) {
                content = c
            } else {
                continue
            }

            let truncated = content.count > maxPerFile
                ? String(content.prefix(maxPerFile)) + "\n// [... \(content.count - maxPerFile) chars omitidos]"
                : content

            parts.append("\n### \(url.lastPathComponent)\n```\(url.pathExtension)\n\(truncated)\n```")
            totalChars += truncated.count
            filesIncluded += 1
        }

        parts.append("\n[Fim do contexto. \(filesIncluded) de \(allFiles.count) arquivos incluídos.]")
        return parts.joined(separator: "\n")
    }

    // MARK: - Auto Rename

    private func autoRenameConversation(_ conversation: Conversation, from content: String) {
        let defaultTitles = ["Nova Conversa", "Sessão de Código", "Nova conversa"]
        let isFirstMessage = conversation.messages.filter { $0.role == .user }.count <= 1
        guard defaultTitles.contains(conversation.title) || isFirstMessage else { return }
        let words = content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(7)
            .joined(separator: " ")
        let title = String(words.prefix(60))
        if !title.isEmpty { conversation.title = title }
    }

    // MARK: - Helpers

    private func isCustom(_ providerType: String) -> Bool {
        switch providerType {
        case "openai", "anthropic": return false
        default: return true
        }
    }

    private func buildWebSearchContext(for query: String) async -> String? {
        guard needsWebSearch(query: query) else { return nil }
        let searchQuery = extractSearchQuery(from: query)
        let result = await AgentToolExecutor.shared.webSearch(query: searchQuery, maxResults: 5)
        guard result.success, !result.output.isEmpty else { return nil }

        var parts = ["[Resultados da busca para \"\(searchQuery)\"]", result.output]

        if needsDeepFetch(query: query), let urlsString = result.metadata["urls"] {
            let fetchTool = WebFetchTool()
            for urlString in urlsString.components(separatedBy: ",").prefix(2) {
                let trimmed = urlString.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, let url = URL(string: trimmed), isUsefulDomain(url) else { continue }
                if let fetchResult = try? await fetchTool.execute(with: ["url": trimmed, "max_chars": "3000"]),
                   fetchResult.success {
                    let title = fetchResult.metadata["title"] ?? trimmed
                    parts.append("\n[Conteúdo: \(title)]\n\(fetchResult.output)\n[Fim]")
                }
            }
        }

        parts.append("\nCite as fontes (URLs) quando relevante.")
        return parts.joined(separator: "\n\n")
    }

    private func needsWebSearch(query: String) -> Bool {
        let lower = query.lowercased()
        let keywords = ["clima", "tempo", "hoje", "agora", "notícia", "preço", "cotação",
                        "documentação", "docs", "github", "http", "https", "weather",
                        "news", "price", "stock", "pesquise", "busque", "procure"]
        return keywords.contains { lower.contains($0) }
    }

    private func needsDeepFetch(query: String) -> Bool {
        let lower = query.lowercased()
        return ["docs", "documentação", "tutorial", "github", "api", "como usar"]
            .contains { lower.contains($0) }
    }

    private func isUsefulDomain(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let skip = ["facebook.com", "twitter.com", "instagram.com", "youtube.com", "reddit.com"]
        return !skip.contains { host.contains($0) }
    }

    private func extractSearchQuery(from text: String) -> String {
        var q = text
            .replacingOccurrences(of: "pesquise sobre", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "busque sobre", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if q.count > 120 { q = String(q.prefix(120)) }
        return q.isEmpty ? text : q
    }

    // MARK: - Validate

    func validateProvider(config: AIProviderConfig, apiKey: String) async throws -> Bool {
        let provider: AIProvider
        switch config.providerType {
        case "openai":
            provider = OpenAIProvider(apiKey: apiKey)
        case "openai_custom", "litellm", "portkey", "vllm", "tgi", "ollama":
            guard let url = URL(string: config.baseURL) else {
                throw AIProviderError.unknown("URL inválida")
            }
            provider = OpenAIProvider(apiKey: apiKey, baseURL: url)
        case "anthropic":
            provider = AnthropicProvider(apiKey: apiKey)
        default:
            throw AIProviderError.unknown("Provider desconhecido")
        }
        provider.defaultModel = config.defaultModel
        return try await provider.validateAPIKey()
    }

    // MARK: - Private helpers

    private func streamCachedResponse(_ response: String, into message: Message) async {
        let words = response.components(separatedBy: " ")
        var accumulated = ""
        for word in words {
            accumulated += (accumulated.isEmpty ? "" : " ") + word
            let current = accumulated
            await MainActor.run { message.content = current }
            try? await Task.sleep(nanoseconds: 6_000_000)
        }
    }

    private func buildCacheKey(content: String, conversation: Conversation) -> String {
        let ctx = conversation.messages.suffix(2)
            .map { "\($0.role.rawValue):\($0.content.prefix(80))" }
            .joined(separator: "|")
        return "\(ctx)|\(content)"
    }

    private func detectAndAttachArtifact(to message: Message, response: String) {
        if let detected = ArtifactDetector.detect(in: response) {
            let artifact = Artifact(title: detected.title, type: detected.type, content: detected.content)
            message.artifact = artifact
            latestArtifactMessageID = message.id
        }
    }
}
