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
    nonisolated private static let fullPath = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin"

    /// Drena stdout/stderr CONCORRENTEMENTE enquanto o processo roda e só então
    /// espera o término. Sem isso ocorre o deadlock clássico do `Process`: o
    /// buffer do pipe (64 KB) enche, o processo bloqueia esperando alguém ler,
    /// e `waitUntilExit()` nunca retorna — congelando comandos com muita saída
    /// (ex.: `log show`). Aplica timeout (mata o processo) e limita o tamanho do
    /// texto devolvido para não estourar memória.
    nonisolated private static func drain(
        _ process: Process,
        stdout: Pipe,
        stderr: Pipe,
        timeout: TimeInterval = 90
    ) -> (out: String, err: String, timedOut: Bool) {
        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let q = DispatchQueue(label: "lume.shell.read", attributes: .concurrent)
        group.enter()
        q.async {
            let d = stdout.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); outData = d; lock.unlock(); group.leave()
        }
        group.enter()
        q.async {
            let d = stderr.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); errData = d; lock.unlock(); group.leave()
        }
        var timedOut = false
        let killer = DispatchWorkItem {
            if process.isRunning { timedOut = true; process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        process.waitUntilExit()
        killer.cancel()
        group.wait()   // garante que os pipes foram totalmente lidos
        let cap = 200_000   // ~200 KB de texto já é mais que suficiente p/ o modelo
        func text(_ data: Data) -> String {
            var s = String(data: data, encoding: .utf8) ?? ""
            if s.count > cap { s = String(s.prefix(cap)) + "\n…(saída truncada)" }
            return s
        }
        lock.lock(); let o = text(outData); let e = text(errData); lock.unlock()
        return (o, e, timedOut)
    }

    nonisolated static func run(command: String, workingDirectory: String?) -> ToolResult {
        // Comandos com sudo → diálogo nativo de administrador (Touch ID/senha), roda como root.
        if command.range(of: "\\bsudo\\b", options: .regularExpression) != nil {
            return runAdmin(command: command, workingDirectory: workingDirectory)
        }
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
            let (out, err, timedOut) = drain(process, stdout: stdoutPipe, stderr: stderrPipe)
            let output = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
            if timedOut {
                return Shell.failure("Tempo esgotado (90s) — comando interrompido. Saída parcial:\n\(output)")
            }
            return process.terminationStatus == 0
                ? Shell.success(output.isEmpty ? "(no output)" : output, metadata: ["exit_code": "0"])
                : Shell.failure("Exit \(process.terminationStatus): \(output)")
        } catch {
            return Shell.failure("Failed to launch: \(error.localizedDescription)")
        }
    }

    /// Executa um comando como administrador (root) via o diálogo de autenticação
    /// nativo do macOS (Touch ID / senha de admin). Não precisa de senha armazenada.
    /// Usado automaticamente quando o comando contém `sudo`.
    nonisolated static func runAdmin(command: String, workingDirectory: String?) -> ToolResult {
        // `do shell script ... with administrator privileges` já roda como root,
        // então removemos o `sudo` para evitar pedido de senha duplicado em TTY inexistente.
        var cmd = command.replacingOccurrences(
            of: "\\bsudo\\b\\s*", with: "", options: .regularExpression)

        // Diretório de trabalho.
        if let wd = workingDirectory, !wd.isEmpty {
            let safeWD = wd.replacingOccurrences(of: "'", with: "'\\''")
            cmd = "cd '\(safeWD)' && \(cmd)"
        }

        // Injeta PATH para o shell root encontrar binários do Homebrew etc.
        cmd = "export PATH=\(fullPath):$PATH; \(cmd)"

        // Escapa para a string literal do AppleScript (apenas \ e ").
        let escaped = cmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe
        do {
            try process.run()
            let (out, err, timedOut) = drain(process, stdout: stdoutPipe, stderr: stderrPipe)
            let output = [out, err]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            if timedOut {
                return Shell.failure("Tempo esgotado (90s) — comando interrompido. Saída parcial:\n\(output)")
            }
            if process.terminationStatus == 0 {
                return Shell.success(output.isEmpty ? "(no output)" : output,
                                     metadata: ["exit_code": "0", "elevated": "1"])
            }
            // -128 = usuário cancelou o diálogo de autenticação.
            if output.contains("-128") || output.lowercased().contains("user canceled") {
                return Shell.failure("Autenticação de administrador cancelada pelo usuário.")
            }
            return Shell.failure("Exit \(process.terminationStatus): \(output)")
        } catch {
            return Shell.failure("Falha ao executar com privilégios de administrador: \(error.localizedDescription)")
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
        do { try process.run() } catch { return (error.localizedDescription, 1) }
        let (out, err, _) = drain(process, stdout: pipe, stderr: errPipe)
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
