//
//  TaskScheduler.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import SwiftData
import UserNotifications

@Model
final class ScheduledTask {
    var id: String = UUID().uuidString
    var title: String
    var prompt: String
    var conversationID: String
    var scheduledAt: Date
    var recurrence: String   // "none", "daily", "weekly"
    var isCompleted: Bool = false
    var createdAt: Date = Date()

    init(title: String, prompt: String, conversationID: String,
         scheduledAt: Date, recurrence: String = "none") {
        self.title = title
        self.prompt = prompt
        self.conversationID = conversationID
        self.scheduledAt = scheduledAt
        self.recurrence = recurrence
    }
}

@Observable
final class TaskScheduler {
    static let shared = TaskScheduler()
    private var timer: Timer?
    private var pendingTasks: [ScheduledTask] = []
    var onTaskFired: ((ScheduledTask) -> Void)?

    private init() {}

    func schedule(_ tasks: [ScheduledTask]) {
        pendingTasks = tasks.filter { !$0.isCompleted }
        startPolling()
    }

    func add(_ task: ScheduledTask) {
        pendingTasks.append(task)
        // Schedule local notification
        let content = UNMutableNotificationContent()
        content.title = "Lume — Tarefa Agendada"
        content.body = task.title
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: task.scheduledAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: task.id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkTasks()
        }
    }

    private func checkTasks() {
        let now = Date()
        for task in pendingTasks where !task.isCompleted && task.scheduledAt <= now {
            onTaskFired?(task)
            task.isCompleted = true

            // Handle recurrence
            if task.recurrence == "daily" {
                task.scheduledAt = Calendar.current.date(byAdding: .day, value: 1, to: task.scheduledAt) ?? task.scheduledAt
                task.isCompleted = false
            } else if task.recurrence == "weekly" {
                task.scheduledAt = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: task.scheduledAt) ?? task.scheduledAt
                task.isCompleted = false
            }
        }
        pendingTasks.removeAll { $0.isCompleted && $0.recurrence == "none" }
    }
}
