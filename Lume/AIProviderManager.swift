//
//  AIProviderManager.swift
//  Lume
//

import Foundation
import Observation

@Observable
final class AIProviderManager {
    /// Instância única compartilhada por todo o app. Sem isso, a tela de
    /// Configurações usava uma instância PRÓPRIA: ao cadastrar/ativar um provider
    /// lá, o `activeProvider` era setado nessa cópia, mas o chat usava outra
    /// instância (cujo `activeProvider` continuava nil) → "nenhum modelo cadastrado".
    static let shared = AIProviderManager()

    var activeProvider: AIProvider?
    var isLoading = false
    var error: AIProviderError?
    var streamingMessageID: String?
    var latestArtifactMessageID: String?
    var lastRoutingDecision: RoutingDecision?
    var lastCacheHit = false
    var streamingTokenCount: Int = 0
    var streamingElapsed: TimeInterval = 0
    /// Atividade atual durante o streaming (Pensando…, Pesquisando…, Escrevendo código…).
    var streamingActivity: String?

    var lastCompressionRatio: Double = 0
    var totalTokensSaved: Int = 0
    var cacheHitRate: Double = 0
    private var totalRequests = 0
    private var cacheHits = 0

    private let keychainManager = KeychainManager.shared
    private let contextManager = ContextManager()
    private var streamingTask: Task<String, Error>?
    private var streamingStartTime: Date?
    private(set) var activeConfig: AIProviderConfig?

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

    /// Troca o modelo de uma conversa específica sem afetar outras conversas nem o provider global.
    /// O provider global é atualizado apenas transitoriamente no momento do streaming (via defer em streamMessage).
    func changeModel(_ modelName: String, for conversation: Conversation? = nil) {
        guard !modelName.isEmpty else { return }
        // Salva apenas na conversa — o streamMessage já lê conversation.modelName
        conversation?.modelName = modelName
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        streamingMessageID = nil
        isLoading = false
        streamingTokenCount = 0
        streamingElapsed = 0
        streamingActivity = nil
    }

    /// Deriva a atividade atual a partir do conteúdo acumulado (pensamento, código, escrita).
    /// Conta ocorrências sem alocar arrays de substrings (diferente de
    /// `components(separatedBy:)`, que materializa todos os pedaços a cada flush).
    private static func occurrences(of needle: String, in text: String) -> Int {
        var count = 0
        var idx = text.startIndex
        while let r = text.range(of: needle, range: idx..<text.endIndex) {
            count += 1
            idx = r.upperBound
        }
        return count
    }

    static func deriveActivity(from text: String) -> String {
        let opens = occurrences(of: "<think>", in: text)
        let closes = occurrences(of: "</think>", in: text)
        if opens > closes { return "Pensando…" }
        if occurrences(of: "```", in: text) % 2 == 1 { return "Escrevendo código…" }
        return "Escrevendo resposta…"
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
        streamingActivity = "Pensando…"
        totalRequests += 1
        defer {
            isLoading = false
            streamingTokenCount = 0
            streamingElapsed = 0
            streamingActivity = nil
        }

        // ── ROTEAMENTO ────────────────────────────────────────────
        let originalModel = provider.defaultModel
        let isCustomProvider = isCustom(conversation.providerType)
        let lumeConfig = LumeConfig.load()

        // Sempre define o modelo da conversa antes de qualquer override
        let conversationModel = conversation.modelName.isEmpty ? originalModel : conversation.modelName
        provider.defaultModel = conversationModel

        if !isCustomProvider && lumeConfig.enableModelRouting {
            // O modelo escolhido pelo usuário é soberano: nunca o trocamos por baixo
            // dos panos. O roteador roda em modo .preferred apenas para registrar a
            // decisão/custo, mas mantém exatamente o modelo selecionado.
            let routing = LLMRouter.route(
                prompt: content,
                history: conversation.messages,
                provider: conversation.providerType,
                preferredModel: conversationModel,
                forceMode: .preferred
            )
            lastRoutingDecision = routing
            provider.defaultModel = routing.model
        } else {
            // Para custom providers ou roteamento desligado: usa exatamente o modelo da conversa
            lastRoutingDecision = RoutingDecision(
                model: conversationModel,
                providerType: conversation.providerType,
                reason: .preferredModel,
                estimatedCost: LLMRouter.costTier(for: conversationModel),
                confidence: 1.0
            )
        }

        defer { provider.defaultModel = originalModel }

        // ── CACHE ────────────────────────────────────────────────
        let cacheKey = buildCacheKey(content: content, conversation: conversation)
        // Perguntas factuais/atuais (que disparam busca) nunca são servidas do cache —
        // a resposta deve ser sempre fresca, com dados atualizados.
        let skipCache = needsWebSearch(query: content)
        if lumeConfig.enableSemanticCache, !skipCache,
           let cached = await SemanticCache.shared.get(prompt: cacheKey, model: provider.defaultModel) {
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

        // ── PLACEHOLDER DO ASSISTENTE ────────────────────────────
        // Criado já aqui para o avatar + loader + atividade ("Pesquisando…",
        // "Pensando…") aparecerem desde o envio, antes do primeiro token.
        let assistantMsg = Message(role: .assistant, content: "")
        conversation.messages.append(assistantMsg)
        streamingMessageID = assistantMsg.id

        // ── SYSTEM PROMPT ────────────────────────────────────────
        var baseSystemPrompt = isCustomProvider
            ? contextManager.optimizeSystemPromptForCustomProvider(conversation.systemPrompt)
            : contextManager.optimizeSystemPrompt(conversation.systemPrompt)

        // ── MEMÓRIA PERSISTENTE ──────────────────────────────────
        // Fatos do usuário válidos em todas as conversas. No system prompt (estável),
        // pois muda raramente — não prejudica o prompt caching no uso normal.
        if lumeConfig.enableMemory, let memoryBlock = MemoryStore.shared.contextBlock() {
            baseSystemPrompt = memoryBlock + "\n\n" + baseSystemPrompt
        }

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
        // Busca proativa para TODOS os providers (inclusive custom/GLM): o app
        // pesquisa e entrega o material pronto, em vez de depender do modelo pedir.
        var finalContent = content
        if let webContext = await buildWebSearchContext(for: content) {
            finalContent = content + "\n\n" + webContext
        }
        var ragSources: [RAGSource] = []
        if let retrieval = await RAGEngine.shared.buildRetrieval(for: content) {
            finalContent = retrieval.context + "\n\nPergunta do usuário: " + finalContent
            ragSources = retrieval.sources
        }

        // ── CONTEXTO TEMPORAL ────────────────────────────────────
        // Anexa a data/hora atual (fuso do macOS) ao turno do usuário — não ao
        // system prompt, para não invalidar o prompt caching da Anthropic.
        finalContent = Self.currentDateContext() + "\n\n---\n\n" + finalContent

        // ── COMPRESSÃO DE CONTEXTO ───────────────────────────────
        let rawMessages = conversation.messages.filter { $0.role != .assistant || !$0.content.isEmpty }
        // Usa a janela de contexto real do modelo ou o limite configurado pelo usuário
        let modelContextWindow = LLMRouter.maxContextWindow(for: provider.defaultModel)
        let configuredMax = lumeConfig.maxContextTokens
        // Para custom providers usa a janela máxima do modelo; para outros, o mínimo entre
        // o configurado e metade da janela do modelo (reservando espaço para a resposta)
        let targetTokens: Int
        if isCustomProvider {
            targetTokens = max(modelContextWindow > 4096 ? modelContextWindow / 2 : 100_000,
                               configuredMax)
        } else {
            let halfWindow = modelContextWindow > 0 ? modelContextWindow / 2 : 60_000
            targetTokens = min(configuredMax, halfWindow)
        }
        let compressionResult = ContextCompressor.shared.compress(
            messages: rawMessages,
            query: content,
            targetTokens: targetTokens,
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
        assistantMsg.ragSources = ragSources

        var fullResponse = ""

        let task = Task<String, Error> {
            var accumulated = ""
            var tokenCount = 0
            var lastFlush = Date.distantPast
            for try await chunk in provider.streamMessage(
                content: finalContent,
                conversationHistory: contextMessages.filter { $0.role != .assistant || !$0.content.isEmpty },
                systemPrompt: optimizedSystemPrompt
            ) {
                try Task.checkCancellation()
                // Sinal de atividade — não faz parte do conteúdo da mensagem.
                if chunk.hasPrefix("[[STATUS:") && chunk.hasSuffix("]]") {
                    let label = String(chunk.dropFirst(9).dropLast(2))
                    await MainActor.run { self.streamingActivity = label }
                    continue
                }
                accumulated += chunk
                tokenCount += max(1, chunk.count / 4)

                // THROTTLE: atualiza a tela no máximo ~12x/segundo. Sem isso, cada token
                // re-parseia e re-renderiza a mensagem inteira (O(n²) em respostas longas),
                // o que satura a CPU e trava o app. 12x/s é fluido e corta ~40% do trabalho.
                let now = Date()
                guard now.timeIntervalSince(lastFlush) >= 0.08 else { continue }
                lastFlush = now
                let snapshot = accumulated
                let tc = tokenCount
                let activity = Self.deriveActivity(from: snapshot)
                await MainActor.run {
                    assistantMsg.content = snapshot
                    self.streamingTokenCount = tc
                    if self.streamingActivity != activity { self.streamingActivity = activity }
                    if let start = self.streamingStartTime {
                        self.streamingElapsed = Date().timeIntervalSince(start)
                    }
                }
            }
            // Flush final (garante o texto completo) + contagem de tokens.
            let finalText = accumulated
            let finalTokens = tokenCount
            await MainActor.run {
                assistantMsg.content = finalText
                assistantMsg.tokenCount = finalTokens
                conversation.totalTokensUsed += finalTokens
                conversation.messageCount = conversation.messages.count
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

        if !skipCache {
            await SemanticCache.shared.set(prompt: cacheKey, model: provider.defaultModel, response: fullResponse)
        }
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

        // Título provisório imediato (primeiras palavras) — exibido sem latência.
        let words = content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(7)
            .joined(separator: " ")
        let provisional = String(words.prefix(60))
        if !provisional.isEmpty { conversation.title = provisional }

        // Refina com modelo on-device (Apple Foundation Models) — privado, gratuito,
        // assíncrono. Se indisponível, mantém o título provisório.
        Task { [weak conversation] in
            guard let refined = await OnDeviceTitler.generateTitle(for: content) else { return }
            await MainActor.run { conversation?.title = refined }
        }
    }

    // MARK: - Helpers

    private func isCustom(_ providerType: String) -> Bool {
        switch providerType {
        case "openai", "anthropic": return false
        default: return true
        }
    }

    /// Bloco de contexto temporal injetado em cada mensagem para ancorar a IA no presente.
    static func currentDateContext() -> String {
        let now = Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: "pt_BR")
        df.timeZone = TimeZone.current
        df.dateFormat = "EEEE, d 'de' MMMM 'de' yyyy 'às' HH:mm"
        let formatted = df.string(from: now)
        let tzName = TimeZone.current.localizedName(for: .standard, locale: Locale(identifier: "pt_BR"))
            ?? TimeZone.current.identifier
        return """
        [Contexto temporal] Agora é \(formatted) (\(tzName)). \
        Use SEMPRE esta data e hora como "hoje"/"agora". Qualquer plano, cronograma, \
        prazo ou referência temporal deve partir desta data — nunca assuma um ano anterior \
        nem datas do seu treinamento.
        """
    }

    private func buildWebSearchContext(for query: String) async -> String? {
        guard needsWebSearch(query: query) else { return nil }
        streamingActivity = "Pesquisando na web…"
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

        parts.append("\nUse os resultados acima para responder com DADOS REAIS e cite as fontes (URLs). NÃO responda que 'não tem acesso' — os dados estão acima. Se precisar estimar, mostre o cálculo e marque como estimativa.")
        return parts.joined(separator: "\n\n")
    }

    private func needsWebSearch(query: String) -> Bool {
        let lower = query.lowercased()

        // 1) Intenção explícita de busca
        let explicit = ["pesquise", "busque", "procure", "search", "google", "na internet", "na web"]
        if explicit.contains(where: { lower.contains($0) }) { return true }

        // 2) Pergunta factual/quantitativa: interrogativo + termo de dado real.
        //    O app pesquisa e entrega o material pronto ao modelo.
        let isQuestion = lower.contains("?")
            || ["qual", "quais", "quando", "onde", "quem", "quanto", "quantos", "quantas",
                "como", "por que", "porque"].contains(where: { lower.contains($0) })
        let factual = ["clima", "tempo", "previsão", "chuva", "precipita", "temperatura",
                       "notícia", "preço", "preco", "cotação", "cotacao", "valor", "custo",
                       "média", "media", "taxa", "percentual", "porcentagem", "índice", "indice",
                       "estatística", "estatistica", "população", "populacao", "habitantes",
                       "distância", "distancia", "pib", "ranking", "quantos km", "área", "area",
                       "produção", "producao", "exportação", "importação", "frota", "tarifa",
                       "weather", "price", "news", "stock", "population", "average", "rate", "statistics"]
        if isQuestion && factual.contains(where: { lower.contains($0) }) { return true }

        return false
    }

    private func needsDeepFetch(query: String) -> Bool {
        let lower = query.lowercased()
        if ["tutorial passo a passo", "como instalar", "como configurar",
            "github.com", "github.io", "stackoverflow.com"]
            .contains(where: { lower.contains($0) }) { return true }
        // Para perguntas factuais/quantitativas, ler o conteúdo das páginas ajuda
        // a obter números reais (não apenas o snippet da busca).
        return needsWebSearch(query: query)
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
        // Delay adaptativo: mais rápido para respostas longas (mínimo 1ms, máximo 4ms)
        let delayNs = UInt64(max(1_000_000, min(4_000_000, 400_000_000 / max(1, words.count))))
        var accumulated = ""
        for word in words {
            accumulated += (accumulated.isEmpty ? "" : " ") + word
            let current = accumulated
            await MainActor.run { message.content = current }
            try? await Task.sleep(nanoseconds: delayNs)
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
