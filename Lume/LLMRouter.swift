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
            case .codeGeneration:    return "Geração de código"
            case .longContext:       return "Contexto longo"
            case .multimodal:        return "Multimodal"
            case .preferredModel:    return "Modelo preferido"
            case .costOptimized:     return "Otimizado para custo"
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
        "anthropic": "claude-3-5-haiku-20241022"
    ]

    private static let powerfulModels: [String: String] = [
        "openai":    "gpt-4o",
        "anthropic": "claude-opus-4-5"
    ]

    private static let codeModels: [String: String] = [
        "openai":    "gpt-4o",
        "anthropic": "claude-sonnet-4-5"
    ]

    private static let longContextModels: [String: String] = [
        "openai":    "gpt-4o",
        "anthropic": "claude-opus-4-5"
    ]

    // MARK: - Context window sizes (tokens)

    private static let contextWindows: [String: Int] = [
        "gpt-4o":                        128_000,
        "gpt-4o-mini":                   128_000,
        "gpt-4-turbo":                   128_000,
        "gpt-4":                           8_192,
        "gpt-3.5-turbo":                  16_385,
        "claude-opus-4-5":               200_000,
        "claude-sonnet-4-5":             200_000,
        "claude-3-5-haiku-20241022":     200_000,
    ]

    // MARK: - Route

    static func route(
        prompt: String,
        history: [Message],
        provider: String,
        preferredModel: String,
        hasImages: Bool = false,
        forceMode: RoutingMode = .auto
    ) -> RoutingDecision {

        if forceMode == .preferred || !preferredModel.isEmpty {
            return RoutingDecision(
                model: preferredModel,
                providerType: provider,
                reason: .preferredModel,
                estimatedCost: costTier(for: preferredModel),
                confidence: 1.0
            )
        }

        if hasImages {
            let model = multimodalModel(for: provider) ?? preferredModel
            return RoutingDecision(model: model, providerType: provider,
                                   reason: .multimodal, estimatedCost: .expensive, confidence: 0.95)
        }

        let totalTokens = estimateTokens(prompt)
                        + history.map { estimateTokens($0.content) }.reduce(0, +)
        if totalTokens > 60_000 {
            let model = longContextModels[provider] ?? preferredModel
            return RoutingDecision(model: model, providerType: provider,
                                   reason: .longContext, estimatedCost: .expensive, confidence: 0.9)
        }

        switch forceMode {
        case .cheap:
            let model = cheapModels[provider] ?? preferredModel
            return RoutingDecision(model: model, providerType: provider,
                                   reason: .costOptimized, estimatedCost: .cheap, confidence: 0.85)
        case .powerful:
            let model = powerfulModels[provider] ?? preferredModel
            return RoutingDecision(model: model, providerType: provider,
                                   reason: .complexReasoning, estimatedCost: .expensive, confidence: 0.9)
        default:
            break
        }

        let complexity = analyzeComplexity(prompt: prompt, history: history)

        switch complexity {
        case .low:
            let model = cheapModels[provider] ?? preferredModel
            return RoutingDecision(model: model, providerType: provider,
                                   reason: .simpleQuery, estimatedCost: .cheap, confidence: 0.8)
        case .medium:
            let model = codeModels[provider] ?? preferredModel
            let isCode = isCodeRelated(prompt)
            return RoutingDecision(
                model: model, providerType: provider,
                reason: isCode ? .codeGeneration : .complexReasoning,
                estimatedCost: .medium, confidence: 0.75
            )
        case .high:
            let model = powerfulModels[provider] ?? preferredModel
            return RoutingDecision(model: model, providerType: provider,
                                   reason: .complexReasoning, estimatedCost: .expensive, confidence: 0.85)
        }
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

    static func costTier(for model: String) -> RoutingDecision.CostTier {
        let cheap = ["gpt-4o-mini", "claude-3-5-haiku-20241022", "gpt-3.5-turbo"]
        let expensive = ["gpt-4", "claude-opus-4-5", "gpt-4-turbo"]
        if cheap.contains(model) { return .cheap }
        if expensive.contains(model) { return .expensive }
        return .medium
    }

    static func multimodalModel(for provider: String) -> String? {
        switch provider {
        case "openai":    return "gpt-4o"
        case "anthropic": return "claude-opus-4-5"
        default:          return nil
        }
    }

    static func maxContextWindow(for model: String) -> Int {
        contextWindows[model] ?? 4_096
    }
}

// MARK: - Routing Mode

enum RoutingMode {
    case auto
    case cheap
    case powerful
    case preferred
}
