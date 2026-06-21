//
//  WorkflowEngine.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import SwiftData

// MARK: - Workflow Models

@Model
final class Workflow {
    var id: String = UUID().uuidString
    var name: String
    var steps: [WorkflowStep]
    var triggerType: String  // "manual", "schedule", "file_change"
    var isEnabled: Bool = true
    var createdAt: Date = Date()
    var lastRunAt: Date?

    init(name: String, steps: [WorkflowStep] = [], triggerType: String = "manual") {
        self.name = name
        self.steps = steps
        self.triggerType = triggerType
    }
}

struct WorkflowStep: Codable, Identifiable {
    var id: String = UUID().uuidString
    var type: StepType
    var prompt: String
    var toolName: String?
    var condition: String?   // jinja-like: "{{prev_output}} contains 'error'"
    var outputVar: String?   // store output as variable

    enum StepType: String, Codable {
        case llmCall       // send prompt to LLM
        case toolCall      // call an agent tool
        case conditional   // branch based on condition
        case subAgent      // spawn a sub-agent with its own conversation
        case humanApproval // pause and wait for user confirmation
    }
}

// MARK: - Workflow Engine

@Observable
final class WorkflowEngine {
    static let shared = WorkflowEngine()

    var runningWorkflows: [String: WorkflowRun] = [:]
    var onStepCompleted: ((String, WorkflowStep, String) -> Void)?
    var onWorkflowCompleted: ((String) -> Void)?

    private init() {}

    // MARK: - Run

    @discardableResult
    func run(
        workflow: Workflow,
        providerManager: AIProviderManager,
        conversation: Conversation
    ) async throws -> String {
        let runID = UUID().uuidString
        let run = WorkflowRun(workflowID: workflow.id, steps: workflow.steps)
        runningWorkflows[runID] = run

        var context: [String: String] = [:]
        var lastOutput = ""

        for step in workflow.steps {
            // Check condition
            if let condition = step.condition,
               !evaluateCondition(condition, context: context) {
                continue
            }

            switch step.type {
            case .llmCall:
                let prompt = interpolate(step.prompt, context: context)
                lastOutput = try await providerManager.streamMessage(
                    content: prompt,
                    conversation: conversation
                )

            case .toolCall:
                if let toolName = step.toolName {
                    lastOutput = await callTool(
                        name: toolName,
                        prompt: interpolate(step.prompt, context: context)
                    )
                }

            case .humanApproval:
                // Pause — UI will resume via resumeWorkflow()
                runningWorkflows[runID]?.waitingForApproval = true
                runningWorkflows[runID]?.pendingStep = step
                return "[waiting_for_approval]"

            case .subAgent:
                let subConversation = Conversation(
                    title: "Sub-agent: \(step.prompt.prefix(30))",
                    providerType: conversation.providerType,
                    modelName: conversation.modelName,
                    systemPrompt: conversation.systemPrompt
                )
                lastOutput = try await providerManager.streamMessage(
                    content: interpolate(step.prompt, context: context),
                    conversation: subConversation
                )

            case .conditional:
                break // handled above
            }

            if let outputVar = step.outputVar {
                context[outputVar] = lastOutput
            }
            context["prev_output"] = lastOutput
            onStepCompleted?(runID, step, lastOutput)
        }

        runningWorkflows.removeValue(forKey: runID)
        workflow.lastRunAt = Date()
        onWorkflowCompleted?(runID)
        return lastOutput
    }

    func resumeWorkflow(runID: String, approved: Bool) {
        guard approved else {
            runningWorkflows.removeValue(forKey: runID)
            return
        }
        runningWorkflows[runID]?.waitingForApproval = false
    }

    // MARK: - Helpers

    private func interpolate(_ template: String, context: [String: String]) -> String {
        var result = template
        for (key, value) in context {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    private func evaluateCondition(_ condition: String, context: [String: String]) -> Bool {
        // Simple: "{{var}} contains 'text'"
        let pattern = /\{\{(\w+)\}\}\s+contains\s+'([^']+)'/
        if let match = condition.firstMatch(of: pattern) {
            let varName = String(match.1)
            let searchTerm = String(match.2)
            return context[varName]?.contains(searchTerm) ?? false
        }
        return true
    }

    private func callTool(name: String, prompt: String) async -> String {
        switch name {
        case "run_shell":
            let result = await AgentToolExecutor.shared.runShell(
                command: prompt, workingDirectory: nil
            )
            return result.output
        case "read_file":
            let result = await AgentToolExecutor.shared.readFile(at: prompt)
            return result.output
        default:
            return "[tool \(name) not found]"
        }
    }
}

// MARK: - Run State

final class WorkflowRun {
    let workflowID: String
    let steps: [WorkflowStep]
    var waitingForApproval = false
    var pendingStep: WorkflowStep?

    init(workflowID: String, steps: [WorkflowStep]) {
        self.workflowID = workflowID
        self.steps = steps
    }
}
