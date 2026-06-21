//
//  OnDeviceComplexity.swift
//  Lume
//
//  Classificação de complexidade de prompt 100% on-device (Apple Foundation Models,
//  macOS 26+). Complementa a heurística por palavras-chave do `LLMRouter`. Quando o
//  modelo local não está disponível, retorna nil e o chamador cai para a heurística.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum OnDeviceComplexity {

    /// Indica se o modelo on-device está disponível neste dispositivo.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Classifica a complexidade da tarefa do usuário como `.low`, `.medium` ou `.high`.
    /// Retorna nil se o modelo on-device não estiver disponível ou a resposta for ambígua.
    static func classify(prompt: String) async -> LLMRouter.ComplexityLevel? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                let session = LanguageModelSession(
                    instructions: """
                    Classifique a complexidade da tarefa do usuário em EXATAMENTE uma palavra: \
                    low, medium ou high. Use 'low' para saudações e perguntas triviais; \
                    'medium' para tarefas comuns; 'high' para raciocínio profundo, código \
                    complexo, análise detalhada ou múltiplos passos. Responda apenas a palavra.
                    """
                )
                let response = try await session.respond(to: String(trimmed.prefix(2000)))
                let word = response.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if word.contains("high")   { return .high }
                if word.contains("low")    { return .low }
                if word.contains("medium") { return .medium }
                return nil
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
