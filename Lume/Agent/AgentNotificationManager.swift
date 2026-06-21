//
//  AgentNotificationManager.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import UserNotifications

/// Sends system notifications when long-running agent tasks complete.
final class AgentNotificationManager {
    static let shared = AgentNotificationManager()
    private var authorized = false

    private init() {}

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            authorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            authorized = false
        }
    }

    func notifyTaskComplete(title: String, body: String) {
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }

    func notifyAgentFinished(conversationTitle: String, summary: String) {
        notifyTaskComplete(
            title: "Lume — Tarefa concluída",
            body: "\(conversationTitle): \(summary.prefix(100))"
        )
    }
}
