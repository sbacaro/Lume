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

    private static let builtInTools: [any AgentTool] = [
        ShellTool(),
        ReadFileTool(),
        WriteFileTool(),
        ListDirectoryTool(),
        CreateDirectoryTool(),
        WebSearchTool(),
        WebFetchTool(),
        GitHubListReposTool(),
        GitHubGetRepoTool(),
        GitHubListIssuesTool(),
        GitHubListPRsTool(),
        GitHubCreateIssueTool(),
        GitHubCreateRepoTool(),
    ]

    /// Ferramentas nativas + ferramentas descobertas dos servidores MCP conectados.
    /// Como `AnthropicProvider.buildToolDefinitions()` deriva genericamente desta
    /// lista, qualquer ferramenta MCP aparece automaticamente para o modelo.
    var availableTools: [any AgentTool] {
        Self.builtInTools + MCPManager.shared.agentTools()
    }

    private init() {}

    func requestDirectoryAccess() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a folder for the agent to work in")
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

    /// Igual a `execute`, mas para `run_shell` transmite a saída ao vivo via `onStream`
    /// (cada linha de output enquanto o comando roda). Demais ferramentas ignoram o callback.
    func executeStreaming(
        toolName: String,
        input: [String: String],
        onStream: @escaping @Sendable (String) -> Void
    ) async -> ToolResult {
        if toolName == "run_shell", let command = input["command"] {
            return await runShell(command: command,
                                  workingDirectory: input["working_directory"],
                                  onStream: onStream)
        }
        return await execute(toolName: toolName, input: input)
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

    func runShell(
        command: String,
        workingDirectory: String?,
        onStream: (@Sendable (String) -> Void)? = nil
    ) async -> ToolResult {
        // ── SEGURANÇA: exclusão de arquivos ──────────────────────────────
        // Se o comando apaga arquivos, a aprovação do usuário é SEMPRE obrigatória —
        // independentemente do modo de aprovação (não pode ser desativada). A exclusão
        // é redirecionada para a Lixeira do macOS (nunca permanente).
        let isDeletion = Shell.isFileDeletion(command)
        if isDeletion {
            let approved = await ApprovalCoordinator.shared.requestApproval(
                toolName: "delete_file",
                summary: String(localized: "Delete file(s) — moves to Trash"),
                detail: command,
                isDestructive: true
            )
            guard approved else { return cancelledResult("run_shell") }
        } else {
            guard await approveIfNeeded(toolName: "run_shell",
                                        summary: "Executar comando no terminal",
                                        detail: command, isDestructive: true)
            else { return cancelledResult("run_shell") }
        }

        // Disponibiliza o token do GitHub (cadastrado em Configurações → GitHub) para o
        // shell, para que scripts/`gh`/`curl`/`git` autentiquem sem pedir nada ao usuário.
        var extraEnv: [String: String] = [:]
        let ghToken = GitHubService.shared.token
        if !ghToken.isEmpty {
            extraEnv["GITHUB_TOKEN"] = ghToken
            extraEnv["GH_TOKEN"] = ghToken
        }

        return await Task.detached {
            Shell.run(command: command, workingDirectory: workingDirectory,
                      onOutput: onStream, extraEnv: extraEnv,
                      redirectDeletionToTrash: true)
        }.value
    }

    func readFile(at path: String) async -> ToolResult {
        guard await approveIfNeeded(toolName: "read_file",
                                    summary: String(localized: "Read file"),
                                    detail: path, isDestructive: false)
        else { return cancelledResult("read_file") }
        return await Task.detached { Shell.readFile(at: path) }.value
    }

    func writeFile(at path: String, content: String) async -> ToolResult {
        guard await approveIfNeeded(toolName: "write_file",
                                    summary: String(localized: "Write file"),
                                    detail: path + "\n\n" + String(content.prefix(500)),
                                    isDestructive: true)
        else { return cancelledResult("write_file") }
        return await Task.detached { Shell.writeFile(at: path, content: content) }.value
    }

    func listDirectory(at path: String) async -> ToolResult {
        guard await approveIfNeeded(toolName: "list_directory",
                                    summary: "Listar diretório",
                                    detail: path, isDestructive: false)
        else { return cancelledResult("list_directory") }
        return await Task.detached { Shell.listDirectory(at: path) }.value
    }

    func createDirectory(at path: String) async -> ToolResult {
        guard await approveIfNeeded(toolName: "create_directory",
                                    summary: String(localized: "Create directory"),
                                    detail: path, isDestructive: true)
        else { return cancelledResult("create_directory") }
        return await Task.detached { Shell.createDirectory(at: path) }.value
    }

    // MARK: - GitHub

    private func ghFailure(_ error: Error) -> ToolResult {
        ToolResult(success: false,
                   output: (error as? GHError)?.errorDescription ?? error.localizedDescription,
                   metadata: [:])
    }

    func githubListRepos() async -> ToolResult {
        do {
            let repos = try await GitHubService.shared.listRepos()
            guard !repos.isEmpty else {
                return ToolResult(success: true, output: "Nenhum repositório encontrado.", metadata: [:])
            }
            let lines = repos.map { r in
                "• \(r.fullName)\(r.isPrivate ? " [privado]" : "") — \(r.description ?? "sem descrição") "
                + "(★\(r.stargazersCount ?? 0), \(r.language ?? "—"), branch: \(r.defaultBranch ?? "main"))"
            }
            return ToolResult(success: true, output: lines.joined(separator: "\n"),
                              metadata: ["count": "\(repos.count)"])
        } catch { return ghFailure(error) }
    }

    func githubGetRepo(slug: String) async -> ToolResult {
        guard let (owner, name) = GitHubService.shared.splitSlug(slug) else {
            return ToolResult(success: false, output: "Formato inválido. Use 'owner/repo'.", metadata: [:])
        }
        do {
            let r = try await GitHubService.shared.getRepo(owner: owner, name: name)
            let out = """
            \(r.fullName)\(r.isPrivate ? " [privado]" : "")
            Descrição: \(r.description ?? "—")
            Linguagem: \(r.language ?? "—") | ★ \(r.stargazersCount ?? 0) | Forks: \(r.forksCount ?? 0) | Issues abertas: \(r.openIssuesCount ?? 0)
            Branch padrão: \(r.defaultBranch ?? "main")
            URL: \(r.htmlUrl)
            """
            return ToolResult(success: true, output: out, metadata: ["url": r.htmlUrl])
        } catch { return ghFailure(error) }
    }

    func githubListIssues(slug: String, state: String) async -> ToolResult {
        guard let (owner, name) = GitHubService.shared.splitSlug(slug) else {
            return ToolResult(success: false, output: "Formato inválido. Use 'owner/repo'.", metadata: [:])
        }
        do {
            let issues = try await GitHubService.shared.listIssues(owner: owner, repo: name, state: state)
            guard !issues.isEmpty else {
                return ToolResult(success: true, output: "Nenhuma issue \(state).", metadata: [:])
            }
            let lines = issues.map { "#\($0.number) [\($0.state)] \($0.title) — \($0.user?.login ?? "?") (\($0.comments ?? 0) coment.)\n  \($0.htmlUrl)" }
            return ToolResult(success: true, output: lines.joined(separator: "\n"),
                              metadata: ["count": "\(issues.count)"])
        } catch { return ghFailure(error) }
    }

    func githubListPRs(slug: String, state: String) async -> ToolResult {
        guard let (owner, name) = GitHubService.shared.splitSlug(slug) else {
            return ToolResult(success: false, output: "Formato inválido. Use 'owner/repo'.", metadata: [:])
        }
        do {
            let prs = try await GitHubService.shared.listPullRequests(owner: owner, repo: name, state: state)
            guard !prs.isEmpty else {
                return ToolResult(success: true, output: "Nenhum pull request \(state).", metadata: [:])
            }
            let lines = prs.map { "#\($0.number) [\($0.state)\(($0.draft ?? false) ? "/draft" : "")] \($0.title) — \($0.user?.login ?? "?")\n  \($0.htmlUrl)" }
            return ToolResult(success: true, output: lines.joined(separator: "\n"),
                              metadata: ["count": "\(prs.count)"])
        } catch { return ghFailure(error) }
    }

    func githubCreateIssue(slug: String, title: String, body: String?) async -> ToolResult {
        guard let (owner, name) = GitHubService.shared.splitSlug(slug) else {
            return ToolResult(success: false, output: "Formato inválido. Use 'owner/repo'.", metadata: [:])
        }
        guard await approveIfNeeded(toolName: "github_create_issue",
                                    summary: String(localized: "Create GitHub issue"),
                                    detail: "\(owner)/\(name): \(title)", isDestructive: true)
        else { return cancelledResult("github_create_issue") }
        do {
            let issue = try await GitHubService.shared.createIssue(owner: owner, repo: name, title: title, body: body)
            return ToolResult(success: true,
                              output: "Issue criada: #\(issue.number) \(issue.title)\n\(issue.htmlUrl)",
                              metadata: ["url": issue.htmlUrl, "number": "\(issue.number)"])
        } catch { return ghFailure(error) }
    }

    func githubCreateRepo(name: String, description: String?, isPrivate: Bool) async -> ToolResult {
        guard await approveIfNeeded(toolName: "github_create_repo",
                                    summary: String(localized: "Create GitHub repository"),
                                    detail: "\(name)\(isPrivate ? " (privado)" : " (público)")", isDestructive: true)
        else { return cancelledResult("github_create_repo") }
        do {
            let repo = try await GitHubService.shared.createRepo(name: name, description: description, isPrivate: isPrivate)
            return ToolResult(success: true,
                              output: "Repositório criado: \(repo.fullName)\n\(repo.htmlUrl)",
                              metadata: ["url": repo.htmlUrl])
        } catch { return ghFailure(error) }
    }

    // MARK: - Approval Gate

    /// Gate de aprovação para ferramentas externas (MCP). Trata como destrutivo
    /// por precaução — em modo `supervised` pede confirmação; em `strict`, sempre.
    func approveExternalTool(name: String, summary: String, detail: String) async -> Bool {
        await approveIfNeeded(toolName: name, summary: summary, detail: detail, isDestructive: true)
    }

    /// Decide se a ação precisa de aprovação (conforme o modo) e, se precisar,
    /// suspende até o usuário aprovar/recusar.
    private func approveIfNeeded(
        toolName: String,
        summary: String,
        detail: String,
        isDestructive: Bool
    ) async -> Bool {
        let mode = LumeConfig.load().approvalMode
        let needs: Bool
        switch mode {
        case .autonomous: needs = false
        case .supervised: needs = isDestructive
        case .strict:     needs = true
        }
        guard needs else { return true }
        return await ApprovalCoordinator.shared.requestApproval(
            toolName: toolName, summary: summary, detail: detail, isDestructive: isDestructive
        )
    }

    private func cancelledResult(_ toolName: String) -> ToolResult {
        ToolResult(
            success: false,
            output: "Ação cancelada: o usuário recusou a execução de '\(toolName)'.",
            metadata: [:]
        )
    }
}
