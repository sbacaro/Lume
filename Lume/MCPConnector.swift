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

    private init() {}

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
