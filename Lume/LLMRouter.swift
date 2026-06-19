//
//  LLMRouter.swift
//  Lume
//
//  Roteador de LLM inspirado em RouteLLM/Martian.
//  Decide qual modelo usar baseado em complexidade, custo e capacidade necessária.
//

import Foundation
import NaturalLanguage

// MARK: - Routing Decision (nível de módulo — acessível em todo o projeto)

struct RoutingDecision {
    let model: String
    let providerType: String
    let reason: RoutingReason
    let estimatedCost: CostTier
    let confidence: Double

    enum RoutingReason {
        case simpleQuery
        case complexReasoning
        case codeGeneration
        case longContext
        case multimodal
        case preferredModel
        case costOptimized

        var description: String {
            switch self {
            case .simpleQuery:       return "Consulta simples"
            case .complexReasoning:  return "Raciocínio complexo"
            case .codeGeneration:    return String(localized: "Code generation")
            case .longContext:       return "Contexto longo"
            case .multimodal:        return "Multimodal"
            case .preferredModel:    return "Modelo preferido"
            case .costOptimized:     return String(localized: "Cost-optimized")
            }
        }
    }

    enum CostTier: String {
        case cheap     = "💚 Econômico"
        case medium    = "🟡 Médio"
        case expensive = "🔴 Premium"
    }
}

// MARK: - LLM Router

enum LLMRouter {

    // MARK: - Modelos por categoria

    private static let cheapModels: [String: String] = [
        "openai":    "gpt-4o-mini",
        "anthropic": "claude-haiku-4-5-20251001"
    ]

    private static let powerfulModels: [String: String] = [
        "openai":    "gpt-4o",
        "anthropic": "claude-opus-4-8"
    ]

    private static let codeModels: [String: String] = [
        "openai":    "gpt-4o",
        "anthropic": "claude-sonnet-4-6"
    ]

    private static let longContextModels: [String: String] = [
        "openai":    "gpt-4o",
        "anthropic": "claude-opus-4-8"
    ]

    // MARK: - Context window sizes (tokens)

    private static let contextWindows: [String: Int] = [
        "gpt-4o":                         128_000,
        "gpt-4o-mini":                    128_000,
        "gpt-4-turbo":                    128_000,
        "gpt-4":                            8_192,
        "gpt-3.5-turbo":                   16_385,
        "claude-opus-4-8":                200_000,
        "claude-sonnet-4-6":              200_000,
        "claude-haiku-4-5-20251001":      200_000,
        // aliases para compatibilidade retroativa
        "claude-opus-4-5":                200_000,
        "claude-sonnet-4-5":              200_000,
        "claude-3-5-haiku-20241022":      200_000,
    ]

    // MARK: - Route

    static func route(
        prompt: String,
        history: [Message],
        provider: String,
        preferredModel: String,
        hasImages: Bool = false,
        forceMode: RoutingMode = .auto,
        complexityOverride: ComplexityLevel? = nil
    ) -> RoutingDecision {

        // Detecta o provider real a partir do modelo (suporta gateways com prefixo)
        let effectiveProvider = preferredModel.contains("/")
            ? inferProvider(from: preferredModel)
            : provider

        // Modo preferido: sempre usa o modelo definido na conversa, sem override
        if forceMode == .preferred {
            return RoutingDecision(
                model: preferredModel,
                providerType: effectiveProvider,
                reason: .preferredModel,
                estimatedCost: costTier(for: preferredModel),
                confidence: 1.0
            )
        }

        // Se não tiver modelo preferido definido, usa preferredModel como âncora
        if preferredModel.isEmpty {
            return RoutingDecision(
                model: preferredModel,
                providerType: effectiveProvider,
                reason: .preferredModel,
                estimatedCost: .medium,
                confidence: 1.0
            )
        }

        if hasImages {
            let model = multimodalModel(for: effectiveProvider) ?? preferredModel
            return RoutingDecision(model: model, providerType: effectiveProvider,
                                   reason: .multimodal, estimatedCost: .expensive, confidence: 0.95)
        }

        let totalTokens = estimateTokens(prompt)
                        + history.map { estimateTokens($0.content) }.reduce(0, +)
        if totalTokens > 60_000 {
            let model = longContextModels[effectiveProvider] ?? preferredModel
            return RoutingDecision(model: model, providerType: effectiveProvider,
                                   reason: .longContext, estimatedCost: .expensive, confidence: 0.9)
        }

        switch forceMode {
        case .cheap:
            let model = cheapModels[effectiveProvider] ?? preferredModel
            return RoutingDecision(model: model, providerType: effectiveProvider,
                                   reason: .costOptimized, estimatedCost: .cheap, confidence: 0.85)
        case .powerful:
            let model = powerfulModels[effectiveProvider] ?? preferredModel
            return RoutingDecision(model: model, providerType: effectiveProvider,
                                   reason: .complexReasoning, estimatedCost: .expensive, confidence: 0.9)
        default:
            break
        }

        let complexity = complexityOverride ?? analyzeComplexity(prompt: prompt, history: history)

        switch complexity {
        case .low:
            // Para gateways: mantém o modelo preferido em vez de tentar trocar por um "barato" desconhecido
            let model = cheapModels[effectiveProvider] ?? preferredModel
            return RoutingDecision(model: model, providerType: effectiveProvider,
                                   reason: .simpleQuery, estimatedCost: .cheap, confidence: 0.8)
        case .medium:
            let model = codeModels[effectiveProvider] ?? preferredModel
            let isCode = isCodeRelated(prompt)
            return RoutingDecision(
                model: model, providerType: effectiveProvider,
                reason: isCode ? .codeGeneration : .complexReasoning,
                estimatedCost: .medium, confidence: 0.75
            )
        case .high:
            let model = powerfulModels[effectiveProvider] ?? preferredModel
            return RoutingDecision(model: model, providerType: effectiveProvider,
                                   reason: .complexReasoning, estimatedCost: .expensive, confidence: 0.85)
        }
    }

    // MARK: - Async routing (complexidade on-device)

    /// Versão assíncrona do `route`: em modo `.auto`, classifica a complexidade com o
    /// modelo on-device (Foundation Models) e usa o resultado como override; cai para
    /// a heurística por palavras-chave quando o modelo local não está disponível.
    static func routeAsync(
        prompt: String,
        history: [Message],
        provider: String,
        preferredModel: String,
        hasImages: Bool = false,
        forceMode: RoutingMode = .auto
    ) async -> RoutingDecision {
        let override = forceMode == .auto ? await OnDeviceComplexity.classify(prompt: prompt) : nil
        return route(
            prompt: prompt, history: history, provider: provider,
            preferredModel: preferredModel, hasImages: hasImages,
            forceMode: forceMode, complexityOverride: override
        )
    }

    // MARK: - Complexity Analysis

    enum ComplexityLevel { case low, medium, high }

    static func analyzeComplexity(prompt: String, history: [Message]) -> ComplexityLevel {
        let lower = prompt.lowercased()
        let wordCount = prompt.components(separatedBy: .whitespaces).count
        let historyDepth = history.count

        let highKeywords = [
            "analyze", "analise", "compare", "evaluate", "avalie", "design", "projete",
            "architect", "arquitete", "implement", "implemente", "debug", "optimize",
            "otimize", "refactor", "refatore", "explain in detail", "explique em detalhes",
            "step by step", "passo a passo", "why", "como funciona", "implications"
        ]
        let lowKeywords = [
            "o que é", "what is", "define", "defina", "list", "liste",
            "simple", "simples", "quick", "rápido", "translate", "traduza",
            "summarize", "resuma", "hi", "oi", "hello", "olá"
        ]

        var score = 0
        if wordCount > 100 { score += 2 } else if wordCount > 30 { score += 1 }
        if historyDepth > 10 { score += 2 } else if historyDepth > 4 { score += 1 }
        if highKeywords.contains(where: { lower.contains($0) }) { score += 2 }
        if lowKeywords.contains(where: { lower.contains($0) }) { score -= 1 }
        if isCodeRelated(prompt) { score += 1 }
        if containsMath(prompt) { score += 1 }

        if score <= 1 { return .low }
        if score <= 3 { return .medium }
        return .high
    }

    // MARK: - Helpers

    static func isCodeRelated(_ text: String) -> Bool {
        let keywords = ["```", "func ", "function ", "class ", "def ", "var ", "let ",
                        "const ", "import ", "return ", "if (", "for (", "swift", "python",
                        "javascript", "typescript", "rust", "go", "código", "code",
                        "implementa", "implement", "função", "method"]
        return keywords.contains { text.contains($0) }
    }

    static func containsMath(_ text: String) -> Bool {
        let patterns = ["∫", "∑", "√", "π", "equation", "equação", "calculate", "calcule",
                        "formula", "fórmula", "algebra", "álgebra", "derivative", "derivada"]
        return patterns.contains { text.lowercased().contains($0) }
    }

    static func estimateTokens(_ text: String) -> Int { max(1, text.count / 4) }

    // MARK: - Provider prefix detection
    // Suporta modelos com prefixo: "anthropic/claude-opus-4-8", "vertex_ai/gemini-2.5-flash", etc.

    /// Extrai o nome curto do modelo removendo o prefixo do provider gateway
    /// "anthropic/claude-opus-4-8" → "claude-opus-4-8"
    /// "vertex_ai/gemini-2.5-flash" → "gemini-2.5-flash"
    /// "claude-opus-4-8" → "claude-opus-4-8" (sem mudança)
    static func bareModelName(_ model: String) -> String {
        guard let slash = model.firstIndex(of: "/") else { return model }
        let name = String(model[model.index(after: slash)...])
        return name.isEmpty ? model : name
    }

    /// Detecta o provider base a partir do prefixo do modelo
    /// "anthropic/..." → "anthropic"; "openai/..." → "openai"; "vertex_ai/gemini..." → "google"
    static func inferProvider(from model: String) -> String {
        let lower = model.lowercased()
        if lower.hasPrefix("anthropic/") || lower.hasPrefix("awsbedrock/us.anthropic") ||
           lower.hasPrefix("awsbedrock/global.anthropic") { return "anthropic" }
        if lower.hasPrefix("openai/") || lower.hasPrefix("awsbedrock/openai") { return "openai" }
        if lower.hasPrefix("vertex_ai/gemini") || lower.hasPrefix("google/") { return "google" }
        if lower.hasPrefix("vertex_ai/") { return "google" }
        if lower.hasPrefix("awsbedrock/meta") || lower.contains("llama") { return "meta" }
        if lower.hasPrefix("awsbedrock/") { return "aws" }
        if lower.contains("gemini") { return "google" }
        if lower.contains("gpt") || lower.contains("o1") || lower.contains("o3") ||
           lower.contains("o4") { return "openai" }
        if lower.contains("claude") { return "anthropic" }
        if lower.contains("mistral") || lower.contains("mixtral") { return "mistral" }
        if lower.contains("llama") || lower.contains("glm") { return "meta" }
        if lower.contains("deepseek") { return "deepseek" }
        return "unknown"
    }

    static func costTier(for model: String) -> RoutingDecision.CostTier {
        let bare = bareModelName(model).lowercased()
        // Padrões de modelos econômicos (por substring no nome curto)
        let cheapPatterns = ["mini", "haiku", "nano", "flash", "lite", "micro",
                             "3.5-turbo", "gpt-3", "nova-lite", "nova-micro",
                             "llama3-2-1b", "llama3-2-3b", "llama3-1-8b",
                             "small", "phi-3", "gemma"]
        // Padrões de modelos premium
        let expensivePatterns = ["opus", "gpt-4", "gpt-5", "o1", "o3", "o4",
                                 "nova-premier", "nova-pro", "llama3-1-405b",
                                 "gemini-3-pro", "gemini-2.5-pro", "405b",
                                 "ultra", "pro-preview", "sonnet"]
        if cheapPatterns.contains(where: { bare.contains($0) }) { return .cheap }
        if expensivePatterns.contains(where: { bare.contains($0) }) { return .expensive }
        return .medium
    }

    static func multimodalModel(for provider: String) -> String? {
        switch provider {
        case "openai":    return "gpt-4o"
        case "anthropic": return "claude-opus-4-8"
        case "google":    return "vertex_ai/gemini-2.5-flash"
        default:          return nil
        }
    }

    static func maxContextWindow(for model: String) -> Int {
        // Verifica pelo nome completo primeiro, depois pelo nome curto
        if let exact = contextWindows[model] { return exact }
        let bare = bareModelName(model)
        if let bareLookup = contextWindows[bare] { return bareLookup }
        // Inferência por padrão de nome para modelos não catalogados
        let lower = bare.lowercased()
        if lower.contains("gemini") || lower.contains("claude") { return 200_000 }
        if lower.contains("glm") { return 200_000 }           // GLM-4.5/4.6 (ex.: globant_dgx/GLM-4.6)
        if lower.contains("gpt-4") || lower.contains("gpt-5") { return 128_000 }
        if lower.contains("llama") || lower.contains("qwen")
            || lower.contains("deepseek") || lower.contains("mistral") { return 128_000 }
        return 32_000 // conservador para modelos desconhecidos
    }
}

// MARK: - Routing Mode

enum RoutingMode {
    case auto
    case cheap
    case powerful
    case preferred
}
