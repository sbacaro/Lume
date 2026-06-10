//
//  StyleProfile.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import SwiftData

@Model
final class StyleProfile {
    var id: String = UUID().uuidString
    var name: String
    var tone: String           // "formal", "casual", "technical", "creative"
    var verbosity: String      // "concise", "balanced", "detailed"
    var language: String       // "pt-BR", "en-US", etc.
    var customInstructions: String
    var isDefault: Bool = false
    var createdAt: Date = Date()

    init(
        name: String,
        tone: String = "balanced",
        verbosity: String = "balanced",
        language: String = "pt-BR",
        customInstructions: String = ""
    ) {
        self.name = name
        self.tone = tone
        self.verbosity = verbosity
        self.language = language
        self.customInstructions = customInstructions
    }

    /// Gera o suffix de system prompt baseado no perfil.
    var systemPromptSuffix: String {
        var parts: [String] = []

        switch tone {
        case "formal":    parts.append("Use a formal, professional tone.")
        case "casual":    parts.append("Use a casual, friendly tone.")
        case "technical": parts.append("Use precise technical language. Assume expert audience.")
        case "creative":  parts.append("Be expressive and creative in your responses.")
        default: break
        }

        switch verbosity {
        case "concise":  parts.append("Be extremely concise. Avoid filler.")
        case "detailed": parts.append("Provide thorough, detailed explanations.")
        default: break
        }

        if language != "en-US" {
            parts.append("Always respond in \(language).")
        }

        if !customInstructions.isEmpty {
            parts.append(customInstructions)
        }

        return parts.joined(separator: " ")
    }
}
