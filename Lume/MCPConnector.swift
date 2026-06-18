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
    /// Ferramentas descobertas (conector + descrição), expostas ao agente.
    private(set) var discoveredTools: [DiscoveredTool] = []

    struct DiscoveredTool: Identifiable {
        let connectorID: String
        let info: MCPToolInfo
        var id: String { "\(connectorID)/\(info.name)" }
    }

    private init() {}

    // MARK: - Conexão (stdio) + descoberta de ferramentas

    /// Conecta os conectores stdio habilitados que ainda não estão ativos e
    /// atualiza a lista de ferramentas descobertas. Idempotente.
    func syncConnectors(_ connectors: [MCPConnector]) async {
        // Desconecta os que foram desabilitados/removidos (itera sobre um snapshot).
        let enabledIDs = Set(connectors.filter { $0.isEnabled && $0.transport == "stdio" }.map { $0.id })
        let toRemove = clients.filter { !enabledIDs.contains($0.key) }
        for (id, client) in toRemove {
            await client.stop()
            clients.removeValue(forKey: id)
            discoveredTools.removeAll { $0.connectorID == id }
        }
        // Conecta os novos.
        for connector in connectors where connector.isEnabled && connector.transport == "stdio" {
            guard clients[connector.id] == nil else { continue }
            let client = MCPClient(connectorID: connector.id)
            do {
                try await client.start(command: connector.command)
                try await client.initialize()
                let tools = try await client.listTools()
                clients[connector.id] = client
                discoveredTools.append(contentsOf: tools.map {
                    DiscoveredTool(connectorID: connector.id, info: $0)
                })
            } catch {
                await client.stop()
            }
        }
    }

    /// Ferramentas MCP no formato do agente.
    func agentTools() -> [any AgentTool] {
        discoveredTools.map { MCPAgentTool(connectorID: $0.connectorID, info: $0.info) }
    }

    /// Executa uma ferramenta MCP com gate de aprovação (reusa o modo do AgentToolExecutor).
    func executeMCPTool(connectorID: String, name: String, input: [String: String]) async -> ToolResult {
        guard let client = clients[connectorID] else {
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
            let output = try await client.callTool(name: name, arguments: input.mapValues { $0 as Any })
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
