//
//  LumeConfig.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation

/// Configuração global do app — persiste em JSON no diretório de suporte.
/// Pode ser editada manualmente como um arquivo de config.
struct LumeConfig: Codable {
    // MARK: - Agent
    var approvalMode: ApprovalMode = .supervised
    var maxAgentIterations: Int = 10
    var enableModelRouting: Bool = true
    var enableSemanticCache: Bool = true
    var enableRAG: Bool = true
    var enablePromptCaching: Bool = true  // Anthropic only
    var enableMemory: Bool = true         // memória persistente entre conversas

    // MARK: - Context
    var maxContextTokens: Int = 12_000
    var contextSummarizationThreshold: Double = 0.80
    var slidingWindowRecentMessages: Int = 6

    // MARK: - Style
    var defaultLanguage: String = "pt-BR"
    var defaultTone: String = "balanced"

    // MARK: - Safety
    var blockDangerousShellCommands: Bool = true
    var requireWorkspaceForFileOps: Bool = true

    // MARK: - Notifications
    var notifyOnTaskComplete: Bool = true
    var notifyWhenInBackground: Bool = true

    // MARK: - Persistence

    private static let configURL: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Lume")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("config.json")
    }()

    static func load() -> LumeConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(LumeConfig.self, from: data) else {
            return LumeConfig()
        }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }

    static var configFilePath: String { configURL.path }
}

// MARK: - Approval Mode

enum ApprovalMode: String, Codable, CaseIterable {
    case autonomous  // Executa tudo sem pedir
    case supervised  // Pede aprovação para operações destrutivas
    case strict      // Pede aprovação para qualquer tool call

    var label: String {
        switch self {
        case .autonomous: return String(localized: "Autonomous")
        case .supervised: return String(localized: "Supervised")
        case .strict:     return String(localized: "Strict")
        }
    }

    var description: String {
        switch self {
        case .autonomous: return String(localized: "The agent runs all actions automatically.")
        case .supervised: return String(localized: "Asks for approval on operations that modify files or run code.")
        case .strict:     return String(localized: "Each action requires your explicit approval.")
        }
    }

    var icon: String {
        switch self {
        case .autonomous: return "bolt.fill"
        case .supervised: return "eye.fill"
        case .strict:     return "lock.fill"
        }
    }
}
