//
//  Conversation.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import SwiftData

@Model
final class Conversation {
    var id: String = UUID().uuidString
    var title: String = String(localized: "New Conversation")
    var providerType: String = "openai"
    var modelName: String = "gpt-4o"
    var systemPrompt: String = ""
    var isPinned: Bool = false
    var isArchived: Bool = false
    var tags: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // ── Painel direito — persistidos ─────────────────────────
    var referencedFiles: [String] = []
    var contextTags: [String] = []
    var userNotes: String = ""
    var totalTokensUsed: Int = 0
    var messageCount: Int = 0
    /// Tarefas extraídas das mensagens da IA — persistidas
    var tasks: [ConversationTask] = []
    /// Versões anteriores arquivadas ao editar/reiniciar a conversa (branching).
    /// Nada é destruído: o trecho substituído fica disponível para restaurar.
    var versionBranches: [ConversationBranch] = []

    @Relationship(deleteRule: .cascade)
    var messages: [Message] = []

    @Relationship(inverse: \Project.conversations)
    var project: Project?

    init(
        title: String = String(localized: "New Conversation"),
        providerType: String = "openai",
        modelName: String = "gpt-4o",
        systemPrompt: String = ""
    ) {
        self.title = title
        self.providerType = providerType
        self.modelName = modelName
        self.systemPrompt = systemPrompt
    }
}

// MARK: - ConversationTask (Codable para armazenar como [ConversationTask])

struct ConversationTask: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var text: String
    var isDone: Bool = false
    var sourceMessageID: String = ""
    var createdAt: Date = Date()
}

// MARK: - ConversationBranch (versões arquivadas — Codable, armazenado na Conversation)

struct BranchMessage: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var role: String
    var content: String
    var timestamp: Date = Date()
}

struct ConversationBranch: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    /// Índice (no array de mensagens) a partir do qual este trecho foi removido.
    var fromIndex: Int
    /// Rótulo descritivo (ex.: "Antes de editar").
    var label: String
    var createdAt: Date = Date()
    var messages: [BranchMessage]

    /// Texto-resumo da primeira mensagem do usuário no branch, para exibição.
    var preview: String {
        let first = messages.first(where: { $0.role == "user" }) ?? messages.first
        let text = first?.content ?? ""
        return String(text.prefix(80))
    }
}
