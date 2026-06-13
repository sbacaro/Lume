//
//  Message.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import SwiftData

@Model
final class Message {
    var id: String = UUID().uuidString
    var role: MessageRole
    var content: String
    var timestamp: Date = Date()
    var tokenCount: Int = 0
    /// Fontes (RAG) usadas para gerar esta resposta — exibidas como citações.
    var ragSources: [RAGSource] = []

    @Relationship(deleteRule: .cascade)
    var artifact: Artifact?

    init(role: MessageRole, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}
