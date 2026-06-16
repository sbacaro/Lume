//
//  ProjectDetailView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    var providerManager: AIProviderManager

    @State private var selectedConversation: Conversation?
    @State private var showFileImporter = false
    @State private var showInstructionsSheet = false
    @State private var showDeleteConfirm = false
    @State private var messageText = ""
    @State private var indexedFiles: [String] = []
    @State private var gradientAngle: Double = 0
    @State private var attachedImages: [NSImage] = []

    var body: some View {
        Group {
            if let conv = selectedConversation {
                ChatDetailView(conversation: conv, providerManager: providerManager)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                selectedConversation = nil
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(project.name)
                                        .font(.system(size: 13))
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
            } else {
                projectDashboard
            }
        }
        .sheet(isPresented: $showInstructionsSheet) {
            ProjectInstructionsSheet(project: project)
        }
        .confirmationDialog(
            "Delete \"\(project.name)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) { deleteProject() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone. All conversations in the project will be deleted.")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .plainText, .image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    for url in urls {
                        if let file = try? await FileIngestionManager.shared.ingest(url: url) {
                            await RAGEngine.shared.index(file: file)
                            await MainActor.run { indexedFiles.append(file.name) }
                        }
                    }
                }
            }
        }
        .onAppear { startGradientAnimation() }
        .task { await indexProjectFilesIfNeeded() }
    }

    // MARK: - Project Dashboard

    private var projectDashboard: some View {
        HSplitView {
            VStack(spacing: 0) {
                projectHeader
                Divider().opacity(0.3)
                conversationsArea
                projectInputArea
            }
            .frame(minWidth: 420)

            rightPanel
                .frame(width: 300)
        }
    }

    // MARK: - Project Header

    private var projectHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: project.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(LumeTheme.clay)

                    TextField("Project name", text: $project.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .textFieldStyle(.plain)
                        .foregroundStyle(.primary)
                }

                Text("\(project.conversations.count) conversations · created \(project.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button { showInstructionsSheet = true } label: {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Project instructions")

                Menu {
                    Button("New Conversation", action: createConversation)
                    Divider()
                    Button("Add to Knowledge Base") { showFileImporter = true }
                    Divider()
                    Button("Delete Project", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30, height: 30)
                .help("More options")
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    // MARK: - Conversations Area

    private var conversationsArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let latestConv = sortedConversations.first,
                   let lastMsg = latestConv.messages.last(where: { $0.role == .assistant }) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Outputs")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 28)

                        Button { selectedConversation = latestConv } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(lastMsg.content)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(6)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 28)
                    }
                    .padding(.bottom, 24)
                }

                if !sortedConversations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 28)

                        ForEach(sortedConversations) { conv in
                            Button { selectedConversation = conv } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(conv.title)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(conv.updatedAt.formatted(.relative(presentation: .named)))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                        }
                                        if let lastMsg = conv.messages.last(where: { $0.role == .user }) {
                                            Text(lastMsg.content)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        let artifactMessages = conv.messages.filter { $0.artifact != nil }
                                        if !artifactMessages.isEmpty {
                                            HStack(spacing: 4) {
                                                ForEach(artifactMessages.prefix(3), id: \.id) { msg in
                                                    if let artifact = msg.artifact {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "doc.text").font(.system(size: 9))
                                                            Text(artifact.title).font(.system(size: 10))
                                                        }
                                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                                        .background(.ultraThinMaterial,
                                                                    in: RoundedRectangle(cornerRadius: 4))
                                                        .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                            .padding(.top, 2)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.primary.opacity(0.03),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 28)
                            .contextMenu {
                                Button("Open") { selectedConversation = conv }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    modelContext.delete(conv)
                                    try? modelContext.save()
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: project.icon)
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No conversations yet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Type below to start working on this project.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Project Input Area

    private var projectInputArea: some View {
        // Reusa o MESMO composer do Chat/Code para a UI ficar idêntica em todos os modos.
        ChatInputView(
            text: $messageText,
            placeholder: String(localized: "What would you like to work on in this project?"),
            isLoading: providerManager.isLoading,
            onSend: sendMessage,
            onStop: { providerManager.cancelStreaming() },
            onAttach: { showFileImporter = true },
            onVoice: { },
            isDictating: false,
            modelName: providerManager.activeProvider?.defaultModel ?? "",
            availableModels: [],
            onModelChange: { newModel in
                providerManager.activeProvider?.defaultModel = newModel
            },
            onProviderModelSelect: { provider, newModel in
                Task {
                    try? await providerManager.setActiveProvider(
                        configID: provider.id, config: provider, context: modelContext)
                    providerManager.activeProvider?.defaultModel = newModel
                }
            },
            attachedImages: $attachedImages
        )
    }


    // MARK: - Right Panel

    private var rightPanel: some View {
        ScrollView {
            VStack(spacing: 1) {
                RightPanelSection(
                    title: String(localized: "Instructions"),
                    icon: "doc.text",
                    actionIcon: "paperclip",
                    onAction: { showInstructionsSheet = true }
                ) {
                    if project.systemPrompt.isEmpty {
                        Text("Add tone, formatting, or rules to guide how the assistant works.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .italic()
                    } else {
                        Text(project.systemPrompt)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }

                RightPanelSection(title: "Programado", icon: "clock", actionIcon: "plus", onAction: nil) {
                    Text("Set up recurring tasks for this project.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .italic()
                }

                RightPanelSection(
                    title: "Contexto",
                    icon: "doc.text.magnifyingglass",
                    actionIcon: "plus",
                    onAction: { showFileImporter = true }
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On your computer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)

                        if let url = project.localURL {
                            Button { NSWorkspace.shared.open(url) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Image(systemName: "folder.fill").font(.system(size: 13)).foregroundStyle(LumeTheme.clay)
                                    Text(url.lastPathComponent).font(.system(size: 12)).foregroundStyle(.primary).lineLimit(1)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        if !indexedFiles.isEmpty {
                            Text("Memory")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)

                            ForEach(indexedFiles.prefix(3), id: \.self) { name in
                                HStack(spacing: 8) {
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(.secondary)
                                    Text(name).font(.system(size: 12)).foregroundStyle(.primary).lineLimit(1)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }

                Spacer().frame(height: 20)

                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Delete Project", systemImage: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .overlay(Divider(), alignment: .leading)
    }

    // MARK: - Helpers

    private var sortedConversations: [Conversation] {
        project.conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func startGradientAnimation() {
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
            gradientAngle = 360
        }
    }

    private func indexProjectFilesIfNeeded() async {
        let files = ProjectManager.shared.listFiles(in: project)
        for url in files {
            if let file = try? await FileIngestionManager.shared.ingest(url: url) {
                await RAGEngine.shared.index(file: file)
                await MainActor.run {
                    if !indexedFiles.contains(file.name) {
                        indexedFiles.append(file.name)
                    }
                }
            }
        }
    }

    private func createConversation() {
        let provider = providerManager.activeProvider
        let conv = Conversation(
            title: "New Conversation",
            providerType: provider?.name == "Anthropic" ? "anthropic" : (providerManager.activeConfig?.providerType ?? "openai"),
            modelName: provider?.defaultModel ?? "gpt-4o",
            systemPrompt: project.systemPrompt
        )
        conv.project = project
        modelContext.insert(conv)
        do { try modelContext.save() } catch { }
        selectedConversation = conv
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let provider = providerManager.activeProvider
        let conv = Conversation(
            title: String(text.prefix(40)),
            providerType: provider?.name == "Anthropic" ? "anthropic" : (providerManager.activeConfig?.providerType ?? "openai"),
            modelName: provider?.defaultModel ?? "gpt-4o",
            systemPrompt: project.systemPrompt
        )
        conv.project = project
        conv.messages.append(Message(role: .user, content: text))
        modelContext.insert(conv)
        // Silencia o warning — save() é síncrono, resultado ignorado intencionalmente
        do { try modelContext.save() } catch { }
        messageText = ""
        attachedImages = []

        let manager = providerManager
        let ragProject = project

        Task.detached { @MainActor in
            let files = ProjectManager.shared.listFiles(in: ragProject)
            for url in files {
                if let file = try? await FileIngestionManager.shared.ingest(url: url) {
                    await RAGEngine.shared.index(file: file)
                }
            }
            _ = try? await manager.streamMessage(content: text, conversation: conv)
        }

        selectedConversation = conv
    }

    private func deleteProject() {
        modelContext.delete(project)
        // Silencia o warning — save() é síncrono, resultado ignorado intencionalmente
        do { try modelContext.save() } catch { }
    }
}

// MARK: - Right Panel Section

struct RightPanelSection<Content: View>: View {
    let title: String
    let icon: String
    let actionIcon: String
    let onAction: (() -> Void)?
    @State private var isExpanded = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let onAction {
                    Button(action: onAction) {
                        Image(systemName: actionIcon)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isExpanded {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }

            Divider().opacity(0.4)
        }
    }
}
