//
//  GitHubService.swift
//  Lume
//
//  Integração com a API REST do GitHub via Personal Access Token (PAT).
//  O token é guardado no KeychainManager (arquivo criptografado AES-GCM),
//  sob o id "github_pat". Cobre: validar conta, listar/criar repos, listar/
//  criar issues e listar pull requests. Usado tanto pela UI (Configurações →
//  GitHub) quanto pelas ferramentas do agente (github_*).
//

import Foundation
import Observation

// MARK: - Modelos

struct GHOwner: Codable, Hashable {
    let login: String
    let avatarUrl: String?
    let htmlUrl: String?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
    }
}

struct GHUser: Codable, Identifiable, Hashable {
    let id: Int
    let login: String
    let name: String?
    let avatarUrl: String?
    let htmlUrl: String?
    let publicRepos: Int?
    let privateReposOwned: Int?

    enum CodingKeys: String, CodingKey {
        case id, login, name
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
        case publicRepos = "public_repos"
        case privateReposOwned = "owned_private_repos"
    }
}

struct GHRepo: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let isPrivate: Bool
    let htmlUrl: String
    let defaultBranch: String?
    let stargazersCount: Int?
    let forksCount: Int?
    let openIssuesCount: Int?
    let language: String?
    let updatedAt: String?
    let owner: GHOwner?

    enum CodingKeys: String, CodingKey {
        case id, name, description, language, owner
        case fullName = "full_name"
        case isPrivate = "private"
        case htmlUrl = "html_url"
        case defaultBranch = "default_branch"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case openIssuesCount = "open_issues_count"
        case updatedAt = "updated_at"
    }
}

struct GHIssue: Codable, Identifiable, Hashable {
    struct PRRef: Codable, Hashable {}   // presença indica que o "issue" é na verdade um PR

    let id: Int
    let number: Int
    let title: String
    let state: String
    let htmlUrl: String
    let body: String?
    let comments: Int?
    let createdAt: String?
    let user: GHOwner?
    let pullRequest: PRRef?

    enum CodingKeys: String, CodingKey {
        case id, number, title, state, body, comments, user
        case htmlUrl = "html_url"
        case createdAt = "created_at"
        case pullRequest = "pull_request"
    }
}

struct GHPullRequest: Codable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let state: String
    let htmlUrl: String
    let draft: Bool?
    let createdAt: String?
    let user: GHOwner?

    enum CodingKeys: String, CodingKey {
        case id, number, title, state, draft, user
        case htmlUrl = "html_url"
        case createdAt = "created_at"
    }
}

enum GHError: LocalizedError {
    case notConnected
    case unauthorized
    case invalidResponse
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConnected:   return String(localized: "GitHub not connected. Add a token in Settings → GitHub.")
        case .unauthorized:   return "Token inválido ou sem permissão (401). Verifique o token e seus escopos."
        case .invalidResponse: return "Resposta inválida do GitHub."
        case .api(let status, let message): return "GitHub (\(status)): \(message)"
        }
    }
}

// MARK: - Serviço

@Observable
@MainActor
final class GitHubService {
    static let shared = GitHubService()
    private static let keychainID = "github_pat"

    private(set) var token: String = ""
    private(set) var user: GHUser?
    /// Repositórios em cache (preenchidos no bootstrap/connect). Servem para
    /// informar o modelo, via system prompt, do que existe — sem custo de tool call.
    private(set) var repos: [GHRepo] = []
    var isValidating = false
    var lastError: String?

    var isConnected: Bool { user != nil && !token.isEmpty }

    private let apiBase = URL(string: "https://api.github.com")!
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Conexão

    /// Carrega o token salvo e valida silenciosamente (chamar no início do app).
    func bootstrap() async {
        let stored = await KeychainManager.shared.retrieveAPIKey(for: Self.keychainID)
        guard !stored.isEmpty else { return }
        token = stored
        do {
            user = try await fetchUser()
            repos = (try? await listRepos()) ?? []
        }
        catch { user = nil; lastError = (error as? GHError)?.errorDescription }
    }

    /// Valida um token, e se OK persiste e marca como conectado.
    @discardableResult
    func connect(token raw: String) async -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { lastError = "Token vazio."; return false }
        isValidating = true
        lastError = nil
        defer { isValidating = false }
        token = t
        do {
            user = try await fetchUser()
            try? await KeychainManager.shared.saveAPIKey(t, for: Self.keychainID)
            repos = (try? await listRepos()) ?? []
            return true
        } catch {
            user = nil
            lastError = (error as? GHError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func disconnect() async {
        token = ""
        user = nil
        repos = []
        lastError = nil
        try? await KeychainManager.shared.deleteAPIKey(for: Self.keychainID)
    }

    /// Bloco injetado no system prompt para que QUALQUER modelo/provider saiba que
    /// o GitHub já está autenticado e use as ferramentas github_* sem pedir token.
    func contextBlock() -> String? {
        guard isConnected, let login = user?.login else { return nil }
        var lines = [
            "## GitHub",
            "Conta conectada: @\(login). Você JÁ está autenticado no GitHub — NÃO peça token, chave, login ou senha ao usuário em hipótese alguma.",
            "Para ações comuns use as ferramentas: github_list_repos, github_get_repo, github_list_issues, github_list_prs, github_create_issue, github_create_repo.",
            "Para QUALQUER outra operação (releases, tags, push, gh CLI, curl à API, git) o token JÁ está disponível no ambiente do shell como $GITHUB_TOKEN e $GH_TOKEN. Use essas variáveis diretamente em scripts (ex.: `gh release create ...`, `curl -H \"Authorization: Bearer $GITHUB_TOKEN\" ...`) — nunca peça o valor do token ao usuário.",
            "Repositórios podem ser referenciados como 'owner/repo' ou apenas 'repo' (assume @\(login) como owner)."
        ]
        if !repos.isEmpty {
            let names = repos.prefix(40).map { $0.fullName }.joined(separator: ", ")
            lines.append("Repositórios do usuário (\(repos.count)): \(names).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Requisição base

    private func request(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        query: [URLQueryItem] = []
    ) async throws -> Data {
        guard !token.isEmpty else { throw GHError.notConnected }
        var comps = URLComponents(
            url: apiBase.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { comps.queryItems = query }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Lume", forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw GHError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw GHError.unauthorized }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw GHError.api(status: http.statusCode, message: message ?? "Erro \(http.statusCode)")
        }
        return data
    }

    private func fetchUser() async throws -> GHUser {
        try decoder.decode(GHUser.self, from: try await request("user"))
    }

    // MARK: - Repositórios

    func listRepos(sort: String = "updated", perPage: Int = 50) async throws -> [GHRepo] {
        let data = try await request("user/repos", query: [
            .init(name: "sort", value: sort),
            .init(name: "per_page", value: "\(min(max(perPage, 1), 100))"),
            .init(name: "affiliation", value: "owner,collaborator,organization_member")
        ])
        return try decoder.decode([GHRepo].self, from: data)
    }

    func getRepo(owner: String, name: String) async throws -> GHRepo {
        try decoder.decode(GHRepo.self, from: try await request("repos/\(owner)/\(name)"))
    }

    func createRepo(name: String, description: String?, isPrivate: Bool, autoInit: Bool = true) async throws -> GHRepo {
        var body: [String: Any] = ["name": name, "private": isPrivate, "auto_init": autoInit]
        if let description, !description.isEmpty { body["description"] = description }
        let data = try await request("user/repos", method: "POST", body: body)
        return try decoder.decode(GHRepo.self, from: data)
    }

    // MARK: - Issues

    func listIssues(owner: String, repo: String, state: String = "open") async throws -> [GHIssue] {
        let data = try await request("repos/\(owner)/\(repo)/issues", query: [
            .init(name: "state", value: state),
            .init(name: "per_page", value: "50")
        ])
        // O endpoint /issues também retorna PRs — filtramos os que têm pull_request.
        return try decoder.decode([GHIssue].self, from: data).filter { $0.pullRequest == nil }
    }

    func createIssue(owner: String, repo: String, title: String, body: String?) async throws -> GHIssue {
        var b: [String: Any] = ["title": title]
        if let body, !body.isEmpty { b["body"] = body }
        let data = try await request("repos/\(owner)/\(repo)/issues", method: "POST", body: b)
        return try decoder.decode(GHIssue.self, from: data)
    }

    // MARK: - Pull Requests

    func listPullRequests(owner: String, repo: String, state: String = "open") async throws -> [GHPullRequest] {
        let data = try await request("repos/\(owner)/\(repo)/pulls", query: [
            .init(name: "state", value: state),
            .init(name: "per_page", value: "50")
        ])
        return try decoder.decode([GHPullRequest].self, from: data)
    }

    // MARK: - Helpers para "owner/repo"

    /// Aceita "owner/repo" ou só "repo" (usa o usuário conectado como owner).
    func splitSlug(_ slug: String) -> (owner: String, repo: String)? {
        let parts = slug.split(separator: "/").map(String.init)
        if parts.count == 2 { return (parts[0], parts[1]) }
        if parts.count == 1, let login = user?.login { return (login, parts[0]) }
        return nil
    }
}
