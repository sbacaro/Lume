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
    var title: String = "Nova Conversa"
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

    @Relationship(deleteRule: .cascade)
    var messages: [Message] = []

    @Relationship(inverse: \Project.conversations)
    var project: Project?

    init(
        title: String = "Nova Conversa",
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
