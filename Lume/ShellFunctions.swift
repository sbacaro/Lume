//
//  ShellFunctions.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import Security

// MARK: - Shell namespace

enum Shell {

    // PATH completo para garantir que git, swift, npm etc sejam encontrados
    private static let fullPath = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin"

    nonisolated static func run(command: String, workingDirectory: String?) -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        // ✅ Injeta PATH completo
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = fullPath
        process.environment = env
        if let wd = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: wd)
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            return process.terminationStatus == 0
                ? Shell.success(output.isEmpty ? "(no output)" : output, metadata: ["exit_code": "0"])
                : Shell.failure("Exit \(process.terminationStatus): \(output)")
        } catch {
            return Shell.failure("Failed to launch: \(error.localizedDescription)")
        }
    }

    nonisolated static func readFile(at path: String) -> ToolResult {
        do {
            let content = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            return Shell.success(content, metadata: [
                "lines": "\(content.components(separatedBy: "\n").count)",
                "path": path
            ])
        } catch {
            return Shell.failure("Cannot read \(path): \(error.localizedDescription)")
        }
    }

    nonisolated static func writeFile(at path: String, content: String) -> ToolResult {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            return Shell.success("Written to \(path)", metadata: ["path": path])
        } catch {
            return Shell.failure("Cannot write \(path): \(error.localizedDescription)")
        }
    }

    nonisolated static func listDirectory(at path: String) -> ToolResult {
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let lines = items
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { item -> String in
                    let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    return isDir ? "📁 \(item.lastPathComponent)/" : "📄 \(item.lastPathComponent)"
                }
            return Shell.success(lines.joined(separator: "\n"), metadata: ["count": "\(items.count)"])
        } catch {
            return Shell.failure("Cannot list \(path): \(error.localizedDescription)")
        }
    }

    nonisolated static func createDirectory(at path: String) -> ToolResult {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return Shell.success("Directory created at \(path)")
        } catch {
            return Shell.failure("Cannot create \(path): \(error.localizedDescription)")
        }
    }

    // MARK: - Sudo

    nonisolated static func sudoTest(password: String) -> Bool {
        Shell.sudoRun(command: "-v", password: password, workingDirectory: nil).success
    }

    nonisolated static func sudoRun(command: String, password: String, workingDirectory: String?) -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-S", "-p", ""] + command
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
        if let wd = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: wd)
        }
        let stdinPipe  = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput  = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe
        do {
            try process.run()
            if let data = (password + "\n").data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let output = [stdout, stderr]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            return process.terminationStatus == 0
                ? Shell.success(output.isEmpty ? "(no output)" : output, metadata: ["exit_code": "0"])
                : Shell.failure("Exit \(process.terminationStatus): \(output)")
        } catch {
            return Shell.failure("Failed to run sudo: \(error.localizedDescription)")
        }
    }

    nonisolated static func acquireAuthorization() -> Bool {
        var authRef: AuthorizationRef?
        var rights = AuthorizationRights(count: 0, items: nil)
        let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]
        let status = AuthorizationCreate(&rights, nil, flags, &authRef)
        if let ref = authRef { AuthorizationFree(ref, []) }
        return status == errAuthorizationSuccess
    }

    // MARK: - Git ✅ PATH injetado

    nonisolated static func git(_ command: String) -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        // ✅ Injeta PATH para garantir que git seja encontrado
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = fullPath
        process.environment = env
        let pipe    = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = errPipe
        try? process.run()
        process.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),    encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (out.isEmpty ? err : out, process.terminationStatus)
    }

    // MARK: - ToolResult factories

    nonisolated static func success(_ output: String, metadata: [String: String] = [:]) -> ToolResult {
        ToolResult(success: true, output: output, metadata: metadata)
    }

    nonisolated static func failure(_ error: String) -> ToolResult {
        ToolResult(success: false, output: error, metadata: [:])
    }
}

// MARK: - Legacy free function aliases

func shellRun(command: String, workingDirectory: String?) -> ToolResult { Shell.run(command: command, workingDirectory: workingDirectory) }
func shellReadFile(at path: String) -> ToolResult { Shell.readFile(at: path) }
func shellWriteFile(at path: String, content: String) -> ToolResult { Shell.writeFile(at: path, content: content) }
func shellListDirectory(at path: String) -> ToolResult { Shell.listDirectory(at: path) }
func shellCreateDirectory(at path: String) -> ToolResult { Shell.createDirectory(at: path) }
func sudoTest(password: String) -> Bool { Shell.sudoTest(password: password) }
func sudoRun(command: String, password: String, workingDirectory: String?) -> ToolResult { Shell.sudoRun(command: command, password: password, workingDirectory: workingDirectory) }
func acquireAuthorization() -> Bool { Shell.acquireAuthorization() }
func gitRun(_ command: String) -> (output: String, exitCode: Int32) { Shell.git(command) }
func makeSuccess(_ output: String, metadata: [String: String] = [:]) -> ToolResult { Shell.success(output, metadata: metadata) }
func makeFailure(_ error: String) -> ToolResult { Shell.failure(error) }
