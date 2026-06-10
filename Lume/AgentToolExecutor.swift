//
//  AgentToolExecutor.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import AppKit

@MainActor
final class AgentToolExecutor {
    static let shared = AgentToolExecutor()

    private(set) var allowedDirectories: Set<URL> = []
    var allowedDirectoriesPublic: Set<URL> { allowedDirectories }
    var requireShellConfirmation = true

    let availableTools: [any AgentTool] = [
        ShellTool(),
        ReadFileTool(),
        WriteFileTool(),
        ListDirectoryTool(),
        CreateDirectoryTool(),
        WebSearchTool(),
        WebFetchTool(),
    ]

    private init() {}

    func requestDirectoryAccess() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Escolha uma pasta para o agente trabalhar"
        panel.prompt = "Permitir Acesso"
        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
        if response == .OK, let url = panel.url {
            allowedDirectories.insert(url)
            return url
        }
        return nil
    }

    func isPathAllowed(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardized
        return allowedDirectories.contains(where: { url.path.hasPrefix($0.standardized.path) })
    }

    func execute(toolName: String, input: [String: String]) async -> ToolResult {
        guard let tool = availableTools.first(where: { $0.name == toolName }) else {
            return ToolResult(success: false, output: "Ferramenta '\(toolName)' não encontrada.", metadata: [:])
        }
        return (try? await tool.execute(with: input))
            ?? ToolResult(success: false, output: "Erro ao executar '\(toolName)'.", metadata: [:])
    }

    func webSearch(query: String, maxResults: Int = 5) async -> ToolResult {
        let tool = WebSearchTool()
        return (try? await tool.execute(with: ["query": query, "max_results": "\(maxResults)"]))
            ?? ToolResult(success: false, output: "Erro na busca.", metadata: [:])
    }

    func webFetch(url: String, maxChars: Int = 8000) async -> ToolResult {
        let tool = WebFetchTool()
        return (try? await tool.execute(with: ["url": url, "max_chars": "\(maxChars)"]))
            ?? ToolResult(success: false, output: "Erro ao acessar URL.", metadata: [:])
    }

    func runShell(command: String, workingDirectory: String?) async -> ToolResult {
        await Task.detached { Shell.run(command: command, workingDirectory: workingDirectory) }.value
    }

    func readFile(at path: String) async -> ToolResult {
        await Task.detached { Shell.readFile(at: path) }.value
    }

    func writeFile(at path: String, content: String) async -> ToolResult {
        await Task.detached { Shell.writeFile(at: path, content: content) }.value
    }

    func listDirectory(at path: String) async -> ToolResult {
        await Task.detached { Shell.listDirectory(at: path) }.value
    }

    func createDirectory(at path: String) async -> ToolResult {
        await Task.detached { Shell.createDirectory(at: path) }.value
    }
}
