//
//  CodeDashboardView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import SwiftData

// ✅ Notificações para a sidebar disparar as sheets
extension Notification.Name {
    static let openGitPanel = Notification.Name("lume.openGitPanel")
}

struct CodeDashboardView: View {
    let conversations: [Conversation]
    let onSelectConversation: (Conversation) -> Void
    let onNewConversation: () -> Void

    @State private var gitStatus: GitManager.GitStatus? = nil
    @State private var showGitPanel = false

    @State private var workspaceURL: URL? = {
        if let path = UserDefaults.standard.string(forKey: "code_workspace_path") {
            return URL(fileURLWithPath: path)
        }
        return AgentToolExecutor.shared.allowedDirectoriesPublic.first
    }()

    private func persistWorkspace(_ url: URL) {
        workspaceURL = url
        UserDefaults.standard.set(url.path, forKey: "code_workspace_path")
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: "code_workspace_bookmark")
        }
    }

    var body: some View {
        Group {
            if workspaceURL == nil {
                codeWelcomeView
            } else {
                codeDashboard
            }
        }
        // Git é a única ferramenta de painel do Code. Shell, busca e testes o agente
        // já executa via tools — a saída aparece na própria conversa, sem painel à parte.
        .onReceive(NotificationCenter.default.publisher(for: .openGitPanel)) { _ in showGitPanel = true }
        .sheet(isPresented: $showGitPanel) {
            GitPanelView()
        }
    }

    // MARK: - Welcome (sem workspace)

    private var codeWelcomeView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.20, green: 0.60, blue: 1.0),
                                     Color(red: 0.10, green: 0.40, blue: 0.90)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 72, height: 72)
                        .shadow(color: Color(red: 0.20, green: 0.60, blue: 1.0).opacity(0.3), radius: 16, y: 6)
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("Code Agent")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(String(localized: "Write, review, debug, and refactor with AI as your co-pilot.\nTo get started, select your project folder."))
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineSpacing(3)
                }

                VStack(spacing: 8) {
                    Text("What the agent can do:")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 6) {
                        featureRow(icon: "chevron.left.forwardslash.chevron.right", color: Color(red: 0.20, green: 0.60, blue: 1.0), text: String(localized: "Read and edit your project's files"))
                        featureRow(icon: "ant.circle.fill",       color: .red,    text: "Encontrar e corrigir bugs automaticamente")
                        featureRow(icon: "arrow.2.squarepath",    color: .orange, text: String(localized: "Refactor and improve code quality"))
                        featureRow(icon: "testtube.2",            color: .purple, text: String(localized: "Write and run tests"))
                        featureRow(icon: "arrow.triangle.branch", color: .orange, text: String(localized: "View Git status and make commits"))
                        featureRow(icon: "terminal.fill",         color: .green,  text: "Executar comandos no terminal integrado")
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                }
                .frame(maxWidth: 420)

                Button {
                    Task {
                        if let url = await AgentToolExecutor.shared.requestDirectoryAccess() {
                            persistWorkspace(url)
                            gitStatus = await GitManager.shared.status(at: url.path)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 14, weight: .semibold))
                        Text("Select project folder").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.60, blue: 1.0), Color(red: 0.10, green: 0.40, blue: 0.90)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: Color(red: 0.20, green: 0.60, blue: 1.0).opacity(0.3), radius: 8, y: 3)
                }
                .buttonStyle(.plain)

                Text(String(localized: "Access is restricted to the selected folder.\nNo other files on your computer are accessed."))
                    .font(.system(size: 11)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: 480)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Dashboard (com workspace)

    private var codeDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                workspaceSection
                sessionSection
                toolsSection
                recentSessionsSection
            }
            .padding(24)
        }
        .background(Color(.windowBackgroundColor))
        .task {
            if let url = workspaceURL {
                gitStatus = await GitManager.shared.status(at: url.path)
            }
        }
    }

    @ViewBuilder
    private var workspaceSection: some View {
        if let url = workspaceURL {
            VStack(alignment: .leading, spacing: 10) {
                workspaceCard(url: url)
                if let status = gitStatus {
                    gitCompactRow(status: status)
                }
            }
        }
    }

    private func workspaceCard(url: URL) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LumeTheme.moss.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: "folder.fill").font(.system(size: 15)).foregroundStyle(LumeTheme.moss)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent).font(.system(size: 14, weight: .semibold))
                Text(url.path).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 6, height: 6).shadow(color: .green.opacity(0.5), radius: 2)
                Text("Active").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button("Switch") {
                Task {
                    if let newURL = await AgentToolExecutor.shared.requestDirectoryAccess() {
                        persistWorkspace(newURL)
                        gitStatus = await GitManager.shared.status(at: newURL.path)
                    }
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            Button {
                workspaceURL = nil
                gitStatus = nil
                UserDefaults.standard.removeObject(forKey: "code_workspace_path")
            } label: {
                Image(systemName: "xmark.circle").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Remove workspace")
        }
        .padding(12)
        .background(LumeTheme.moss.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LumeTheme.moss.opacity(0.2), lineWidth: 1))
    }

    private func gitCompactRow(status: GitManager.GitStatus) -> some View {
        Button { showGitPanel = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(.orange)
                Text(status.branch).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                if !status.staged.isEmpty { Text("↑\(status.staged.count) staged").font(.system(size: 10)).foregroundStyle(.green) }
                if !status.modified.isEmpty { Text("~\(status.modified.count) modified").font(.system(size: 10)).foregroundStyle(.orange) }
                if status.staged.isEmpty && status.modified.isEmpty { Text("clean").font(.system(size: 10)).foregroundStyle(.green) }
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start a session")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                sessionCard(icon: "chevron.left.forwardslash.chevron.right", title: String(localized: "Write code"),     subtitle: String(localized: "New feature, function, or component"), color: Color(red: 0.20, green: 0.60, blue: 1.0))
                sessionCard(icon: "ant.circle.fill",          title: String(localized: "Debug an error"),      subtitle: "Encontrar e corrigir bugs",          color: .red)
                sessionCard(icon: "arrow.2.squarepath",       title: "Refatorar",          subtitle: "Melhorar qualidade e legibilidade",  color: .orange)
                sessionCard(icon: "testtube.2",               title: String(localized: "Write tests"),    subtitle: "Unit tests e cobertura",             color: .purple)
                sessionCard(icon: "doc.text.magnifyingglass", title: String(localized: "Review code"),     subtitle: String(localized: "Code review with suggestions"),          color: .blue)
                sessionCard(icon: "terminal.fill",            title: String(localized: "Script / automation"), subtitle: String(localized: "Shell, Python, automations"),          color: .green)
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tools").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                toolButton(icon: "arrow.triangle.branch", label: "Git", color: .orange) { showGitPanel = true }
            }
        }
    }

    @ViewBuilder
    private var recentSessionsSection: some View {
        let codeSessions = conversations.filter {
            $0.messages.contains { $0.content.contains("```") || $0.content.contains("func ") || $0.content.contains("def ") }
        }
        if !codeSessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Sessions").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    ForEach(codeSessions.prefix(5)) { conv in
                        Button { onSelectConversation(conv) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 10)).foregroundStyle(Color.accentColor).frame(width: 14)
                                Text(conv.title).font(.system(size: 13)).lineLimit(1).foregroundStyle(.primary)
                                Spacer()
                                Text(conv.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.12)).frame(width: 26, height: 26)
                Image(systemName: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            }
            Text(text).font(.system(size: 12)).foregroundStyle(.primary)
            Spacer()
        }
    }

    private func sessionCard(icon: String, title: String, subtitle: String, color: Color) -> some View {
        Button { onNewConversation() } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.12)).frame(width: 34, height: 34)
                    Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(11)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func toolButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.10)).frame(width: 34, height: 34)
                    Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(color)
                }
                Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Git Panel

struct GitPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status: GitManager.GitStatus? = nil
    @State private var commitMessage = ""
    @State private var isLoading = false
    @State private var output = ""
    @State private var selectedTab = 0

    private var workspacePath: String? {
        UserDefaults.standard.string(forKey: "code_workspace_path")
        ?? AgentToolExecutor.shared.allowedDirectoriesPublic.first?.path
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Git", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                if let branch = status?.branch {
                    Text(branch).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Color.orange.opacity(0.12), in: Capsule())
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(20)

            Divider().opacity(0.4)

            Picker("", selection: $selectedTab) {
                Text("Status").tag(0); Text("Commit").tag(1); Text("Log").tag(2)
            }
            .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 12)

            Divider().opacity(0.4)

            Group {
                switch selectedTab {
                case 0: gitStatusTab
                case 1: gitCommitTab
                case 2: gitLogTab
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 560, height: 480)
        .task {
            if let path = workspacePath { status = await GitManager.shared.status(at: path) }
        }
    }

    private var gitStatusTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let status {
                    if !status.staged.isEmpty    { fileSection(title: "Staged",    files: status.staged,    color: .green,     icon: "plus.circle.fill") }
                    if !status.modified.isEmpty  { fileSection(title: "Modified",  files: status.modified,  color: .orange,    icon: "pencil.circle.fill") }
                    if !status.untracked.isEmpty { fileSection(title: "Untracked", files: status.untracked, color: .secondary, icon: "questionmark.circle.fill") }
                    if status.staged.isEmpty && status.modified.isEmpty && status.untracked.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 32)).foregroundStyle(.green)
                            Text("Working tree clean").font(.headline)
                            Text("No pending changes.").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(40)
                    }
                } else {
                    ProgressView("Loading status…").frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(20)
        }
    }

    private var gitCommitTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Commit message").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                TextEditor(text: $commitMessage).font(.system(size: 13)).frame(height: 80)
                    .scrollContentBackground(.hidden).padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                Button("Stage All") { runGit("add -A") }.buttonStyle(.bordered)
                Button("Commit") {
                    guard !commitMessage.isEmpty else { return }
                    runGit("commit -m \"\(commitMessage)\""); commitMessage = ""
                }.buttonStyle(.borderedProminent).disabled(commitMessage.isEmpty)
                Button("Push") { runGit("push") }.buttonStyle(.bordered)
                Button("Pull") { runGit("pull") }.buttonStyle(.bordered)
            }
            if !output.isEmpty {
                ScrollView {
                    Text(output).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120).padding(10).background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
        }
        .padding(20)
    }

    private var gitLogTab: some View {
        GitLogView(workspacePath: workspacePath ?? "")
    }

    private func fileSection(title: String, files: [String], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                Text("(\(files.count))").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            ForEach(files, id: \.self) { file in
                HStack(spacing: 8) {
                    Image(systemName: fileIconForPath(file)).font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 14)
                    Text(file).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.head)
                }
                .padding(.leading, 18)
            }
        }
    }

    private func runGit(_ command: String) {
        isLoading = true
        Task {
            let result = await AgentToolExecutor.shared.runShell(command: "git \(command)", workingDirectory: workspacePath)
            output = result.output; isLoading = false
            if let path = workspacePath { status = await GitManager.shared.status(at: path) }
        }
    }

    private func fileIconForPath(_ path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift": return "chevron.left.forwardslash.chevron.right"
        case "md":    return "doc.text"
        case "json":  return "curlybraces"
        default:      return "doc"
        }
    }
}

// MARK: - Git Log

struct GitLogView: View {
    let workspacePath: String
    @State private var log = ""
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading log…").frame(maxWidth: .infinity).padding(40)
            } else {
                ScrollView {
                    Text(log).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .textSelection(.enabled)
                }
            }
        }
        .task {
            let result = await AgentToolExecutor.shared.runShell(command: "git log --oneline -30", workingDirectory: workspacePath)
            log = result.output.isEmpty ? String(localized: "No commits yet.") : result.output
            isLoading = false
        }
    }
}

// MARK: - Code Search (inteligente)
