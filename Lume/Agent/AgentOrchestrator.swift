//
//  AgentOrchestrator.swift
//  Lume
//

import Foundation

// MARK: - Agent Node

protocol AgentNode: Sendable {
    var id: String { get }
    var name: String { get }
    func execute(state: AgentState) async throws -> AgentState
}

// MARK: - Agent State
// Usa String (IDs) em vez de Message diretamente para ser Sendable

struct AgentState: Sendable {
    var messageContents: [String]   // conteúdo das mensagens em vez de Message objects
    var variables: [String: String]
    var toolResults: [String: String]
    var currentStep: String
    var iterationCount: Int
    var shouldContinue: Bool
    var finalOutput: String?
    var error: String?

    init(messageContents: [String] = [], variables: [String: String] = [:]) {
        self.messageContents = messageContents
        self.variables = variables
        self.toolResults = [:]
        self.currentStep = "start"
        self.iterationCount = 0
        self.shouldContinue = true
    }

    nonisolated init() {
        self.messageContents = []
        self.variables = [:]
        self.toolResults = [:]
        self.currentStep = "start"
        self.iterationCount = 0
        self.shouldContinue = true
    }
}

// MARK: - Agent Edge

struct AgentEdge: Sendable {
    let from: String
    let condition: @Sendable (AgentState) -> String
}

// MARK: - Agent Graph

final class AgentGraph: Sendable {
    private let _nodes: [String: any AgentNode]
    private let _edges: [String: AgentEdge]
    let entryPoint: String
    let maxIterations: Int

    init(nodes: [String: any AgentNode] = [:],
         edges: [String: AgentEdge] = [:],
         entryPoint: String = "start",
         maxIterations: Int = 25) {
        self._nodes = nodes
        self._edges = edges
        self.entryPoint = entryPoint
        self.maxIterations = maxIterations
    }

    final class Builder {
        var nodes: [String: any AgentNode] = [:]
        var edges: [String: AgentEdge] = [:]
        var entryPoint: String = "start"
        var maxIterations: Int = 25

        func addNode(_ node: any AgentNode) { nodes[node.id] = node }
        func addEdge(from: String, condition: @escaping @Sendable (AgentState) -> String) {
            edges[from] = AgentEdge(from: from, condition: condition)
        }
        func addSimpleEdge(from: String, to: String) {
            edges[from] = AgentEdge(from: from, condition: { _ in to })
        }
        func build() -> AgentGraph {
            AgentGraph(nodes: nodes, edges: edges, entryPoint: entryPoint, maxIterations: maxIterations)
        }
    }

    func execute(initialState: AgentState) async throws -> AgentState {
        var state = initialState
        state.currentStep = entryPoint
        while state.shouldContinue && state.iterationCount < maxIterations {
            guard let node = _nodes[state.currentStep] else {
                state.error = "Nó '\(state.currentStep)' não encontrado"; break
            }
            state = try await node.execute(state: state)
            state.iterationCount += 1
            if state.currentStep == "end" || state.finalOutput != nil { break }
            if let edge = _edges[state.currentStep] {
                state.currentStep = edge.condition(state)
            } else { break }
        }
        if state.iterationCount >= maxIterations {
            state.error = "Limite de iterações atingido (\(maxIterations))"
        }
        return state
    }
}

// MARK: - Built-in Nodes

struct LLMNode: AgentNode {
    let id: String
    let name: String
    let systemPrompt: String
    let providerManager: AIProviderManager
    var conversation: Conversation

    func execute(state: AgentState) async throws -> AgentState {
        var newState = state
        // Usa o último conteúdo do estado em vez de acessar conversation.messages diretamente
        let lastContent = state.messageContents.last ?? ""
        let response = try await providerManager.streamMessage(content: lastContent, conversation: conversation)
        newState.variables["last_response"] = response
        newState.messageContents.append(response)
        return newState
    }
}

struct ToolNode: AgentNode {
    let id: String
    let name: String
    let toolName: String
    let inputExtractor: @Sendable (AgentState) -> [String: String]

    func execute(state: AgentState) async throws -> AgentState {
        var newState = state
        let input = inputExtractor(state)
        let result = await AgentToolExecutor.shared.execute(toolName: toolName, input: input)
        newState.toolResults[toolName] = result.output
        newState.variables["last_tool_result"] = result.output
        newState.variables["last_tool_success"] = result.success ? "true" : "false"
        return newState
    }
}

struct ConditionNode: AgentNode {
    let id: String
    let name: String
    let condition: @Sendable (AgentState) -> Bool
    let trueVariable: String
    let falseVariable: String

    func execute(state: AgentState) async throws -> AgentState {
        var newState = state
        newState.variables["condition_result"] = condition(state) ? trueVariable : falseVariable
        return newState
    }
}

struct LoopNode: AgentNode {
    let id: String
    let name: String
    let maxIterations: Int

    func execute(state: AgentState) async throws -> AgentState {
        var newState = state
        if state.iterationCount >= maxIterations {
            newState.shouldContinue = false
            newState.currentStep = "end"
        }
        return newState
    }
}

struct OutputNode: AgentNode {
    let id = "end"
    let name = "Output"
    let outputExtractor: @Sendable (AgentState) -> String

    func execute(state: AgentState) async throws -> AgentState {
        var newState = state
        newState.finalOutput = outputExtractor(state)
        newState.shouldContinue = false
        return newState
    }
}

// MARK: - Parallel Subagents

actor ParallelAgentExecutor {
    static let shared = ParallelAgentExecutor()
    private init() {}

    func executeParallel(
        graphs: [(AgentGraph, AgentState)],
        maxConcurrency: Int = 3
    ) async throws -> [AgentState] {
        let count = graphs.count
        let emptyState = AgentState()

        return try await withThrowingTaskGroup(of: (Int, AgentState).self) { group in
            for (idx, (graph, state)) in graphs.enumerated() {
                if idx >= maxConcurrency { _ = try await group.next() }
                let capturedState = state
                group.addTask {
                    let result = try await graph.execute(initialState: capturedState)
                    return (idx, result)
                }
            }
            var results: [AgentState] = Array(repeating: emptyState, count: count)
            for try await (idx, state) in group {
                results[idx] = state
            }
            return results
        }
    }
}

// MARK: - Workflow Factory

enum WorkflowFactory {
    static func researchWorkflow(providerManager: AIProviderManager, conversation: Conversation) -> AgentGraph {
        let builder = AgentGraph.Builder()
        builder.addNode(ToolNode(id: "search", name: "Buscar na Web", toolName: "web_search",
            inputExtractor: { state in
                let content = state.messageContents.last ?? ""
                return ["query": state.variables["query"] ?? content]
            }))
        builder.addNode(LLMNode(id: "synthesize", name: "Sintetizar",
            systemPrompt: "Sintetize as informações encontradas com fidelidade às fontes e cite-as. Não invente dados: se algo não estiver nas fontes, diga que não foi encontrado em vez de supor.",
            providerManager: providerManager, conversation: conversation))
        builder.addNode(OutputNode { state in state.variables["last_response"] ?? "" })
        builder.addSimpleEdge(from: "search", to: "synthesize")
        builder.addSimpleEdge(from: "synthesize", to: "end")
        builder.entryPoint = "search"
        return builder.build()
    }

    static func codeWorkflow(providerManager: AIProviderManager, conversation: Conversation) -> AgentGraph {
        let builder = AgentGraph.Builder()
        builder.maxIterations = 5
        builder.addNode(LLMNode(id: "generate", name: "Gerar Código",
            systemPrompt: "Gere código limpo e funcional. Não invente APIs, bibliotecas ou funções inexistentes; se não tiver certeza de uma API, sinalize em vez de supor. Não pressuponha arquivos ou contexto que não foram fornecidos.",
            providerManager: providerManager, conversation: conversation))
        builder.addNode(ToolNode(id: "test", name: "Testar", toolName: "run_shell",
            inputExtractor: { state in
                ["command": "echo '\(state.variables["last_response"] ?? "")' | swift -"]
            }))
        builder.addNode(ConditionNode(id: "check", name: "Verificar",
            condition: { state in !(state.toolResults["run_shell"] ?? "").lowercased().contains("error") },
            trueVariable: "end", falseVariable: "fix"))
        builder.addNode(LLMNode(id: "fix", name: "Corrigir",
            systemPrompt: "Corrija os erros no código com base na causa real apontada pela saída do teste. Não invente correções que não se baseiem no erro observado.",
            providerManager: providerManager, conversation: conversation))
        builder.addNode(OutputNode { state in state.variables["last_response"] ?? "" })
        builder.addSimpleEdge(from: "generate", to: "test")
        builder.addSimpleEdge(from: "test", to: "check")
        builder.addEdge(from: "check") { state in state.variables["condition_result"] ?? "end" }
        builder.addSimpleEdge(from: "fix", to: "test")
        builder.entryPoint = "generate"
        return builder.build()
    }
}
