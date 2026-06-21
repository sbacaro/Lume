//
//  ApprovalCoordinator.swift
//  Lume
//
//  Ponte entre a execução de ferramentas do agente e a UI de aprovação.
//  Quando o modo de aprovação exige confirmação, o executor chama
//  `requestApproval` e fica suspenso (sem bloquear a thread) até o usuário
//  aprovar ou recusar na interface, que chama `resolve`.
//

import Foundation
import Observation

@MainActor
@Observable
final class ApprovalCoordinator {
    static let shared = ApprovalCoordinator()

    /// Solicitação de aprovação pendente (nil quando não há nenhuma).
    var pending: PendingApproval?

    struct PendingApproval: Identifiable {
        let id = UUID()
        let toolName: String
        /// Resumo curto da ação (ex.: "Executar comando").
        let summary: String
        /// Detalhe (comando, caminho, prévia de conteúdo).
        let detail: String
        /// Se a ação modifica o sistema (escrita/execução).
        let isDestructive: Bool
        let continuation: CheckedContinuation<Bool, Never>
    }

    private init() {}

    /// Pede aprovação ao usuário. Suspende até `resolve` ser chamado.
    /// Retorna true (aprovado) ou false (recusado).
    func requestApproval(
        toolName: String,
        summary: String,
        detail: String,
        isDestructive: Bool
    ) async -> Bool {
        // Se já há uma aprovação pendente, recusa a nova para evitar fila travada.
        if pending != nil { return false }
        return await withCheckedContinuation { continuation in
            pending = PendingApproval(
                toolName: toolName,
                summary: summary,
                detail: detail,
                isDestructive: isDestructive,
                continuation: continuation
            )
        }
    }

    /// Resolve a aprovação pendente com a decisão do usuário.
    func resolve(_ approved: Bool) {
        guard let current = pending else { return }
        pending = nil
        current.continuation.resume(returning: approved)
    }
}
