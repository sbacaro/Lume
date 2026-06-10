//
//  ModelRouter.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation

/// Roteamento automático de modelos baseado em complexidade e custo.
struct ModelRouter {

    enum Complexity {
        case simple      // Perguntas factuais curtas, reformulações
        case moderate    // Análise, código simples, explicações
        case complex     // Raciocínio multi-step, código arquitetural, documentos longos
    }

    struct RoutingDecision {
        let model: String
        let reason: String
        let complexity: Complexity
    }

    // MARK: - Route

    /// Analisa o prompt e histórico e decide qual modelo usar.
    static func route(
        prompt: String,
        history: [Message],
        provider: String,
        preferredModel: String
    ) -> RoutingDecision {
        let complexity = analyze(prompt: prompt, history: history)

        switch provider {
        case "openai":
            return routeOpenAI(complexity: complexity, preferred: preferredModel)
        case "anthropic":
            return routeAnthropic(complexity: complexity, preferred: preferredModel)
        default:
            return RoutingDecision(model: preferredModel, reason: "Default", complexity: complexity)
        }
    }

    // MARK: - Analysis

    static func analyze(prompt: String, history: [Message]) -> Complexity {
        let lower = prompt.lowercased()
        let wordCount = prompt.components(separatedBy: .whitespaces).count
        let historyLength = history.count

        // Simple heuristics
        let isShort = wordCount < 15
        let hasCode = prompt.contains("```") || lower.contains("código") ||
                      lower.contains("function") || lower.contains("class") ||
                      lower.contains("algorithm") || lower.contains("algoritmo")
        let isComplex = lower.contains("arquitetura") || lower.contains("architecture") ||
                        lower.contains("design system") || lower.contains("refactor") ||
                        lower.contains("step by step") || lower.contains("passo a passo") ||
                        lower.contains("explica") && wordCount > 20
        let hasLongHistory = historyLength > 20
        let isDocumentTask = lower.contains("resuma") || lower.contains("summarize") ||
                             lower.contains("analise") || lower.contains("analyze")

        if isComplex || hasCode && wordCount > 30 || hasLongHistory && isDocumentTask {
            return .complex
        } else if hasCode || isDocumentTask || wordCount > 30 {
            return .moderate
        } else if isShort {
            return .simple
        }
        return .moderate
    }

    // MARK: - Provider-specific routing

    private static func routeOpenAI(complexity: Complexity, preferred: String) -> RoutingDecision {
        // Don't override if user explicitly chose a specific model
        let userChose = preferred != "gpt-4"
        if userChose {
            return RoutingDecision(model: preferred, reason: "User preference", complexity: complexity)
        }

        switch complexity {
        case .simple:
            return RoutingDecision(
                model: "gpt-3.5-turbo",
                reason: "Simple query — using faster model",
                complexity: complexity
            )
        case .moderate:
            return RoutingDecision(
                model: "gpt-4o",
                reason: "Moderate complexity — using balanced model",
                complexity: complexity
            )
        case .complex:
            return RoutingDecision(
                model: "gpt-4o",
                reason: "High complexity — using most capable model",
                complexity: complexity
            )
        }
    }

    private static func routeAnthropic(complexity: Complexity, preferred: String) -> RoutingDecision {
        let userChose = preferred != "claude-3-opus-20240229"
        if userChose {
            return RoutingDecision(model: preferred, reason: "User preference", complexity: complexity)
        }

        switch complexity {
        case .simple:
            return RoutingDecision(
                model: "claude-3-5-haiku-20241022",
                reason: "Simple query — using fastest model",
                complexity: complexity
            )
        case .moderate:
            return RoutingDecision(
                model: "claude-sonnet-4-5",
                reason: "Moderate complexity — using balanced model",
                complexity: complexity
            )
        case .complex:
            return RoutingDecision(
                model: "claude-opus-4-5",
                reason: "High complexity — using most capable model",
                complexity: complexity
            )
        }
    }
}
