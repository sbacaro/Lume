//
//  TerminalSession.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import Observation
import Security

// MARK: - Terminal Line

struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let type: LineType

    enum LineType {
        case command, output, error, system, sudo
    }
}

// MARK: - Terminal Session

@Observable
final class TerminalSession {
    var lines: [TerminalLine] = []
    var workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    var isSudoSession = false
    var isRunning = false

    private var history: [String] = []
    private var historyIndex: Int = -1
    private var sudoPassword: String? = nil
    private var environment: [String: String] = ProcessInfo.processInfo.environment

    var pendingPasswordContinuation: CheckedContinuation<String?, Never>? = nil
    var isWaitingForPassword = false

    init() {
        appendLine(String(localized: "Lume Terminal — type 'help' for available commands"), type: .system)
        loadHistory()
    }

    // MARK: - Execute

    @MainActor
    func execute(_ rawCommand: String) async {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        addToHistory(command)
        appendLine("\(promptPrefix)\(command)", type: .command)

        if await handleBuiltin(command) { return }

        if command.hasPrefix("sudo") {
            await executeSudo(command)
            return
        }

        if command.hasPrefix("cd ") || command == "cd" {
            handleCd(command)
            return
        }

        isRunning = true
        let wd = workingDirectory
        let result = await Task.detached {
            Shell.run(command: command, workingDirectory: wd)
        }.value
        isRunning = false

        if result.success {
            if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendLine(result.output, type: .output)
            }
        } else {
            appendLine(result.output, type: .error)
        }
    }

    // MARK: - Built-in commands

    @MainActor
    private func handleBuiltin(_ command: String) async -> Bool {
        let parts = command.components(separatedBy: " ").filter { !$0.isEmpty }
        guard let cmd = parts.first else { return false }

        switch cmd {
        case "clear", "cls":
            clear(); return true

        case "cd":
            handleCd(command); return true

        case "help":
            appendLine("""
            Comandos disponíveis:
              clear          Limpa o terminal
              cd <path>      Muda o diretório
              pwd            Mostra o diretório atual
              sudo <cmd>     Executa com privilégios elevados
              sudo -i        Inicia sessão sudo
              sudo --reset   Remove credencial sudo em cache
              env            Lista variáveis de ambiente
              export K=V     Define variável de ambiente
              history        Mostra histórico de comandos
              help           Este menu
            """, type: .system)
            return true

        case "pwd":
            appendLine(workingDirectory, type: .output); return true

        case "history":
            let hist = history.enumerated()
                .map { "  \($0.offset + 1)  \($0.element)" }
                .joined(separator: "\n")
            appendLine(hist.isEmpty ? "(empty)" : hist, type: .output)
            return true

        case "env":
            appendLine(
                environment.sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "\n"),
                type: .output
            )
            return true

        case "export":
            if parts.count >= 2, let eq = parts[1].firstIndex(of: "=") {
                let key   = String(parts[1][..<eq])
                let value = String(parts[1][parts[1].index(after: eq)...])
                environment[key] = value
                appendLine("export \(key)=\(value)", type: .system)
            }
            return true

        default:
            return false
        }
    }

    // MARK: - cd

    private func handleCd(_ command: String) {
        let parts = command.components(separatedBy: " ").filter { !$0.isEmpty }
        let target: String

        if parts.count < 2 || parts[1] == "~" {
            target = FileManager.default.homeDirectoryForCurrentUser.path
        } else if parts[1].hasPrefix("~") {
            target = FileManager.default.homeDirectoryForCurrentUser.path + String(parts[1].dropFirst())
        } else if parts[1].hasPrefix("/") {
            target = parts[1]
        } else {
            target = (workingDirectory as NSString).appendingPathComponent(parts[1])
        }

        let resolved = (target as NSString).standardizingPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue {
            workingDirectory = resolved
        } else {
            appendLine("cd: \(parts.dropFirst().joined(separator: " ")): No such file or directory", type: .error)
        }
    }

    // MARK: - Sudo

    @MainActor
    private func executeSudo(_ command: String) async {
        if command == "sudo --reset" || command == "sudo -k" {
            sudoPassword = nil
            isSudoSession = false
            appendLine("[sudo] Credencial removida do cache.", type: .sudo)
            return
        }
        if command == "sudo -i" {
            if await ensureSudoCredential() {
                isSudoSession = true
                appendLine("[sudo] Sessão privilegiada iniciada.", type: .sudo)
            }
            return
        }
        guard await ensureSudoCredential() else { return }
        let actualCommand = String(command.dropFirst(5))
        appendLine("[sudo] \(actualCommand)", type: .sudo)
        isRunning = true
        let result = await runSudo(command: actualCommand)
        isRunning = false
        if result.success {
            if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendLine(result.output, type: .output)
            }
        } else {
            appendLine(result.output, type: .error)
        }
    }

    @MainActor
    @discardableResult
    private func ensureSudoCredential() async -> Bool {
        if let pwd = sudoPassword {
            let valid = await Task.detached { Shell.sudoTest(password: pwd) }.value
            if valid { return true }
            sudoPassword = nil
            isSudoSession = false
        }
        appendLine("[sudo] Solicitando credenciais de administrador…", type: .sudo)
        let authOK = await Task.detached { Shell.acquireAuthorization() }.value
        guard authOK else {
            appendLine("[sudo] Autorização negada ou cancelada.", type: .error)
            return false
        }
        let password = await promptForPassword()
        guard let pwd = password, !pwd.isEmpty else {
            appendLine("[sudo] Nenhuma senha fornecida.", type: .error)
            return false
        }
        let valid = await Task.detached { Shell.sudoTest(password: pwd) }.value
        guard valid else {
            appendLine("[sudo] Senha incorreta.", type: .error)
            return false
        }
        sudoPassword = pwd
        isSudoSession = true
        appendLine(String(localized: "[sudo] Credential valid and stored in memory."), type: .sudo)
        return true
    }

    private func runSudo(command: String) async -> ToolResult {
        guard let password = sudoPassword else {
            return Shell.failure("[sudo] Sem credencial em cache")
        }
        let wd = workingDirectory
        return await Task.detached {
            Shell.sudoRun(command: command, password: password, workingDirectory: wd)
        }.value
    }

    // MARK: - Password prompt

    @MainActor
    private func promptForPassword() async -> String? {
        await withCheckedContinuation { continuation in
            self.pendingPasswordContinuation = continuation
            NotificationCenter.default.post(name: .terminalNeedsPassword, object: self)
        }
    }

    @MainActor
    func submitPassword(_ password: String?) {
        pendingPasswordContinuation?.resume(returning: password)
        pendingPasswordContinuation = nil
    }

    // MARK: - Autocomplete

    func autocomplete(_ partial: String) -> String {
        let parts = partial.components(separatedBy: " ")
        guard let last = parts.last, !last.isEmpty else { return partial }
        let dir    = last.contains("/") ? URL(fileURLWithPath: last).deletingLastPathComponent().path : workingDirectory
        let prefix = last.contains("/") ? URL(fileURLWithPath: last).lastPathComponent : last
        let items   = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let matches = items.filter { $0.hasPrefix(prefix) }.sorted()
        guard let first = matches.first else { return partial }
        let completion = last.contains("/")
            ? (dir as NSString).appendingPathComponent(first)
            : first
        var newParts = parts
        newParts[newParts.count - 1] = completion
        let fullPath = last.contains("/") ? completion : (workingDirectory as NSString).appendingPathComponent(completion)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
            return newParts.joined(separator: " ") + "/"
        }
        return newParts.joined(separator: " ")
    }

    // MARK: - History

    func previousCommand() -> String? {
        guard !history.isEmpty else { return nil }
        historyIndex = max(0, historyIndex - 1)
        return history.count > historyIndex ? history[history.count - 1 - historyIndex] : nil
    }

    func nextCommand() -> String? {
        guard historyIndex > 0 else { historyIndex = -1; return "" }
        historyIndex -= 1
        return history.count > historyIndex ? history[history.count - 1 - historyIndex] : nil
    }

    private func addToHistory(_ command: String) {
        if history.last != command { history.append(command) }
        if history.count > 500 { history.removeFirst() }
        historyIndex = -1
        saveHistory()
    }

    // MARK: - Persistence

    private var historyURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Lume")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("terminal_history.txt")
    }

    private func saveHistory() {
        try? history.joined(separator: "\n").write(to: historyURL, atomically: true, encoding: .utf8)
    }

    private func loadHistory() {
        guard let text = try? String(contentsOf: historyURL, encoding: .utf8) else { return }
        history = text.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // MARK: - Helpers

    func clear() {
        lines.removeAll()
        appendLine("Lume Terminal", type: .system)
    }

    private func appendLine(_ text: String, type: TerminalLine.LineType) {
        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            lines.append(TerminalLine(text: line, type: type))
        }
        if lines.count > 2000 { lines.removeFirst(lines.count - 2000) }
    }

    private var promptPrefix: String {
        let dir = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return isSudoSession ? "root@lume \(dir) # " : "lume \(dir) $ "
    }
}

extension Notification.Name {
    static let terminalNeedsPassword = Notification.Name("terminalNeedsPassword")
}
