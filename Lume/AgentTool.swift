//
//  AgentTool.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation

// MARK: - Tool Protocol

protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }
    func execute(with input: [String: String]) async throws -> ToolResult
}

// MARK: - Parameter & Result

struct ToolParameter: Sendable {
    let name: String
    let description: String
    let type: String
    let required: Bool
}

struct ToolResult: Sendable {
    let success: Bool
    let output: String
    let metadata: [String: String]
}

// MARK: - Tool Call

struct ToolCall: Identifiable, Sendable {
    let id: String
    let toolName: String
    let input: [String: String]
    var result: ToolResult?
    var state: ToolCallState

    enum ToolCallState: Sendable {
        case pending, running, completed, failed
    }

    init(toolName: String, input: [String: String]) {
        self.id = UUID().uuidString
        self.toolName = toolName
        self.input = input
        self.result = nil
        self.state = .pending
    }
}

// MARK: - Concrete Tools

struct ShellTool: AgentTool {
    let name = "run_shell"
    let description = "Executes a shell command on the user's Mac. Supports pipes, redirection and chaining. You CAN run commands that require root: just prefix with `sudo` — Lume runs them through the native macOS administrator authentication dialog (Touch ID / admin password), so never refuse a privileged command for lack of access. Always attempt the command rather than saying you cannot."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "command", description: "Shell command", type: "string", required: true),
        ToolParameter(name: "working_directory", description: "Working directory", type: "string", required: false)
    ]
    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let command = input["command"] else { return makeFailure("Missing: command") }
        return await AgentToolExecutor.shared.runShell(command: command, workingDirectory: input["working_directory"])
    }
}

struct ReadFileTool: AgentTool {
    let name = "read_file"
    let description = "Reads a file."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "path", description: "File path", type: "string", required: true)
    ]
    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let path = input["path"] else { return makeFailure("Missing: path") }
        return await AgentToolExecutor.shared.readFile(at: path)
    }
}

struct WriteFileTool: AgentTool {
    let name = "write_file"
    let description = "Writes a file."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "path",    description: "File path", type: "string", required: true),
        ToolParameter(name: "content", description: "Content",   type: "string", required: true)
    ]
    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let path = input["path"], let content = input["content"] else {
            return makeFailure("Missing: path, content")
        }
        return await AgentToolExecutor.shared.writeFile(at: path, content: content)
    }
}

struct ListDirectoryTool: AgentTool {
    let name = "list_directory"
    let description = "Lists a directory."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "path", description: "Directory path", type: "string", required: true)
    ]
    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let path = input["path"] else { return makeFailure("Missing: path") }
        return await AgentToolExecutor.shared.listDirectory(at: path)
    }
}

struct CreateDirectoryTool: AgentTool {
    let name = "create_directory"
    let description = "Creates a directory."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "path", description: "Directory path", type: "string", required: true)
    ]
    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let path = input["path"] else { return makeFailure("Missing: path") }
        return await AgentToolExecutor.shared.createDirectory(at: path)
    }
}
