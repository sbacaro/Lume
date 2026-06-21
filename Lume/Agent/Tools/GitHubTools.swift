//
//  GitHubTools.swift
//  Lume
//
//  Ferramentas do agente para gerenciar o GitHub via API (usa o token salvo em
//  Configurações → GitHub). Delegam ao AgentToolExecutor, que aplica o gate de
//  aprovação nas ações de escrita (criar repo/issue).
//

import Foundation

struct GitHubListReposTool: AgentTool {
    let name = "github_list_repos"
    let description = "Lista os repositórios do GitHub do usuário conectado (nome, descrição, stars, linguagem, branch padrão). Requer GitHub conectado em Configurações."
    let parameters: [ToolParameter] = []
    func execute(with input: [String: String]) async throws -> ToolResult {
        await AgentToolExecutor.shared.githubListRepos()
    }
}

struct GitHubGetRepoTool: AgentTool {
    let name = "github_get_repo"
    let description = "Mostra detalhes de um repositório do GitHub."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "repo", description: "Repositório no formato 'owner/repo' (ou só 'repo' para o usuário conectado)", type: "string", required: true)
    ]
    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let repo = input["repo"], !repo.isEmpty else { return makeFailure("Missing: repo") }
        return await AgentToolExecutor.shared.githubGetRepo(slug: repo)
    }
}

struct GitHubListIssuesTool: AgentTool {
    let name = "github_list_issues"
    let description = "Lista issues de um repositório do GitHub (não inclui pull requests)."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "repo", description: "Repositório 'owner/repo'", type: "string", required: true),
        ToolParameter(name: "state", description: "open, closed ou all (padrão: open)", type: "string", required: false)
    ]
    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let repo = input["repo"], !repo.isEmpty else { return makeFailure("Missing: repo") }
        return await AgentToolExecutor.shared.githubListIssues(slug: repo, state: input["state"] ?? "open")
    }
}

struct GitHubListPRsTool: AgentTool {
    let name = "github_list_prs"
    let description = "Lista pull requests de um repositório do GitHub."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "repo", description: "Repositório 'owner/repo'", type: "string", required: true),
        ToolParameter(name: "state", description: "open, closed ou all (padrão: open)", type: "string", required: false)
    ]
    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let repo = input["repo"], !repo.isEmpty else { return makeFailure("Missing: repo") }
        return await AgentToolExecutor.shared.githubListPRs(slug: repo, state: input["state"] ?? "open")
    }
}

struct GitHubCreateIssueTool: AgentTool {
    let name = "github_create_issue"
    let description = "Cria uma nova issue em um repositório do GitHub. Ação de escrita — pode pedir aprovação do usuário."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "repo", description: "Repositório 'owner/repo'", type: "string", required: true),
        ToolParameter(name: "title", description: "Título da issue", type: "string", required: true),
        ToolParameter(name: "body", description: "Corpo/descrição da issue (Markdown)", type: "string", required: false)
    ]
    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let repo = input["repo"], !repo.isEmpty else { return makeFailure("Missing: repo") }
        guard let title = input["title"], !title.isEmpty else { return makeFailure("Missing: title") }
        return await AgentToolExecutor.shared.githubCreateIssue(slug: repo, title: title, body: input["body"])
    }
}

struct GitHubCreateRepoTool: AgentTool {
    let name = "github_create_repo"
    let description = "Cria um novo repositório no GitHub do usuário conectado. Ação de escrita — pode pedir aprovação do usuário."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "name", description: "Nome do repositório", type: "string", required: true),
        ToolParameter(name: "description", description: "Descrição (opcional)", type: "string", required: false),
        ToolParameter(name: "private", description: "true para privado, false para público (padrão: false)", type: "string", required: false)
    ]
    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let name = input["name"], !name.isEmpty else { return makeFailure("Missing: name") }
        let isPrivate = (input["private"] ?? "false").lowercased() == "true"
        return await AgentToolExecutor.shared.githubCreateRepo(name: name, description: input["description"], isPrivate: isPrivate)
    }
}
