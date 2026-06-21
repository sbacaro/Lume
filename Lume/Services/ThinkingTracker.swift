// ThinkingTracker.swift
import Foundation
import Observation

/// Acumula as anotações de "o que a IA está fazendo" durante o streaming.
@Observable
final class ThinkingTracker {

    struct Step: Identifiable {
        let id = UUID()
        var label: String          // ex: "Analisando o problema…"
        var detail: String = ""    // texto acumulado opcional
        var isDone: Bool = false
        var icon: String = "circle.dotted"  // SF Symbol
    }

    var steps: [Step] = []
    var isActive: Bool = false
    var currentLabel: String = ""

    func start() {
        steps = []
        isActive = true
        currentLabel = ""
    }

    func addStep(_ label: String, icon: String = "circle.dotted") {
        let step = Step(label: label, icon: icon)
        steps.append(step)
        currentLabel = label
    }

    func appendDetail(_ text: String) {
        guard !steps.isEmpty else { return }
        steps[steps.count - 1].detail += text
    }

    func completeLastStep(icon: String = "checkmark.circle.fill") {
        guard !steps.isEmpty else { return }
        steps[steps.count - 1].isDone = true
        steps[steps.count - 1].icon = icon
    }

    func finish() {
        // Mark all remaining pending steps as done
        for i in steps.indices where !steps[i].isDone {
            steps[i].isDone = true
            steps[i].icon = "checkmark.circle.fill"
        }
        isActive = false
        currentLabel = ""
    }

    func reset() {
        steps = []
        isActive = false
        currentLabel = ""
    }
}
