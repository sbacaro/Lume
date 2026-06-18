//
//  MCPConnector.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import SwiftData

/// Model Context Protocol connector — permite ao agente usar ferramentas externas
/// através de servidores MCP locais ou remotos (stdio ou HTTP/SSE).
@Model
final class MCPConnector {
    var id: String = UUID().uuidString
    var name: String
    var transport: String      // "stdio" | "http"
    var command: String        // para stdio: ex "npx @modelcontextprotocol/server-filesystem"
    var url: String            // para http: ex "http://localhost:3000"
    var isEnabled: Bool = true
    var createdAt: Date = Date()

    init(name: String, transport: String, command: String = "", url: String = "") {
        self.name = name
        self.transport = transport
        self.command = command
        self.url = url
    }
}

/// Runtime manager para conectores MCP ativos.
@Observable
final class MCPManager {
    static let shared = MCPManager()
    var activeConnectors: [MCPConnector] = []
    var runningProcesses: [String: Process] = [:]

    /// Clientes stdio conectados, por id de conector.
    private var clients: [String: MCPClient] = [:]
    /// Endpoints HTTP conectados (id de conector → base URL).
    private var httpEndpoints: [String: String] = [:]
    /// Ferramentas descobertas (conector + descrição), expostas ao agente.
    private(set) var discoveredTools: [DiscoveredTool] = []
    /// Status de conexão por conector (para feedback na UI).
    private(set) var statuses: [String: ConnectorStatus] = [:]

    struct DiscoveredTool: Identifiable {
        let connectorID: String
        let info: MCPToolInfo
        var id: String { "\(connectorID)/\(info.name)" }
    }

    enum ConnectorStatus: Equatable, Sendable {
        case connecting
        case connected(tools: Int)
        case failed(String)
    }

    private init() {}

    // MARK: - Conexão (stdio + HTTP) + descoberta de ferramentas

    /// Conecta os conectores habilitados (stdio ou HTTP) ainda não ativos e
    /// atualiza ferramentas/status. Idempotente — pode ser chamado repetidamente.
    func syncConnectors(_ connectors: [MCPConnector]) async {
        let enabled = connectors.filter { $0.isEnabled }
        let enabledIDs = Set(enabled.map { $0.id })

        // Desconecta o que foi desabilitado/removido (snapshot para iterar com segurança).
        for (id, client) in clients where !enabledIDs.contains(id) {
            await client.stop()
            clients.removeValue(forKey: id)
        }
        httpEndpoints = httpEndpoints.filter { enabledIDs.contains($0.key) }
        discoveredTools.removeAll { !enabledIDs.contains($0.connectorID) }
        statuses = statuses.filter { enabledIDs.contains($0.key) }

        // Conecta os novos.
        for connector in enabled where clients[connector.id] == nil && httpEndpoints[connector.id] == nil {
            statuses[connector.id] = .connecting
            do {
                let tools = try await connect(connector)
                discoveredTools.append(contentsOf: tools.map {
                    DiscoveredTool(connectorID: connector.id, info: $0)
                })
                statuses[connector.id] = .connected(tools: tools.count)
            } catch {
                statuses[connector.id] = .failed(error.localizedDescription)
            }
        }
    }

    /// Conecta um conector e devolve suas ferramentas. Limpa recursos em caso de falha.
    private func connect(_ connector: MCPConnector) async throws -> [MCPToolInfo] {
        switch connector.transport {
        case "http":
            try await MCPHTTP.initialize(baseURL: connector.url)
            let tools = try await MCPHTTP.listTools(baseURL: connector.url)
            httpEndpoints[connector.id] = connector.url
            return tools
        default: // stdio
            let client = MCPClient(connectorID: connector.id)
            do {
                try await client.start(command: connector.command)
                try await client.initialize()
                let tools = try await client.listTools()
                clients[connector.id] = client
                return tools
            } catch {
                await client.stop()
                throw error
            }
        }
    }

    /// Ferramentas MCP no formato do agente.
    func agentTools() -> [any AgentTool] {
        discoveredTools.map { MCPAgentTool(connectorID: $0.connectorID, info: $0.info) }
    }

    /// Executa uma ferramenta MCP com gate de aprovação (reusa o modo do AgentToolExecutor).
    func executeMCPTool(connectorID: String, name: String, input: [String: String]) async -> ToolResult {
        guard clients[connectorID] != nil || httpEndpoints[connectorID] != nil else {
            return ToolResult(success: false, output: "Conector MCP não está conectado.", metadata: [:])
        }
        let detail = input.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
        let approved = await AgentToolExecutor.shared.approveExternalTool(
            name: name, summary: "Ferramenta MCP: \(name)", detail: detail
        )
        guard approved else {
            return ToolResult(success: false, output: "Ação cancelada: o usuário recusou '\(name)'.", metadata: [:])
        }
        do {
            let output: String
            if let client = clients[connectorID] {
                output = try await client.callTool(name: name, arguments: input)
            } else if let url = httpEndpoints[connectorID] {
                output = try await MCPHTTP.callTool(baseURL: url, name: name, arguments: input)
            } else {
                output = "Conector MCP não está conectado."
            }
            return ToolResult(success: true, output: output, metadata: ["mcp": connectorID])
        } catch {
            return ToolResult(success: false, output: error.localizedDescription, metadata: [:])
        }
    }

    // MARK: - Stdio transport

    func startConnector(_ connector: MCPConnector) async throws {
        guard connector.transport == "stdio" else { return }

        let parts = connector.command
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
        guard let executable = parts.first else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = parts
        _ = executable // suppress warning

        let stdin  = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput  = stdin
        process.standardOutput = stdout
        process.standardError  = stderr

        try process.run()
        runningProcesses[connector.id] = process
    }

    func stopConnector(_ connectorID: String) {
        runningProcesses[connectorID]?.terminate()
        runningProcesses.removeValue(forKey: connectorID)
    }

    // MARK: - HTTP transport — list tools

    func fetchTools(from connector: MCPConnector) async throws -> [MCPTool] {
        guard connector.transport == "http",
              let url = URL(string: "\(connector.url)/tools/list") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0",
                                                                         "method": "tools/list",
                                                                         "id": 1])
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(MCPToolsResponse.self, from: data)
        return response.result?.tools ?? []
    }

    // MARK: - Call tool

    func callTool(name: String, arguments: [String: Any], connector: MCPConnector) async throws -> String {
        guard connector.transport == "http",
              let url = URL(string: "\(connector.url)/tools/call") else {
            return "[MCP] stdio tool call not yet implemented"
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments],
            "id": 2
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? [String: Any],
           let content = result["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String {
            return text
        }
        return String(data: data, encoding: .utf8) ?? "[no output]"
    }
}

// MARK: - MCP Types

struct MCPTool: Decodable {
    let name: String
    let description: String?
}

struct MCPToolsResponse: Decodable {
    let result: MCPToolsResult?
}

struct MCPToolsResult: Decodable {
    let tools: [MCPTool]
}
