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

    /// Timeout de INATIVIDADE (s): o processo só é interrompido se ficar este tempo
    /// SEM produzir nenhuma saída (stdout/stderr). Enquanto está "rolando" — gerando
    /// output — roda o tempo que precisar (builds longos: `xcodebuild`, `pkgbuild`,
    /// `productbuild`, `codesign`, `notarytool`). O relógio reinicia a cada saída.
    /// Serve apenas para matar processos travados de verdade. Ajustável globalmente.
    nonisolated(unsafe) static var idleTimeout: TimeInterval = 300

    // MARK: - Segurança: exclusão de arquivos → Lixeira (nunca permanente)

    /// Detecta se o comando tenta apagar arquivos/pastas. Usado para FORÇAR aprovação
    /// do usuário (ação de segurança, não desativável por nenhum modo de aprovação).
    nonisolated static func isFileDeletion(_ command: String) -> Bool {
        let patterns = [
            "\\brm\\b", "\\brmdir\\b", "\\bunlink\\b",
            "/bin/rm\\b", "/usr/bin/unlink\\b",
            "\\bshred\\b", "\\bsrm\\b",
            "-delete\\b",            // find ... -delete
            "git\\s+clean\\b"        // git clean -f remove arquivos não rastreados
        ]
        return patterns.contains { command.range(of: $0, options: .regularExpression) != nil }
    }

    /// Prelúdio injetado nos comandos do AGENTE: redefine rm/rmdir/unlink para mover à
    /// Lixeira do macOS em vez de apagar. Finder é o método primário (preserva "Colocar
    /// de volta"); `mv` para ~/.Trash é o fallback. Flags (que começam com `-`) são ignoradas.
    nonisolated private static let trashPrelude: String =
        "__lume_trash() { for f in \"$@\"; do [ \"${f#-}\" != \"$f\" ] && continue; { [ -e \"$f\" ] || [ -L \"$f\" ]; } || continue; case \"$f\" in /*) a=\"$f\";; *) a=\"$PWD/$f\";; esac; /usr/bin/osascript -e \"tell application \\\"Finder\\\" to delete (POSIX file \\\"$a\\\")\" >/dev/null 2>&1 || { mkdir -p \"$HOME/.Trash\"; /bin/mv -f \"$a\" \"$HOME/.Trash/\" 2>/dev/null; }; done; }\n"
        + "rm() { __lume_trash \"$@\"; }\n"
        + "rmdir() { __lume_trash \"$@\"; }\n"
        + "unlink() { __lume_trash \"$@\"; }\n"

    /// Aplica o redirecionamento para a Lixeira a um comando: reescreve `rm` absoluto
    /// para a função e injeta o prelúdio.
    nonisolated private static func applyTrashRedirect(_ command: String) -> String {
        let rewritten = command
            .replacingOccurrences(of: "/usr/bin/rm", with: "rm")
            .replacingOccurrences(of: "/bin/rm", with: "rm")
        return trashPrelude + rewritten
    }

    /// Drena stdout/stderr INCREMENTALMENTE enquanto o processo roda, acompanhando-o:
    /// cada pedaço de saída atualiza `lastActivity`. Um watchdog só termina o processo
    /// se ele ficar `idleTimeout` segundos sem produzir nada (travado). Sem essa drenagem
    /// concorrente ocorreria o deadlock clássico do `Process` (buffer de pipe de 64 KB
    /// enche, processo bloqueia, `waitUntilExit()` nunca retorna). Limita o texto
    /// devolvido para não estourar memória.
    nonisolated private static func drain(
        _ process: Process,
        stdout: Pipe,
        stderr: Pipe,
        idleTimeout: TimeInterval = Shell.idleTimeout,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) -> (out: String, err: String, timedOut: Bool) {
        // Estado mutável compartilhado entre os handlers concorrentes (readability
        // handlers e watchdog). Encapsulado num tipo de referência protegido pelo
        // `lock`, para que os closures @Sendable capturem uma referência constante
        // em vez de mutar `var`s capturadas (erro no modo Swift 6).
        final class DrainState: @unchecked Sendable {
            var outData = Data()
            var errData = Data()
            var lastActivity = Date()
            var lastEmit = Date.distantPast
            var idleKilled = false
        }
        let lock = NSLock()
        let state = DrainState()
        let cap = 200_000   // ~200 KB de texto já é mais que suficiente p/ o modelo

        // Emite ao vivo a última linha de saída (no máx. ~10x/s) para a UI acompanhar
        // o processo em tempo real, sem inundar a interface.
        let emitLive: @Sendable (Data) -> Void = { d in
            guard let onOutput else { return }
            lock.lock()
            let due = Date().timeIntervalSince(state.lastEmit) >= 0.1
            if due { state.lastEmit = Date() }
            lock.unlock()
            guard due, let s = String(data: d, encoding: .utf8) else { return }
            let lastLine = s.split(whereSeparator: { $0.isNewline }).last.map(String.init) ?? ""
            let clean = lastLine
                .replacingOccurrences(of: "]]", with: "] ]")
                .trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty { onOutput(String(clean.prefix(160))) }
        }

        // Leitura incremental: cada chunk reinicia o relógio de inatividade e atualiza
        // o status ao vivo.
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            guard !d.isEmpty else { return }
            lock.lock(); state.outData.append(d); state.lastActivity = Date(); lock.unlock()
            emitLive(d)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            guard !d.isEmpty else { return }
            lock.lock(); state.errData.append(d); state.lastActivity = Date(); lock.unlock()
            emitLive(d)
        }

        // Watchdog: verifica periodicamente; só mata se ficou MUDO por idleTimeout.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "lume.shell.watchdog"))
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler {
            lock.lock(); let idle = Date().timeIntervalSince(state.lastActivity); lock.unlock()
            if process.isRunning && idle > idleTimeout {
                lock.lock(); state.idleKilled = true; lock.unlock()
                process.terminate()
            }
        }
        timer.resume()

        process.waitUntilExit()
        timer.cancel()

        // Encerra os handlers e captura qualquer saída remanescente no buffer.
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        let restOut = stdout.fileHandleForReading.readDataToEndOfFile()
        let restErr = stderr.fileHandleForReading.readDataToEndOfFile()

        func text(_ data: Data) -> String {
            var s = String(data: data, encoding: .utf8) ?? ""
            if s.count > cap { s = String(s.prefix(cap)) + "\n…(saída truncada)" }
            return s
        }
        lock.lock()
        state.outData.append(restOut); state.errData.append(restErr)
        let o = text(state.outData); let e = text(state.errData); let killed = state.idleKilled
        lock.unlock()
        return (o, e, killed)
    }

    nonisolated static func run(
        command: String,
        workingDirectory: String?,
        onOutput: (@Sendable (String) -> Void)? = nil,
        extraEnv: [String: String] = [:],
        redirectDeletionToTrash: Bool = false
    ) -> ToolResult {
        // Comandos com sudo → diálogo nativo de administrador (Touch ID/senha), roda como root.
        if command.range(of: "\\bsudo\\b", options: .regularExpression) != nil {
            return runAdmin(command: command, workingDirectory: workingDirectory,
                            onOutput: onOutput, extraEnv: extraEnv,
                            redirectDeletionToTrash: redirectDeletionToTrash)
        }
        // Segurança: exclusões vão para a Lixeira (rm/rmdir/unlink → mover ao Trash).
        let effectiveCommand = redirectDeletionToTrash ? applyTrashRedirect(command) : command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", effectiveCommand]
        // ✅ Injeta PATH completo + variáveis extras (ex.: GITHUB_TOKEN/GH_TOKEN).
        // No env do processo (não na linha de comando) — não aparece em `ps`.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = fullPath
        for (k, v) in extraEnv { env[k] = v }
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
            let (out, err, timedOut) = drain(process, stdout: stdoutPipe, stderr: stderrPipe, onOutput: onOutput)
            let output = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
            if timedOut {
                return Shell.failure("Processo sem saída por \(Int(Shell.idleTimeout))s (aparentemente travado) — interrompido. Saída parcial:\n\(output)")
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
    nonisolated static func runAdmin(
        command: String,
        workingDirectory: String?,
        onOutput: (@Sendable (String) -> Void)? = nil,
        extraEnv: [String: String] = [:],
        redirectDeletionToTrash: Bool = false
    ) -> ToolResult {
        // `do shell script ... with administrator privileges` já roda como root,
        // então removemos o `sudo` para evitar pedido de senha duplicado em TTY inexistente.
        var cmd = command.replacingOccurrences(
            of: "\\bsudo\\b\\s*", with: "", options: .regularExpression)

        // Diretório de trabalho.
        if let wd = workingDirectory, !wd.isEmpty {
            let safeWD = wd.replacingOccurrences(of: "'", with: "'\\''")
            cmd = "cd '\(safeWD)' && \(cmd)"
        }

        // Injeta PATH + variáveis extras (ex.: GITHUB_TOKEN/GH_TOKEN) para o shell root.
        var prefix = "export PATH=\(fullPath):$PATH; "
        for (k, v) in extraEnv {
            let safeV = v.replacingOccurrences(of: "'", with: "'\\''")
            prefix += "export \(k)='\(safeV)'; "
        }
        cmd = prefix + cmd

        // Segurança: exclusões vão para a Lixeira mesmo em comandos com privilégios.
        if redirectDeletionToTrash { cmd = applyTrashRedirect(cmd) }

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
            let (out, err, timedOut) = drain(process, stdout: stdoutPipe, stderr: stderrPipe, onOutput: onOutput)
            let output = [out, err]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            if timedOut {
                return Shell.failure("Processo sem saída por \(Int(Shell.idleTimeout))s (aparentemente travado) — interrompido. Saída parcial:\n\(output)")
            }
            if process.terminationStatus == 0 {
                return Shell.success(output.isEmpty ? "(no output)" : output,
                                     metadata: ["exit_code": "0", "elevated": "1"])
            }
            // -128 = usuário cancelou o diálogo de autenticação.
            if output.contains("-128") || output.lowercased().contains("user canceled") {
                return Shell.failure(String(localized: "Administrator authentication cancelled by the user."))
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
