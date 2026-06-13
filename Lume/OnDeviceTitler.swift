//
//  OnDeviceTitler.swift
//  Lume
//
//  Geração de títulos de conversa 100% on-device usando o modelo de linguagem
//  do sistema (Apple Foundation Models, macOS 26+). Privado, gratuito e offline.
//  Em versões anteriores do macOS ou quando o modelo não está disponível,
//  `generateTitle` retorna nil e o chamador mantém o título provisório.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum OnDeviceTitler {

    /// Indica se o modelo on-device está disponível neste dispositivo.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Gera um título curto e descritivo para uma conversa a partir da primeira
    /// mensagem do usuário. Retorna nil se o modelo on-device não estiver disponível.
    static func generateTitle(for text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                let session = LanguageModelSession(
                    instructions: """
                    Você gera títulos curtos para conversas. Responda APENAS com o título, \
                    no máximo 5 palavras, no mesmo idioma da mensagem, sem aspas e sem \
                    pontuação final.
                    """
                )
                let prompt = "Crie um título para esta conversa:\n\n\(String(text.prefix(400)))"
                let response = try await session.respond(to: prompt)
                let title = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.“”"))
                return title.isEmpty ? nil : String(title.prefix(60))
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
