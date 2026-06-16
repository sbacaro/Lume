//
//  GitHubSettingsView.swift
//  Lume
//
//  Configurações → GitHub: conectar com Personal Access Token, listar/criar
//  repositórios, ver issues e pull requests e criar issues.
//

import SwiftUI
import AppKit

struct GitHubSettingsView: View {
    @State private var gh = GitHubService.shared

    // Conexão
    @State private var tokenInput = ""

    // Repos
    @State private var repos: [GHRepo] = []
    @State private var loadingRepos = false
    @State private var repoSearch = ""

    // Detalhe do repo selecionado
    @State private var selectedRepo: GHRepo?
    @State private var issues: [GHIssue] = []
    @State private var prs: [GHPullRequest] = []
    @State private var loadingDetail = false

    // Criar repo
    @State private var newRepoName = ""
    @State private var newRepoDesc = ""
    @State private var newRepoPrivate = false
    @State private var creatingRepo = false

    // Criar issue
    @State private var newIssueTitle = ""
    @State private var newIssueBody = ""
    @State private var creatingIssue = false

    @State private var statusMessage: String?

    private var filteredRepos: [GHRepo] {
        guard !repoSearch.isEmpty else { return repos }
        return repos.filter { $0.fullName.localizedCaseInsensitiveContains(repoSearch) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                accountSection
                if gh.isConnected {
                    createRepoSection
                    reposSection
                    if let repo = selectedRepo {
                        repoDetailSection(repo)
                    }
                }
            }
            .padding(20)
        }
        .task { await gh.bootstrap() }
        .onChange(of: gh.isConnected) { _, connected in
            if connected { Task { await loadRepos() } }
        }
        .onAppear { if gh.isConnected && repos.isEmpty { Task { await loadRepos() } } }
    }

    // MARK: - Conta

    private var accountSection: some View {
        settingsSection("Conta GitHub") {
            if gh.isConnected, let user = gh.user {
                HStack(spacing: 12) {
                    avatar(user.avatarUrl, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name ?? user.login).font(.system(size: 14, weight: .semibold))
                        Text("@\(user.login)").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("\(user.publicRepos ?? 0) públicos · \(user.privateReposOwned ?? 0) privados")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Label("Conectado", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.green)
                        Button("Desconectar") {
                            Task {
                                await gh.disconnect()
                                repos = []; selectedRepo = nil; issues = []; prs = []
                            }
                        }
                        .buttonStyle(.lumeSecondaryCompact)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Cole um Personal Access Token (classic ou fine-grained) com escopo `repo`.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SecureField("ghp_… ou github_pat_…", text: $tokenInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { connect() }
                    HStack {
                        Button(action: connect) {
                            if gh.isValidating {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Conectar")
                            }
                        }
                        .buttonStyle(.lumePrimary)
                        .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty || gh.isValidating)

                        Spacer()
                        Link("Gerar token →",
                             destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=Lume")!)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                    }
                    if let err = gh.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(.system(size: 13))
    }

    // MARK: - Criar repositório

    private var createRepoSection: some View {
        settingsSection("Criar repositório") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("nome-do-repo", text: $newRepoName).textFieldStyle(.roundedBorder)
                TextField("Descrição (opcional)", text: $newRepoDesc).textFieldStyle(.roundedBorder)
                Toggle("Privado", isOn: $newRepoPrivate)
                HStack {
                    Button(action: createRepo) {
                        if creatingRepo { ProgressView().controlSize(.small) } else { Text("Criar") }
                    }
                    .buttonStyle(.lumePrimaryCompact)
                    .disabled(newRepoName.trimmingCharacters(in: .whitespaces).isEmpty || creatingRepo)
                    Spacer()
                }
            }
        }
        .font(.system(size: 13))
    }

    // MARK: - Lista de repositórios

    private var reposSection: some View {
        settingsSection("Repositórios (\(repos.count))") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                    TextField("Buscar…", text: $repoSearch).textFieldStyle(.plain)
                    Button { Task { await loadRepos() } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                if loadingRepos {
                    HStack { ProgressView().controlSize(.small); Text("Carregando…").font(.system(size: 12)).foregroundStyle(.secondary) }
                } else if filteredRepos.isEmpty {
                    Text("Nenhum repositório.").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(filteredRepos.prefix(40)) { repo in
                            repoRow(repo)
                            if repo.id != filteredRepos.prefix(40).last?.id { Divider().opacity(0.3) }
                        }
                    }
                }
            }
        }
        .font(.system(size: 13))
    }

    private func repoRow(_ repo: GHRepo) -> some View {
        Button {
            selectedRepo = repo
            Task { await loadDetail(repo) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed")
                    .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(repo.name).font(.system(size: 13, weight: .medium))
                    if let d = repo.description, !d.isEmpty {
                        Text(d).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if let lang = repo.language {
                    Text(lang).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Label("\(repo.stargazersCount ?? 0)", systemImage: "star")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).labelStyle(.titleAndIcon)
                Button { NSWorkspace.shared.open(URL(string: repo.htmlUrl)!) } label: {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(selectedRepo?.id == repo.id ? Color.accentColor.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detalhe do repo (issues, PRs, nova issue)

    private func repoDetailSection(_ repo: GHRepo) -> some View {
        settingsSection(repo.fullName) {
            VStack(alignment: .leading, spacing: 12) {
                if loadingDetail {
                    HStack { ProgressView().controlSize(.small); Text("Carregando issues e PRs…").font(.system(size: 12)).foregroundStyle(.secondary) }
                } else {
                    // Issues
                    Text("Issues abertas (\(issues.count))").font(.system(size: 12, weight: .semibold))
                    if issues.isEmpty {
                        Text("Nenhuma issue aberta.").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        ForEach(issues.prefix(15)) { issue in
                            itemRow(symbol: "smallcircle.filled.circle", tint: .green,
                                    title: "#\(issue.number) \(issue.title)",
                                    subtitle: "@\(issue.user?.login ?? "?") · \(issue.comments ?? 0) coment.",
                                    url: issue.htmlUrl)
                        }
                    }

                    Divider().opacity(0.3)

                    // PRs
                    Text("Pull requests abertos (\(prs.count))").font(.system(size: 12, weight: .semibold))
                    if prs.isEmpty {
                        Text("Nenhum PR aberto.").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        ForEach(prs.prefix(15)) { pr in
                            itemRow(symbol: "arrow.triangle.branch", tint: .purple,
                                    title: "#\(pr.number) \(pr.title)",
                                    subtitle: "@\(pr.user?.login ?? "?")\((pr.draft ?? false) ? " · rascunho" : "")",
                                    url: pr.htmlUrl)
                        }
                    }

                    Divider().opacity(0.3)

                    // Nova issue
                    Text("Nova issue").font(.system(size: 12, weight: .semibold))
                    TextField("Título", text: $newIssueTitle).textFieldStyle(.roundedBorder)
                    TextField("Descrição (opcional)", text: $newIssueBody, axis: .vertical)
                        .lineLimit(2...5).textFieldStyle(.roundedBorder)
                    HStack {
                        Button(action: { createIssue(in: repo) }) {
                            if creatingIssue { ProgressView().controlSize(.small) } else { Text("Criar issue") }
                        }
                        .buttonStyle(.lumePrimaryCompact)
                        .disabled(newIssueTitle.trimmingCharacters(in: .whitespaces).isEmpty || creatingIssue)
                        Spacer()
                        if let msg = statusMessage {
                            Text(msg).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .font(.system(size: 13))
    }

    private func itemRow(symbol: String, tint: Color, title: String, subtitle: String, url: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12)).lineLimit(1)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { NSWorkspace.shared.open(URL(string: url)!) } label: {
                Image(systemName: "arrow.up.right.square").font(.system(size: 11))
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Avatar

    private func avatar(_ urlString: String?, size: CGFloat) -> some View {
        Group {
            if let s = urlString, let url = URL(string: s) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    // MARK: - Ações

    private func connect() {
        let t = tokenInput
        Task {
            let ok = await gh.connect(token: t)
            if ok { tokenInput = "" }
        }
    }

    private func loadRepos() async {
        loadingRepos = true
        defer { loadingRepos = false }
        do { repos = try await gh.listRepos() }
        catch { statusMessage = (error as? GHError)?.errorDescription ?? error.localizedDescription }
    }

    private func loadDetail(_ repo: GHRepo) async {
        guard let owner = repo.owner?.login else { return }
        loadingDetail = true
        issues = []; prs = []
        defer { loadingDetail = false }
        do {
            issues = try await gh.listIssues(owner: owner, repo: repo.name, state: "open")
            prs = try await gh.listPullRequests(owner: owner, repo: repo.name, state: "open")
        } catch {
            statusMessage = (error as? GHError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func createRepo() {
        creatingRepo = true
        Task {
            defer { creatingRepo = false }
            do {
                let repo = try await gh.createRepo(name: newRepoName.trimmingCharacters(in: .whitespaces),
                                                   description: newRepoDesc, isPrivate: newRepoPrivate)
                newRepoName = ""; newRepoDesc = ""; newRepoPrivate = false
                await loadRepos()
                selectedRepo = repo
            } catch {
                statusMessage = (error as? GHError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func createIssue(in repo: GHRepo) {
        guard let owner = repo.owner?.login else { return }
        creatingIssue = true
        Task {
            defer { creatingIssue = false }
            do {
                _ = try await gh.createIssue(owner: owner, repo: repo.name,
                                             title: newIssueTitle.trimmingCharacters(in: .whitespaces),
                                             body: newIssueBody)
                newIssueTitle = ""; newIssueBody = ""
                statusMessage = "Issue criada ✓"
                await loadDetail(repo)
            } catch {
                statusMessage = (error as? GHError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
