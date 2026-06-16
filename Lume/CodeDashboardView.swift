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
    static let openTerminal    = Notification.Name("lume.openTerminal")
    static let openGitPanel    = Notification.Name("lume.openGitPanel")
    static let openCodeSearch  = Notification.Name("lume.openCodeSearch")
    static let openTestRunner  = Notification.Name("lume.openTestRunner")
    static let openMCPPanel    = Notification.Name("lume.openMCPPanel")
}

struct CodeDashboardView: View {
    let conversations: [Conversation]
    let onSelectConversation: (Conversation) -> Void
    let onNewConversation: () -> Void

    @State private var gitStatus: GitManager.GitStatus? = nil
    @State private var showTerminal = false
    @State private var showGitPanel = false
    @State private var showCodeSearch = false
    @State private var showTestRunner = false
    @State private var showMCPPanel = false

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
        // ✅ Escuta notificações da sidebar
        .onReceive(NotificationCenter.default.publisher(for: .openTerminal))   { _ in showTerminal   = true }
        .onReceive(NotificationCenter.default.publisher(for: .openGitPanel))   { _ in showGitPanel   = true }
        .onReceive(NotificationCenter.default.publisher(for: .openCodeSearch)) { _ in showCodeSearch = true }
        .onReceive(NotificationCenter.default.publisher(for: .openTestRunner)) { _ in showTestRunner = true }
        .onReceive(NotificationCenter.default.publisher(for: .openMCPPanel))   { _ in showMCPPanel   = true }
        .sheet(isPresented: $showTerminal) {
            TerminalSheetView(workingDirectory: workspaceURL?.path)
        }
        .sheet(isPresented: $showGitPanel) {
            GitPanelView()
        }
        .sheet(isPresented: $showCodeSearch) {
            CodeSearchView(workspacePath: workspaceURL?.path)
        }
        .sheet(isPresented: $showTestRunner) {
            TestRunnerView()
        }
        .sheet(isPresented: $showMCPPanel) {
            MCPQuickView()
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
                toolButton(icon: "terminal.fill",            label: "Terminal", color: .green)         { showTerminal   = true }
                toolButton(icon: "arrow.triangle.branch",    label: "Git",      color: .orange)        { showGitPanel   = true }
                toolButton(icon: "doc.text.magnifyingglass", label: String(localized: "Search"),    color: .blue)          { showCodeSearch = true }
                toolButton(icon: "testtube.2",               label: String(localized: "Tests"),   color: .purple)        { showTestRunner = true }
                toolButton(icon: "puzzlepiece.extension",    label: "MCP",      color: LumeTheme.clay) { showMCPPanel   = true }
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

struct CodeSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let workspacePath: String?

    @State private var query = ""
    @State private var results: [CodeSearchResult] = []
    @State private var isSearching = false
    @State private var caseSensitive = false
    @State private var useRegex = false
    @State private var selectedExtensions: Set<String> = ["swift", "py", "js", "ts", "go", "rs", "kt", "java", "md", "json"]
    @State private var showFilters = false
    @State private var selectedResult: CodeSearchResult? = nil

    struct CodeSearchResult: Identifiable {
        let id = UUID()
        let file: String
        let line: Int
        let column: Int
        let content: String
        let matchRange: Range<String.Index>?

        var filename: String { URL(fileURLWithPath: file).lastPathComponent }
        var relativePath: String {
            if let wp = UserDefaults.standard.string(forKey: "code_workspace_path"),
               file.hasPrefix(wp) {
                return String(file.dropFirst(wp.count + 1))
            }
            return file
        }
    }

    private let allExtensions = ["swift", "py", "js", "ts", "go", "rs", "kt", "java", "cpp", "c", "h", "md", "json", "yaml", "sh", "html", "css", "sql", "rb", "php"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Code Search", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                if let path = workspacePath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(20)

            Divider().opacity(0.4)

            // Search bar
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    TextField("Search in code…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onSubmit { performSearch() }
                    if isSearching { ProgressView().scaleEffect(0.7) }
                    Button("Search") { performSearch() }
                        .buttonStyle(.borderedProminent)
                        .disabled(query.isEmpty || workspacePath == nil)

                    // Filtros toggle
                    Button {
                        withAnimation { showFilters.toggle() }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13))
                            .foregroundStyle(showFilters ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Filters")
                }

                // Opções inline
                HStack(spacing: 12) {
                    Toggle("Aa", isOn: $caseSensitive)
                        .toggleStyle(.button)
                        .font(.system(size: 11, weight: .semibold))
                        .help("Match case")

                    Toggle(".*", isOn: $useRegex)
                        .toggleStyle(.button)
                        .font(
                            .system(
                                size: 11,
                                weight: .semibold,
                                design: .monospaced
                            )
                        )
                        .help("Use regular expression")

                    Spacer()

                    if !results.isEmpty {
                        Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))

            // Filtro de extensões
            if showFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Types:")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(allExtensions, id: \.self) { ext in
                            Button {
                                if selectedExtensions.contains(ext) {
                                    selectedExtensions.remove(ext)
                                } else {
                                    selectedExtensions.insert(ext)
                                }
                            } label: {
                                Text(".\(ext)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(selectedExtensions.contains(ext) ? Color.accentColor : Color.secondary)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(
                                        selectedExtensions.contains(ext)
                                            ? Color.accentColor.opacity(0.12)
                                            : Color.primary.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 4)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                }
                .background(Color.primary.opacity(0.02))
                Divider().opacity(0.4)
            }

            Divider().opacity(0.4)

            // Resultados
            if workspacePath == nil {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text("No workspace open").foregroundStyle(.secondary)
                    Text("Select a folder in Code to search.").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty && query.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 36)).foregroundStyle(.tertiary).symbolRenderingMode(.hierarchical)
                    Text("Smart Search").font(.system(size: 15, weight: .semibold))
                    VStack(alignment: .leading, spacing: 6) {
                        searchTip(icon: "textformat.abc", text: String(localized: "Plain text — literal search in code"))
                        searchTip(icon: "chevron.left.forwardslash.chevron.right", text: String(localized: "Enable .* to use regex: func\\s+\\w+"))
                        searchTip(icon: "textformat", text: String(localized: "Enable Aa to match case"))
                        searchTip(icon: "doc.badge.gearshape", text: String(localized: "Filter by file type with the chips"))
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty && !isSearching {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text("No results for \"\(query)\"").foregroundStyle(.secondary)
                    Text("Try different terms or adjust the filters.").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsList
            }
        }
        .frame(width: 700, height: 520)
    }

    private var resultsList: some View {
        // Agrupa por arquivo
        let grouped = Dictionary(grouping: results, by: { $0.relativePath })
        let sortedKeys = grouped.keys.sorted()

        return List {
            ForEach(sortedKeys, id: \.self) { filePath in
                Section {
                    ForEach(grouped[filePath] ?? []) { result in
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: result.file))
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(result.line)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 32, alignment: .trailing)
                                Text(result.content.trimmingCharacters(in: .whitespaces))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: fileIcon(for: filePath))
                            .font(.system(size: 10)).foregroundStyle(Color.accentColor)
                        Text(filePath)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Spacer()
                        Text("\(grouped[filePath]?.count ?? 0)")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func searchTip(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Color.accentColor).frame(width: 16)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func fileIcon(for path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py":    return "chevron.left.forwardslash.chevron.right"
        case "js", "ts": return "globe"
        case "md":    return "doc.text"
        case "json":  return "curlybraces"
        default:      return "doc"
        }
    }

    private func performSearch() {
        guard !query.isEmpty, let path = workspacePath else { return }
        isSearching = true; results = []

        Task {
            // Monta includes de extensões
            let includes = selectedExtensions.map { "--include='*.\($0)'" }.joined(separator: " ")

            // Monta flags grep
            var flags = "-rn"
            if !caseSensitive { flags += "i" }

            let escapedQuery = query.replacingOccurrences(of: "'", with: "'\\''")

            let grepFlag = useRegex ? "-E" : "-F"
            let command = "grep \(flags) \(grepFlag) \(includes) '\(escapedQuery)' . 2>/dev/null | head -200"

            let result = await AgentToolExecutor.shared.runShell(command: command, workingDirectory: path)
            let lines = result.output.components(separatedBy: "\n").filter { !$0.isEmpty }

            results = lines.compactMap { line -> CodeSearchResult? in
                // Formato: ./path/to/file.swift:42:content
                let parts = line.components(separatedBy: ":")
                guard parts.count >= 3 else { return nil }
                let filePath = parts[0].hasPrefix("./") ? path + "/" + String(parts[0].dropFirst(2)) : path + "/" + parts[0]
                let lineNum = Int(parts[1]) ?? 0
                let content = parts.dropFirst(2).joined(separator: ":")
                return CodeSearchResult(file: filePath, line: lineNum, column: 0, content: content, matchRange: nil)
            }

            isSearching = false
        }
    }
}

// MARK: - Test Runner

struct TestRunnerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var output = ""
    @State private var isRunning = false
    @State private var exitCode: Int? = nil

    private var workspacePath: String? {
        UserDefaults.standard.string(forKey: "code_workspace_path")
        ?? AgentToolExecutor.shared.allowedDirectoriesPublic.first?.path
    }

    private var detectedFramework: String {
        guard let path = workspacePath else { return "unknown" }
        let fm = FileManager.default
        if fm.fileExists(atPath: path + "/Package.swift") { return "swift" }
        if fm.fileExists(atPath: path + "/package.json") { return "node" }
        if fm.fileExists(atPath: path + "/pytest.ini") || fm.fileExists(atPath: path + "/setup.py") { return "python" }
        return "unknown"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Test Runner", systemImage: "testtube.2").font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                if let code = exitCode {
                    HStack(spacing: 6) {
                        Circle().fill(code == 0 ? Color.green : Color.red).frame(width: 8, height: 8)
                        Text(code == 0 ? "Passed" : "Failed").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(code == 0 ? .green : .red)
                    }
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(20)

            Divider().opacity(0.4)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Framework detected:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(frameworkLabel).font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                Button { runLint() } label: { Label("Lint", systemImage: "checkmark.seal").font(.system(size: 12)) }
                    .buttonStyle(.bordered).disabled(isRunning || workspacePath == nil)
                Button { runTests() } label: {
                    HStack(spacing: 5) {
                        if isRunning { ProgressView().scaleEffect(0.6) } else { Image(systemName: "play.fill").font(.system(size: 11)) }
                        Text(isRunning ? "Running…" : "Run Tests").font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent).disabled(isRunning || workspacePath == nil)
            }
            .padding(.horizontal, 20).padding(.vertical, 12).background(Color.primary.opacity(0.04))

            Divider().opacity(0.4)

            ScrollView {
                Text(output.isEmpty ? String(localized: "Click 'Run Tests' to start.") : output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(output.isEmpty ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).textSelection(.enabled)
            }
            .background(Color.black.opacity(0.85))
        }
        .frame(width: 600, height: 440)
    }

    private var frameworkLabel: String {
        switch detectedFramework {
        case "swift": return "Swift Package Manager"
        case "node":  return "Node.js / npm"
        case "python": return "Python / pytest"
        default: return String(localized: "Not detected")
        }
    }

    private func runTests() {
        guard let path = workspacePath else { return }
        isRunning = true; output = ""; exitCode = nil
        let cmd: String
        switch detectedFramework {
        case "swift": cmd = "swift test 2>&1"
        case "node":  cmd = "npm test 2>&1"
        case "python": cmd = "python -m pytest 2>&1"
        default: cmd = "echo 'Framework not recognized'"
        }
        Task {
            let r = await AgentToolExecutor.shared.runShell(command: cmd, workingDirectory: path)
            output = r.output; exitCode = r.success ? 0 : 1; isRunning = false
        }
    }

    private func runLint() {
        guard let path = workspacePath else { return }
        isRunning = true; output = ""; exitCode = nil
        let cmd: String
        switch detectedFramework {
        case "swift": cmd = "swiftlint 2>&1 || echo 'swiftlint not installed'"
        case "node":  cmd = "npx eslint . 2>&1 || echo 'eslint not installed'"
        case "python": cmd = "flake8 . 2>&1 || echo 'flake8 not installed'"
        default: cmd = "echo 'Framework not recognized'"
        }
        Task {
            let r = await AgentToolExecutor.shared.runShell(command: cmd, workingDirectory: path)
            output = r.output; exitCode = r.success ? 0 : 1; isRunning = false
        }
    }
}

// MARK: - MCP Quick View

struct MCPQuickView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var connectors: [MCPConnector]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("MCP Connectors", systemImage: "puzzlepiece.extension.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(20)

            Divider().opacity(0.4)

            if connectors.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 36)).foregroundStyle(.tertiary).symbolRenderingMode(.hierarchical)
                    Text("No connector configured").font(.system(size: 14, weight: .medium))
                    Text("Set up MCP connectors in Settings → MCP.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Open Settings") { WindowOpener.shared.openSettings?(); dismiss() }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
            } else {
                List {
                    ForEach(connectors) { connector in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(connector.isEnabled ? LumeTheme.clay.opacity(0.15) : Color.primary.opacity(0.05))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "puzzlepiece.fill").font(.system(size: 14))
                                    .foregroundStyle(connector.isEnabled ? LumeTheme.clay : Color.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connector.name).font(.system(size: 13, weight: .medium))
                                Text(connector.transport == "stdio" ? connector.command : connector.url)
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { connector.isEnabled },
                                set: { connector.isEnabled = $0; try? modelContext.save() }
                            )).labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset).scrollContentBackground(.hidden)
            }
        }
        .frame(width: 480, height: 360)
    }
}
