//
//  OnDeviceSummarizer.swift
//  Lume
//
//  Sumarização de contexto 100% on-device usando o modelo de linguagem do sistema
//  (Apple Foundation Models, macOS 26+). Privado, gratuito e offline. Quando o
//  modelo não está disponível, retorna nil e o chamador cai para a sumarização
//  via API (que custa tokens).
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum OnDeviceSummarizer {

    /// Indica se o modelo on-device está disponível neste dispositivo.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Resume um trecho de conversa (transcript já montado em texto) de forma breve
    /// e factual. Retorna nil se o modelo on-device não estiver disponível ou falhar.
    static func summarize(transcript: String) async -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                let session = LanguageModelSession(
                    instructions: """
                    Você resume conversas de forma breve e factual, preservando decisões, \
                    fatos importantes, nomes/arquivos citados e pontos pendentes. Responda \
                    apenas com o resumo, em tópicos curtos, no mesmo idioma da conversa, \
                    sem preâmbulo.
                    """
                )
                // Limita o tamanho de entrada para o contexto do modelo on-device.
                let response = try await session.respond(to: String(trimmed.prefix(6000)))
                let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return summary.isEmpty ? nil : summary
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
