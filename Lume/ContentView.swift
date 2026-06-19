//
//  ContentView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.lumeConfig) private var config
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var allConversations: [Conversation]
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @State private var providerManager = AIProviderManager.shared
    @Query(filter: #Predicate<AIProviderConfig> { $0.isActive }) private var activeConfigs: [AIProviderConfig]
    private var activeConfig: AIProviderConfig? { activeConfigs.first }

    @State private var selectedConversation: Conversation? = nil
    @State private var selectedProject: Project? = nil
    @State private var sidebarMode: SidebarMode = .chat
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var renamingConversation: Conversation? = nil
    @State private var expandedProjects: Set<String> = []
    @State private var updateManager = UpdateManager.shared
    @EnvironmentObject private var sparkle: SparkleUpdater
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "lume_onboarding_completed")
    @State private var showNewProject = false
    @State private var showCommandPalette = false
    @AppStorage(ThemeKeys.accent) private var accentRaw = AccentChoice.clay.rawValue
    @AppStorage(ThemeKeys.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 520, ideal: 580, max: 660)
                .toolbar(removing: .title)
                .toolbarBackground(.hidden, for: .windowToolbar)
        } detail: {
            detailView
                .navigationTitle("")
                .toolbar(removing: .title)
                .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await loadActiveProvider()
            await GitHubService.shared.bootstrap()
            WindowOpener.shared.openNewProject = { showNewProject = true }
            TaskScheduler.shared.onTaskFired = { task in
                if let conv = allConversations.first(where: { $0.id == task.conversationID }) {
                    Task { try? await providerManager.streamMessage(content: task.prompt, conversation: conv) }
                }
            }
            // Detecta atualizações (GitHub) para exibir o popup na sidebar.
            // O download/instalação em si é feito pelo Sparkle ao tocar no popup.
            await updateManager.checkForUpdates()
        }
        .sheet(item: $renamingConversation) { conv in
            RenameConversationSheet(conversation: conv, initialName: conv.title) { renamingConversation = nil }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environment(\.modelContext, modelContext)
                .onDisappear { Task { await loadActiveProvider() } }
        }
        // ✅ Sheet de Novo Projeto com modelContext correto
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet()
                .environment(\.modelContext, modelContext)
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(
                conversations: allConversations,
                onSelectConversation: { conv in
                    selectedConversation = conv
                    selectedProject = conv.project
                    if conv.tags.contains("code") { sidebarMode = .code }
                    else if conv.project != nil { sidebarMode = .cowork }
                    else { sidebarMode = .chat }
                },
                onNewConversation: { createNewConversation() },
                onOpenSettings: { WindowOpener.shared.openSettings?() }
            )
        }
        .background {
            Group {
                Button("") { showCommandPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("") { createNewConversation() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("") { withAnimation { showSearch = true } }
                    .keyboardShortcut("f", modifiers: .command)
                Button("") { switchMode(.chat) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { switchMode(.cowork) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { switchMode(.code) }
                    .keyboardShortcut("3", modifiers: .command)
            }
            .opacity(0)
        }
        .tint(accentColor)
        .preferredColorScheme(colorScheme)
    }

    private var accentColor: Color { (AccentChoice(rawValue: accentRaw) ?? .clay).color }
    private var colorScheme: ColorScheme? { (AppearanceChoice(rawValue: appearanceRaw) ?? .system).colorScheme }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Lume")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Button { withAnimation { showSearch.toggle() } } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            if showSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
                    TextField("Search", text: $searchText).font(.system(size: 13)).textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12).padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            modePicker.padding(.horizontal, 12).padding(.bottom, 10)
            Divider().opacity(0.4)
            switch sidebarMode {
            case .chat:   chatSidebar
            case .cowork: coworkSidebar
            case .code:   codeSidebar
            }
            Divider().opacity(0.4)
            bottomBar
        }
        .background(Color(.windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: showSearch)
        .animation(.easeInOut(duration: 0.15), value: sidebarMode)
    }

    private func switchMode(_ mode: SidebarMode) {
        withAnimation(.easeInOut(duration: 0.18)) {
            sidebarMode = mode
            selectedConversation = nil
            selectedProject = nil
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(SidebarMode.allCases, id: \.self) { mode in
                Button {
                    switchMode(mode)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon).font(.system(size: 11, weight: .medium))
                        Text(mode.label).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(sidebarMode == mode ? .primary : .secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(
                        sidebarMode == mode ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear),
                        in: Capsule(style: .continuous)
                    )
                    .contentShape(Capsule(style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))
        .frame(minWidth: 240)
    }

    // MARK: - Chat Sidebar

    private var chatSidebar: some View {
        List {
            Button(action: createNewConversation) {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    Text("New Conversation").font(.system(size: 13)).foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.vertical, 2).contentShape(Rectangle())
            }
            .buttonStyle(.plain).listRowBackground(Color.clear).listRowSeparator(.hidden)

            Section {
                ForEach(filteredChatConversations.prefix(30)) { conv in
                    Button {
                        selectedConversation = conv; selectedProject = nil
                    } label: {
                        ConversationRowView(conversation: conv, isSelected: selectedConversation?.id == conv.id)
                    }
                    .buttonStyle(.plain).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .contextMenu { chatConversationContextMenu(conv) }
                }
            } header: { sectionHeader("Recent", action: nil) }
        }
        .listStyle(.sidebar).scrollContentBackground(.hidden)
    }

    // MARK: - Cowork Sidebar

    private var coworkSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarNavItem(icon: "plus.bubble", label: "New Conversation") {
                    if let existing = allConversations.first(where: {
                        $0.project == nil && !$0.isArchived && $0.messages.isEmpty
                    }) {
                        selectedConversation = existing
                        selectedProject = nil
                        sidebarMode = .cowork
                        return
                    }
                    let conv = Conversation(
                        providerType: activeConfig?.providerType ?? "openai",
                        modelName: activeConfig?.defaultModel ?? "gpt-4o"
                    )
                    modelContext.insert(conv)
                    do { try modelContext.save() } catch { }
                    selectedConversation = conv
                    selectedProject = nil
                    sidebarMode = .cowork
                }
                sidebarNavItem(icon: "folder.badge.plus", label: "New Project") {
                    showNewProject = true
                }
                sidebarNavItem(icon: "rectangle.split.2x1", label: "Live Artifacts") {
                    if let conv = allConversations.first(where: { $0.messages.contains { $0.artifact != nil } }) {
                        selectedConversation = conv; selectedProject = nil
                        sidebarMode = .chat
                    }
                }
                Divider().padding(.vertical, 8).padding(.horizontal, 12)
                HStack {
                    Text("Projects").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { showNewProject = true } label: {
                        Image(systemName: "plus").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.bottom, 4)
                if projects.isEmpty {
                    Text("No projects").font(.system(size: 12)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 14).padding(.bottom, 8)
                } else {
                    ForEach(projects) { project in projectDisclosureRow(project) }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Project Disclosure Row

    private func projectDisclosureRow(_ project: Project) -> some View {
        let isExpanded = expandedProjects.contains(project.id)
        let isProjectSelected = selectedProject?.id == project.id
        let sortedConvs = project.conversations.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded { expandedProjects.remove(project.id) }
                        else { expandedProjects.insert(project.id) }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.leading, 8)

                Button {
                    expandedProjects.insert(project.id)
                    selectedProject = project
                    if let lastConv = sortedConvs.first {
                        selectedConversation = lastConv
                    } else {
                        openNewProjectConversation(for: project)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: project.icon).font(.system(size: 13))
                            .foregroundStyle(isProjectSelected ? Color.accentColor : LumeTheme.clay).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                .foregroundStyle(isProjectSelected ? Color.accentColor : .primary)
                            Text("\(sortedConvs.count) conversations").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 7).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { openNewProjectConversation(for: project) } label: {
                        Label("New conversation", systemImage: "plus.bubble")
                    }
                    Button { reconnectProjectFolder(project) } label: {
                        Label("Reconnect folder...", systemImage: "folder.badge.gear")
                    }
                    Divider()
                    Button(role: .destructive) { deleteProject(project) } label: {
                        Label("Delete project", systemImage: "trash")
                    }
                }
            }
            .background(isProjectSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 6)

            if isExpanded {
                VStack(spacing: 1) {
                    if sortedConvs.isEmpty {
                        Text("No conversations").font(.system(size: 11)).foregroundStyle(.tertiary)
                            .padding(.leading, 40).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(sortedConvs) { conv in
                            Button {
                                selectedConversation = conv; selectedProject = conv.project
                            } label: {
                                HStack(spacing: 8) {
                                    Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1).padding(.leading, 22)
                                    Image(systemName: conv.isPinned ? "pin.fill" : "bubble.left")
                                        .font(.system(size: conv.isPinned ? 9 : 10))
                                        .foregroundStyle(conv.isPinned ? Color.accentColor : Color.secondary).frame(width: 14)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(conv.title)
                                            .font(.system(size: 12, weight: selectedConversation?.id == conv.id ? .semibold : .regular))
                                            .lineLimit(1)
                                            .foregroundStyle(selectedConversation?.id == conv.id ? Color.accentColor : .primary)
                                        Text(conv.updatedAt.formatted(.relative(presentation: .named)))
                                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 5).padding(.trailing, 10).padding(.leading, 6)
                                .background(selectedConversation?.id == conv.id ? Color.accentColor.opacity(0.06) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).padding(.horizontal, 6)
                            .contextMenu { coworkConversationContextMenu(conv) }
                        }
                    }
                    Button {
                        openNewProjectConversation(for: project)
                    } label: {
                        HStack(spacing: 6) {
                            Spacer().frame(width: 22)
                            Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                            Text("New conversation").font(.system(size: 11)).foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.vertical, 5).padding(.leading, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.horizontal, 6)
                }
                .padding(.bottom, 4).transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divider().opacity(0.2).padding(.horizontal, 14).padding(.top, isExpanded ? 4 : 0)
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    // MARK: - Open new conversation inside project

    private func openNewProjectConversation(for project: Project) {
        let conv = Conversation(
            title: "New Conversation",
            providerType: activeConfig?.providerType ?? "openai",
            modelName: activeConfig?.defaultModel ?? "gpt-4o",
            systemPrompt: buildProjectSystemPrompt(for: project)
        )
        conv.project = project
        modelContext.insert(conv)
        try? modelContext.save()
        selectedConversation = conv
        selectedProject = project
    }

    // MARK: - Reconnect Project Folder

    private func reconnectProjectFolder(_ project: Project) {
        Task {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = String(localized: "Select the folder for project \"\(project.name)\"")
            panel.prompt = "Reconectar"
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = panel.runModal()
            }
            if response == .OK, let url = panel.url {
                project.localPath = url.path
                try? modelContext.save()
                AIProviderManager.saveBookmark(for: url, projectID: project.id)
            }
        }
    }

    // MARK: - Delete Project

    private func deleteProject(_ project: Project) {
        if selectedProject?.id == project.id { selectedProject = nil }
        if let conv = selectedConversation, conv.project?.id == project.id {
            selectedConversation = nil
        }
        expandedProjects.remove(project.id)
        modelContext.delete(project)
        do { try modelContext.save() } catch { }
    }

    // MARK: - Project System Prompt Builder

    private func buildProjectSystemPrompt(for project: Project) -> String {
        let base = project.systemPrompt.isEmpty ? "" : project.systemPrompt + "\n\n"
        let folderLine = project.localPath.isEmpty ? "" : "Pasta do projeto: \(project.localPath)\n"
        return base
            + "## Contexto do Projeto\n"
            + "Nome: \(project.name)\n"
            + folderLine
            + "\nVocê está trabalhando EXCLUSIVAMENTE no projeto \"\(project.name)\". "
            + "Todas as suas respostas, análises e ações devem ser relacionadas a este projeto. "
            + "Não pergunte sobre qual projeto trabalhar — você já está nele."
            + (project.localPath.isEmpty ? "" : "\nOpere apenas dentro da pasta: \(project.localPath)")
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func chatConversationContextMenu(_ conv: Conversation) -> some View {
        Button { conv.isPinned.toggle(); try? modelContext.save() } label: {
            Label(conv.isPinned ? "Unpin" : "Pin", systemImage: conv.isPinned ? "pin.slash" : "pin")
        }
        Button { renamingConversation = conv } label: { Label("Rename", systemImage: "pencil") }
        if !projects.isEmpty {
            Menu {
                ForEach(projects) { project in
                    Button {
                        moveConversation(conv, to: project); sidebarMode = .cowork
                        selectedProject = project; selectedConversation = conv
                    } label: {
                        if conv.project?.id == project.id { Label(project.name, systemImage: "checkmark") }
                        else { Label(project.name, systemImage: project.icon) }
                    }
                }
            } label: { Label("Add to project", systemImage: "folder.badge.plus") }
        } else {
            Button { showNewProject = true } label: { Label("Add to project", systemImage: "folder.badge.plus") }
        }
        Divider()
        Button(role: .destructive) { deleteConversation(conv) } label: { Label("Delete", systemImage: "trash") }
    }

    @ViewBuilder
    private func coworkConversationContextMenu(_ conv: Conversation) -> some View {
        Menu {
            ForEach(projects) { project in
                Button { moveConversation(conv, to: project) } label: {
                    if conv.project?.id == project.id { Label(project.name, systemImage: "checkmark") }
                    else { Label(project.name, systemImage: project.icon) }
                }
            }
            if !projects.isEmpty { Divider() }
            Button("No project") { conv.project = nil; try? modelContext.save() }
        } label: { Label("Move to project", systemImage: "tray.and.arrow.right") }
        Divider()
        Button { conv.isPinned.toggle(); try? modelContext.save() } label: {
            Label(conv.isPinned ? "Unpin" : "Pin", systemImage: conv.isPinned ? "pin.slash" : "pin")
        }
        Button { renamingConversation = conv } label: { Label("Rename", systemImage: "pencil") }
        Divider()
        Button {
            conv.isArchived.toggle()
            if conv.isArchived && selectedConversation?.id == conv.id { selectedConversation = nil }
            try? modelContext.save()
        } label: {
            Label(conv.isArchived ? "Unarchive" : "Archive",
                  systemImage: conv.isArchived ? "tray.and.arrow.up" : "archivebox")
        }
        Button(role: .destructive) { deleteConversation(conv) } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: - Code Sidebar

    private var codeSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                sidebarNavItem(icon: "house.fill", label: "Code Start") {
                    selectedConversation = nil
                    selectedProject = nil
                }
                .padding(.top, 4)

                sidebarNavItem(icon: "chevron.left.forwardslash.chevron.right", label: String(localized: "New code session")) {
                    createNewCodeConversation()
                }

                Divider().padding(.vertical, 8).padding(.horizontal, 12)

                HStack {
                    Text("Repository").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.horizontal, 14).padding(.bottom, 4)

                sidebarNavItem(icon: "arrow.triangle.branch", label: "Git") {
                    NotificationCenter.default.post(name: .openGitPanel, object: nil)
                }

                Divider().padding(.vertical, 8).padding(.horizontal, 12)

                HStack {
                    Text("Recent Sessions").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.horizontal, 14).padding(.bottom, 4)

                if filteredCodeConversations.isEmpty {
                    Text("No sessions yet")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 14).padding(.bottom, 8)
                } else {
                    ForEach(filteredCodeConversations.prefix(6)) { conv in
                        Button { selectedConversation = conv; selectedProject = nil } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 16)
                                Text(conv.title).font(.system(size: 13)).lineLimit(1).foregroundStyle(.primary)
                                Spacer()
                                Text(conv.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain).contextMenu { chatConversationContextMenu(conv) }
                    }
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Popup de atualização — logo acima do nome do modelo
            if let release = updateManager.availableRelease {
                SidebarUpdateBadge(
                    version: release.version,
                    onUpdate: { sparkle.checkForUpdates(); updateManager.dismiss() },
                    onDismiss: { withAnimation(.easeInOut(duration: 0.2)) { updateManager.dismiss() } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                Spacer()
                if let config = activeConfig {
                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 5, height: 5).shadow(color: .green.opacity(0.6), radius: 2)
                        Text(config.name).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3).background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.25), value: updateManager.availableRelease?.version)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch sidebarMode {
        case .chat:   chatDetail
        case .cowork: coworkDetail
        case .code:   codeDetail
        }
    }

    @ViewBuilder
    private var chatDetail: some View {
        if let conv = selectedConversation {
            ChatDetailView(conversation: conv, providerManager: providerManager)
        } else {
            ChatWelcomeView(onStart: { startConversation(text: $0, mode: .chat) })
        }
    }

    @ViewBuilder
    private var coworkDetail: some View {
        if let conv = selectedConversation {
            ChatDetailView(conversation: conv, providerManager: providerManager)
        } else if let project = selectedProject {
            ProjectDetailView(project: project, providerManager: providerManager)
        } else {
            CoworkDashboardView(
                projects: projects,
                conversations: recentProjectConversations,
                onSelectProject: { selectedProject = $0 },
                onSelectConversation: { selectedConversation = $0; sidebarMode = .cowork },
                onNewProject: { showNewProject = true },
                onNewConversation: {
                    if let existing = allConversations.first(where: {
                        $0.project == nil && !$0.isArchived && $0.messages.isEmpty
                    }) {
                        selectedConversation = existing; sidebarMode = .cowork; return
                    }
                    let conv = Conversation(
                        providerType: activeConfig?.providerType ?? "openai",
                        modelName: activeConfig?.defaultModel ?? "gpt-4o"
                    )
                    modelContext.insert(conv)
                    do { try modelContext.save() } catch { }
                    selectedConversation = conv; sidebarMode = .cowork
                }
            )
        }
    }

    @ViewBuilder
    private var codeDetail: some View {
        if let conv = selectedConversation {
            ChatDetailView(conversation: conv, providerManager: providerManager)
        } else {
            CodeDashboardView(
                conversations: filteredCodeConversations,
                onSelectConversation: { selectedConversation = $0 },
                onNewConversation: { createNewCodeConversation() }
            )
        }
    }

    // MARK: - Conversation launcher

    private func startConversation(text: String, mode: SidebarMode) {
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.prefix(6).joined(separator: " ")
        let conv = Conversation(
            title: String(words.prefix(50)).isEmpty ? "New Conversation" : String(words.prefix(50)),
            providerType: activeConfig?.providerType ?? "openai",
            modelName: activeConfig?.defaultModel ?? "gpt-4o"
        )
        modelContext.insert(conv); do { try modelContext.save() } catch { }
        selectedConversation = conv; selectedProject = nil; sidebarMode = mode
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            _ = try? await providerManager.streamMessage(content: text, conversation: conv)
            conv.updatedAt = Date(); try? modelContext.save()
        }
    }

    // MARK: - Helpers

    private func sidebarNavItem(icon: String, label: String, badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.primary).frame(width: 20)
                Text(label).font(.system(size: 13)).foregroundStyle(.primary)
                if let badge {
                    Text(badge).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, action: (() -> Void)?) -> some View {
        HStack {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).tracking(0.8)
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
        }
    }

    private var filteredChatConversations: [Conversation] {
        let pinned = allConversations.filter { $0.project == nil && !$0.isArchived && $0.isPinned && !$0.tags.contains("code") }
        let rest   = allConversations.filter { $0.project == nil && !$0.isArchived && !$0.isPinned && !$0.tags.contains("code") }
        let sorted = pinned + rest
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredCodeConversations: [Conversation] {
        let codeConvs = allConversations.filter { $0.project == nil && !$0.isArchived && $0.tags.contains("code") }
        guard !searchText.isEmpty else { return codeConvs }
        return codeConvs.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var recentProjectConversations: [Conversation] {
        let active = allConversations.filter { $0.project != nil && !$0.isArchived }
        return active.filter { $0.isPinned } + active.filter { !$0.isPinned }
    }

    private func moveConversation(_ conv: Conversation, to project: Project) {
        conv.project = project; conv.updatedAt = Date(); do { try modelContext.save() } catch { }
    }

    private func deleteConversation(_ conv: Conversation) {
        if selectedConversation?.id == conv.id { selectedConversation = nil }
        modelContext.delete(conv); do { try modelContext.save() } catch { }
    }

    private func createNewConversation() {
        if let existing = allConversations.first(where: {
            $0.project == nil && !$0.isArchived && $0.messages.isEmpty
        }) {
            selectedConversation = existing; selectedProject = nil; sidebarMode = .chat; return
        }
        let conv = Conversation(
            providerType: activeConfig?.providerType ?? "openai",
            modelName: activeConfig?.defaultModel ?? "gpt-4o"
        )
        modelContext.insert(conv); do { try modelContext.save() } catch { }
        selectedConversation = conv; selectedProject = nil; sidebarMode = .chat
    }

    private func createNewCodeConversation() {
        if let existing = allConversations.first(where: {
            $0.project == nil && !$0.isArchived && $0.messages.isEmpty
        }) {
            selectedConversation = existing; selectedProject = nil; sidebarMode = .code; return
        }
        let conv = Conversation(
            title: String(localized: "Code Session"),
            providerType: activeConfig?.providerType ?? "openai",
            modelName: activeConfig?.defaultModel ?? "gpt-4o"
        )
        conv.tags = ["code"]
        modelContext.insert(conv); do { try modelContext.save() } catch { }
        selectedConversation = conv; selectedProject = nil; sidebarMode = .code
    }

    private func loadActiveProvider() async {
        let descriptor = FetchDescriptor<AIProviderConfig>(predicate: #Predicate { $0.isActive })
        if let cfg = try? modelContext.fetch(descriptor).first {
            try? await providerManager.setActiveProvider(configID: cfg.id, config: cfg, context: modelContext)
        }
    }
}

// MARK: - Lume Logo

struct LumeLogo: View {
    var size: CGFloat = 56
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.92, green: 0.52, blue: 0.58),
                             Color(red: 0.96, green: 0.67, blue: 0.42)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
                .shadow(color: Color(red: 0.92, green: 0.52, blue: 0.58).opacity(0.35),
                        radius: size * 0.18, y: size * 0.08)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Welcome View

struct ChatWelcomeView: View {
    var onStart: (String) -> Void

    private let starters: [(icon: String, title: String, subtitle: String, prompt: String)] = [
        ("text.bubble",              String(localized: "Ask a question"),   String(localized: "Ask anything"),                String(localized: "I have a question about ")),
        ("doc.text.magnifyingglass", String(localized: "Summarize a text"), String(localized: "Paste an article or document"), String(localized: "Please summarize the following text:\n\n")),
        ("globe",                    String(localized: "Search the web"),   String(localized: "Up-to-date information"),        String(localized: "Search the web for ")),
        ("character.bubble",         String(localized: "Translate"),        String(localized: "Between languages"),            String(localized: "Translate to English:\n\n")),
        ("lightbulb",                "Brainstorm",                          String(localized: "Explore possibilities"),        String(localized: "Help me come up with ideas for ")),
        ("pencil.and.outline",       String(localized: "Write something"),  String(localized: "Emails, posts, drafts"),        String(localized: "Write for me: ")),
    ]

    private func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return String(localized: "Good morning")
        case 12..<18: return String(localized: "Good afternoon")
        default:      return String(localized: "Good evening")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                LumeLogo(size: 64)
                VStack(spacing: 6) {
                    Text(greeting())
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(String(localized: "Chat — a pure conversation. Ask, write, brainstorm and search the web. No file or shell access in this mode."))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 460)
                }
            }
            .padding(.bottom, 28)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(starters.enumerated()), id: \.offset) { _, item in
                    LumeWelcomeCard(icon: item.icon, title: item.title, subtitle: item.subtitle,
                                    color: Color(red: 0.40, green: 0.60, blue: 1.00)) {
                        onStart(item.prompt)
                    }
                }
            }
            .frame(maxWidth: 660).padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}

struct LumeWelcomeCard: View {
    let icon: String; let title: String; let subtitle: String; let color: Color; let action: () -> Void
    @State private var isHovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(isHovering ? 0.20 : 0.10)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color.opacity(isHovering ? 0.8 : 0.25))
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(isHovering ? AnyShapeStyle(color.opacity(0.07)) : AnyShapeStyle(.ultraThinMaterial),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isHovering ? color.opacity(0.30) : Color.primary.opacity(0.07), lineWidth: 1))
            .shadow(color: isHovering ? color.opacity(0.10) : .black.opacity(0.04), radius: 8, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.14), value: isHovering)
    }
}

// MARK: - Rename Sheet

struct RenameConversationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var conversation: Conversation
    @State private var name: String
    let onDone: () -> Void

    init(conversation: Conversation, initialName: String, onDone: @escaping () -> Void) {
        self.conversation = conversation
        self._name = State(initialValue: initialName)
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Rename").font(.system(size: 18, weight: .bold, design: .rounded))
            TextField("Conversation name", text: $name).textFieldStyle(.roundedBorder).onSubmit { save() }
            HStack {
                Button("Cancel", role: .cancel) { onDone() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Save") { save() }.buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 320)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        conversation.title = trimmed
        do { try modelContext.save() } catch { }
        onDone()
    }
}

// MARK: - Sidebar Mode

enum SidebarMode: String, CaseIterable {
    case chat, cowork, code
    var label: String {
        switch self { case .chat: return "Chat"; case .cowork: return "Cowork"; case .code: return "Code" }
    }
    var icon: String {
        switch self {
        case .chat:   return "bubble.left.and.text.bubble.right"
        case .cowork: return "checklist"
        case .code:   return "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum SidebarItem: Hashable {
    case conversation(String)
    case project(String)
}

struct ProjectRowView: View {
    let project: Project
    let isSelected: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: project.icon).font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : LumeTheme.clay).frame(width: 18)
            Text(project.name).font(.system(size: 13)).lineLimit(1)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
            Spacer()
            Text("\(project.conversations.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                .padding(.horizontal, 5).padding(.vertical, 2).background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.vertical, 5).padding(.horizontal, 4)
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    let isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if conversation.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Color.accentColor)
                }
                Text(conversation.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1).foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
            HStack(spacing: 5) {
                if conversation.tags.contains("code"),
                   let wsPath = UserDefaults.standard.string(forKey: "code_workspace_path") {
                    let wsName = URL(fileURLWithPath: wsPath).lastPathComponent
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill").font(.system(size: 8))
                        Text(wsName).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(LumeTheme.moss)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(LumeTheme.moss.opacity(0.10), in: Capsule())
                    Text("·").foregroundStyle(.tertiary)
                }
                Image(systemName: providerIcon).font(.system(size: 9))
                Text(conversation.modelName).font(.system(size: 11)).lineLimit(1)
                Spacer()
                Text(conversation.updatedAt.formatted(.relative(presentation: .named))).font(.system(size: 10))
            }.foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5).padding(.horizontal, 4).contentShape(Rectangle())
    }
    private var providerIcon: String {
        switch conversation.providerType {
        case "openai": return "bolt.fill"
        case "anthropic": return "sparkles"
        default: return "circle.dotted"
        }
    }
}

struct GitStatusRow: View {
    let workspacePath: String
    @State private var status: GitManager.GitStatus? = nil
    var body: some View {
        Group {
            if let status {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(status.branch)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !status.staged.isEmpty { Text("S:\(status.staged.count)").font(.system(size: 9)).foregroundStyle(.green) }
                    if !status.modified.isEmpty { Text("M:\(status.modified.count)").font(.system(size: 9)).foregroundStyle(.orange) }
                }.padding(.horizontal, 14).padding(.vertical, 4)
            } else {
                Text("Loading git…").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 14)
            }
        }
        .task { status = await GitManager.shared.status(at: workspacePath) }
    }
}
