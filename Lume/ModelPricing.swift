//
//  ModelPricing.swift
//  Lume
//
//  Tabela aproximada de preços por modelo (USD por 1M de tokens) e utilitários
//  para estimar o custo de uma conversa. Os valores são estimativas para exibição
//  na UI — não substituem o faturamento real do provider.
//

import Foundation

struct ModelPrice {
    /// USD por 1M de tokens de entrada.
    let input: Double
    /// USD por 1M de tokens de saída.
    let output: Double

    /// Preço médio ponderado assumindo uma divisão típica (~⅓ saída, ⅔ entrada).
    var blendedPer1M: Double { input * 0.65 + output * 0.35 }
}

enum ModelPricing {

    /// Preços conhecidos (junho/2026). Estimativas — ajuste conforme a tabela oficial.
    private static let table: [String: ModelPrice] = [
        // OpenAI
        "gpt-4o":        ModelPrice(input: 2.50,  output: 10.00),
        "gpt-4o-mini":   ModelPrice(input: 0.15,  output: 0.60),
        "gpt-4-turbo":   ModelPrice(input: 10.00, output: 30.00),
        "gpt-3.5-turbo": ModelPrice(input: 0.50,  output: 1.50),
        // Anthropic
        "claude-opus-4-8":            ModelPrice(input: 15.00, output: 75.00),
        "claude-sonnet-4-6":          ModelPrice(input: 3.00,  output: 15.00),
        "claude-haiku-4-5-20251001":  ModelPrice(input: 0.80,  output: 4.00),
    ]

    /// Busca o preço de um modelo, com correspondência por prefixo para variantes
    /// versionadas (ex.: "claude-haiku-4-5-20251001" casa com "claude-haiku-4-5").
    static func price(for model: String) -> ModelPrice? {
        if let exact = table[model] { return exact }
        let lower = model.lowercased()
        for (key, value) in table where lower.hasPrefix(key.lowercased()) || key.lowercased().hasPrefix(lower) {
            return value
        }
        // Heurística por família para modelos custom/desconhecidos.
        if lower.contains("haiku") || lower.contains("mini") { return ModelPrice(input: 0.20, output: 0.80) }
        if lower.contains("opus")  { return ModelPrice(input: 15.00, output: 75.00) }
        if lower.contains("sonnet") { return ModelPrice(input: 3.00, output: 15.00) }
        return nil
    }

    /// Custo estimado (USD) para um total de tokens usando o preço médio ponderado.
    static func estimatedCost(model: String, tokens: Int) -> Double? {
        guard let p = price(for: model), tokens > 0 else { return nil }
        return Double(tokens) / 1_000_000.0 * p.blendedPer1M
    }

    /// Formata um valor em dólar de forma compacta (ex.: "$0.0023", "$1.42").
    static func formatCost(_ cost: Double) -> String {
        if cost < 0.01 { return String(format: "$%.4f", cost) }
        if cost < 1    { return String(format: "$%.3f", cost) }
        return String(format: "$%.2f", cost)
    }

    /// Formata uma contagem de tokens de forma compacta (ex.: "1.2k", "3.4M").
    static func formatTokens(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000...: return String(format: "%.1fM", Double(tokens) / 1_000_000)
        case 1_000...:     return String(format: "%.1fk", Double(tokens) / 1_000)
        default:           return "\(tokens)"
        }
    }
}
