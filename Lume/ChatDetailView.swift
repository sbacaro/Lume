//
//  ChatDetailView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ChatDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var conversation: Conversation
    var providerManager: AIProviderManager
    var onFirstMessage: (() -> Void)? = nil
    /// Texto pré-preenchido no input ao abrir (ex.: atalhos da tela inicial). Não é enviado.
    var initialDraft: Binding<String?> = .constant(nil)
    @Query private var providerConfigs: [AIProviderConfig]

    @State private var messageText = ""
    @State private var activeArtifact: Artifact? = nil
    @State private var activeToolCalls: [String: [ToolCall]] = [:]
    @State private var showInspector = true
    @State private var dictation = VoiceDictationManager()
    @State private var attachedFiles: [FileIngestionManager.IngestedFile] = []
    @State private var attachedImages: [NSImage] = []
    @State private var showFileImporter = false
    @State private var editingMessage: Message? = nil
    @State private var focusInput = false
    @State private var editingNotes = false
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var displayedMessagesCount = 20
    @State private var expandedMessageId: String?
    @State private var expandedThinkingId: String?
    @State private var showVersions = false
    @State private var errorToast: String?
    @State private var approval = ApprovalCoordinator.shared
    @State private var queuedMessage: String?
    @State private var isChatDropTargeted = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                chatHeader
                Divider()
                messageList
                if !attachedFiles.isEmpty { attachmentBar }
                if let pending = approval.pending {
                    approvalCard(pending)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let q = queuedMessage, !q.trimmingCharacters(in: .whitespaces).isEmpty {
                    queuedChip(q)
                }
                
                // Input fixo na base
                modeCapabilityChip
                ChatInputView(
                    text: $messageText,
                    placeholder: inputPlaceholder,
                    isLoading: providerManager.isLoading,
                    onSend: sendMessage,
                    onStop: { providerManager.cancelStreaming() },
                    onAttach: { showFileImporter = true },
                    onVoice: { Task { await dictation.toggleRecording() } },
                    onQueue: { queueMessage() },
                    isDictating: dictation.isRecording,
                    modelName: conversation.modelName,
                    availableModels: availableModels,
                    onModelChange: { newModel in
                        providerManager.changeModel(newModel, for: conversation)
                    },
                    onProviderModelSelect: { provider, newModel in
                        // Mantém modelo e provider em sincronia: ao escolher um modelo
                        // dentro de um provider, troca o provider ativo para ele.
                        conversation.providerType = provider.providerType
                        providerManager.changeModel(newModel, for: conversation)
                        try? modelContext.save()
                        Task {
                            try? await providerManager.setActiveProvider(
                                configID: provider.id, config: provider, context: modelContext)
                        }
                    },
                    attachedImages: $attachedImages
                )
            }
            .frame(minWidth: 380)
            .background(Color(.windowBackgroundColor))
            .onDrop(of: [.image, .fileURL], isTargeted: $isChatDropTargeted) { providers in
                handleChatImageDrop(providers: providers)
            }
            .overlay {
                if isChatDropTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .background(Color.accentColor.opacity(0.04))
                        .overlay(
                            Label("Drop to attach", systemImage: "photo.badge.plus")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        )
                        .padding(8)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isChatDropTargeted)

            if showInspector && activeArtifact == nil {
                inspectorPanel
                    .frame(width: 270)
                    .transition(.move(edge: .trailing))
            }

            if let artifact = activeArtifact {
                ArtifactPanelView(artifact: artifact)
                    .frame(minWidth: 400)
                    .transition(.move(edge: .trailing))
            }
        }
        .overlay(alignment: .top) { errorBannerView }
        .animation(.easeInOut(duration: 0.2), value: errorToast)
        .onAppear {
            if let draft = initialDraft.wrappedValue, !draft.isEmpty {
                messageText = draft
                initialDraft.wrappedValue = nil
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedFileTypes,
            allowsMultipleSelection: true
        ) { handleFileImport(result: $0) }
        .sheet(item: $editingMessage) { msg in
            EditMessageSheet(message: msg) { newContent in
                restartConversation(from: msg, withNewContent: newContent)
                editingMessage = nil
            } onCancel: { editingMessage = nil }
        }
        .sheet(isPresented: $showVersions) {
            VersionHistorySheet(
                branches: conversation.versionBranches.sorted { $0.createdAt > $1.createdAt },
                onRestore: { restoreBranch($0); showVersions = false },
                onDelete: { branch in
                    conversation.versionBranches.removeAll { $0.id == branch.id }
                    try? modelContext.save()
                },
                onClose: { showVersions = false }
            )
        }
        .onChange(of: dictation.transcript) { _, t in
            guard !t.isEmpty else { return }
            messageText = t
        }
        .onChange(of: dictation.isRecording) { _, recording in
            if !recording && !dictation.transcript.isEmpty {
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    await MainActor.run { if !messageText.isEmpty { sendMessage() } }
                }
            }
        }
        .onChange(of: providerManager.isLoading) { _, loading in
            // Mensagem enfileirada: dispara automaticamente ao terminar a resposta atual.
            if !loading, let queued = queuedMessage {
                queuedMessage = nil
                messageText = queued
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if !providerManager.isLoading { sendMessage() }
                }
            }
        }
        .onChange(of: providerManager.latestArtifactMessageID) { _, msgID in
            guard let msgID else { return }
            if let msg = conversation.messages.first(where: { $0.id == msgID }) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    activeArtifact = msg.artifact
                    if msg.artifact != nil { showInspector = false }
                }
            }
        }
        .onChange(of: focusInput) { _, focused in
            if focused {
                focusInput = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            }
        }
        .alert("Dictation Error", isPresented: .constant(dictation.error != nil)) {
            Button("OK") { dictation.error = nil }
        } message: { Text(dictation.error ?? "") }
        .task { await AgentNotificationManager.shared.requestPermission() }
    }

    // MARK: - Chat Header

    private var chatHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Untitled", text: $conversation.title)
                    .font(.system(size: 13, weight: .semibold))
                    .textFieldStyle(.plain)

                HStack(spacing: 6) {
                    if let project = conversation.project {
                        HStack(spacing: 4) {
                            Image(systemName: project.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(LumeTheme.clay)
                            Text(project.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(LumeTheme.clay)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LumeTheme.clay.opacity(0.10), in: Capsule())

                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Image(systemName: providerIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(conversation.modelName)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    // Modelo escolhido pelo roteamento automático (quando difere do preferido)
                    if providerManager.isLoading,
                       let routed = providerManager.lastRoutingDecision?.model,
                       routed != conversation.modelName {
                        Text("→ \(shortModelName(routed))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .help(String(localized: "Automatic routing chose \(routed) for this message"))
                    }

                    if providerManager.lastCacheHit {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                            .help("Response served from semantic cache")
                    }

                    // Uso da conversa: tokens + custo estimado
                    if conversation.totalTokensUsed > 0 {
                        Text("·").font(.system(size: 10)).foregroundStyle(.tertiary)
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                        Text(usageLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .help("Tokens used in this conversation and estimated cost (approximate)")
                    }
                }
            }

            Spacer()

            if dictation.isRecording {
                HStack(spacing: 5) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                        .shadow(color: .red.opacity(0.6), radius: 3)
                    Text("Recording…").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // Velocidade de geração durante o streaming
            if providerManager.isLoading && providerManager.streamingTokenCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Text(streamingRateLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.opacity)
            }

            if latestArtifactInConversation != nil {
                headerButton(icon: "rectangle.split.2x1", isActive: activeArtifact != nil) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if activeArtifact != nil { activeArtifact = nil; showInspector = true }
                        else { activeArtifact = latestArtifactInConversation; showInspector = false }
                    }
                }.help("Artifacts")
            }

            headerButton(icon: "sidebar.right", isActive: showInspector) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showInspector.toggle()
                    if showInspector { activeArtifact = nil }
                }
            }.help("Inspector")

            Menu {
                Menu("Export") {
                    Button("Markdown (file)…") { ConversationExporter.saveMarkdown(conversation) }
                    Button("PDF…") { ConversationExporter.savePDF(conversation) }
                    Button("Copy as Markdown") { ConversationExporter.copyMarkdown(conversation) }
                }
                Divider()
                Button(String(localized: "Previous versions (\(conversation.versionBranches.count))")) { showVersions = true }
                    .disabled(conversation.versionBranches.isEmpty)
                Divider()
                Button("Clear Cache") { Task { await SemanticCache.shared.clear() } }
                Divider()
                Button("Clear History", action: clearHistory)
                Divider()
                Button("Delete Conversation", role: .destructive, action: deleteConversation)
            } label: { headerButtonLabel(icon: "ellipsis", isActive: false) }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.2), value: dictation.isRecording)
    }

    private func headerButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { headerButtonLabel(icon: icon, isActive: isActive) }.buttonStyle(.plain)
    }

    private func headerButtonLabel(icon: String, isActive: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
            .frame(width: 26, height: 26)
            .background(
                isActive ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    // MARK: - Message List

    private var messageList: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if conversation.messages.isEmpty {
                            EmptyStateView(modelName: conversation.modelName)
                                .frame(width: geometry.size.width)
                                .frame(minHeight: geometry.size.height - 20)
                        } else {
                            messageListContent(geometry: geometry)
                        }

                        Color.clear.frame(height: 1).id("__bottom__")
                    }
                    .frame(minHeight: geometry.size.height, alignment: .bottom)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    displayedMessagesCount = conversation.messages.count
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onChange(of: providerManager.streamingMessageID) { _, id in
                    if id != nil { scrollToBottom(proxy: proxy, animated: false) }
                }
                .onChange(of: providerManager.isLoading) { _, loading in
                    if !loading { scrollToBottom(proxy: proxy, animated: true) }
                }
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Message List Content

    private func messageListContent(geometry: GeometryProxy) -> some View {
        // LazyVStack: só renderiza as linhas visíveis. Sem isso, cada flush do
        // streaming re-avalia o corpo de TODAS as mensagens (e reparseava o
        // markdown de cada uma), saturando CPU e memória em conversas longas.
        LazyVStack(alignment: .leading, spacing: 0) {
            if displayedMessagesCount < conversation.messages.count {
                loadMoreButton
            }
            messageListRows
        }
    }

    // MARK: - Load More Button

    private var loadMoreButton: some View {
        Button {
            withAnimation {
                displayedMessagesCount += 20
            }
        } label: {
            HStack {
                ProgressView().scaleEffect(0.7)
                Text("Load \(min(20, conversation.messages.count - displayedMessagesCount)) earlier messages")
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    // MARK: - Message List Rows

    private var messageListRows: some View {
        let sortedMessages = conversation.messages.sorted { $0.timestamp < $1.timestamp }
        let startIndex = max(0, sortedMessages.count - displayedMessagesCount)

        return ForEach(Array(sortedMessages.enumerated()), id: \.element.id) { idx, message in
            if idx >= startIndex {
                messageRowForMessage(message)
                    .id(message.id)
            }
        }
    }

    // MARK: - Message Row Builder

    private func messageRowForMessage(_ message: Message) -> some View {
        let isStreaming = providerManager.streamingMessageID == message.id
        let toolCalls = activeToolCalls[message.id] ?? []
        
        return MessageRowView(
            message: message,
            isStreaming: isStreaming,
            streamingActivity: isStreaming ? providerManager.streamingActivity : nil,
            toolCalls: toolCalls,
            isThinkingExpanded: expandedThinkingId == message.id,
            onToggleThinking: { toggleThinking(messageId: message.id) },
            onArtifactTap: handleArtifactTap,
            onRestartFrom: { handleRestartFrom(message: message) },
            onEdit: { _ in editingMessage = message },
            onSuggestionSelected: handleSuggestionSelected
        )
    }

    // MARK: - Message Handlers

    private func toggleThinking(messageId: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedThinkingId = expandedThinkingId == messageId ? nil : messageId
        }
    }

    private func handleArtifactTap(_ artifact: Artifact) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if activeArtifact?.id == artifact.id {
                activeArtifact = nil
                showInspector = true
            } else {
                activeArtifact = artifact
                showInspector = false
            }
        }
    }

    private func handleRestartFrom(message: Message) {
        if message.role == .user {
            restartConversation(from: message, withNewContent: nil)
        } else {
            focusInput = true
        }
    }

    private func handleSuggestionSelected(_ suggestion: String) {
        messageText = suggestion
        sendMessage()
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("__bottom__", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("__bottom__", anchor: .bottom)
        }
    }

    // MARK: - Inspector Panel

    /// Modo da conversa, derivado como na navegação (tags/projeto).
    private var mode: LumeMode {
        if conversation.tags.contains("code") { return .code }
        if conversation.project != nil { return .cowork }
        return .chat
    }

    private var modeIcon: String {
        switch mode {
        case .chat:   return "message"
        case .cowork: return "square.grid.2x2"
        case .code:   return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Rótulo honesto do que o agente pode fazer no modo atual (reflete o gating de tools).
    private var modeCapabilityLabel: String {
        switch mode {
        case .chat:   return "Chat — pesquisa na web"
        case .cowork: return "Cowork — arquivos, sandbox, MCP"
        case .code:   return "Code — shell, Git, arquivos"
        }
    }

    /// Faixa fina acima do input indicando o modo e suas capacidades.
    private var modeCapabilityChip: some View {
        HStack(spacing: 6) {
            Image(systemName: modeIcon).font(.system(size: 10))
            Text(modeCapabilityLabel).font(.system(size: 11))
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// Seção "Repository" do inspector (modo Code): arquivos referenciados na sessão.
    private var codeRepoContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if conversation.referencedFiles.isEmpty {
                Text("Nenhum arquivo referenciado ainda.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(conversation.referencedFiles.prefix(8), id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(systemName: fileIcon(for: path))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 11)).lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inspectorPanel: some View {
        List {
            if mode != .chat {
                Section("Progress") { progressContent }
            }
            if mode == .cowork, let project = conversation.project {
                Section(project.name) { projectFilesContent(project) }
            }
            if mode == .code {
                Section("Repository") { codeRepoContent }
            }
            Section("Context") { contextContent }
            Section("Notes") {
                if !conversation.userNotes.isEmpty || editingNotes {
                    notesContent
                } else {
                    Button { editingNotes = true } label: {
                        Label("Add note", systemImage: "note.text.badge.plus")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
        }
    }

    // MARK: - Progresso

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if conversation.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            ZStack {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                                if i < progressStep {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if i < 2 {
                                Rectangle().fill(Color.primary.opacity(0.12))
                                    .frame(height: 1).frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    Text(providerManager.isLoading
                         ? "Processing…"
                         : String(localized: "Task progress will appear here\nautomatically as the AI makes progress."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                let done = conversation.tasks.filter { $0.isDone }.count
                let total = conversation.tasks.count
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(localized: "\(done) of \(total) completed"))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text((Double(done) / Double(max(1, total))).formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(done == total && total > 0 ? Color.green : Color.accentColor)
                                .frame(width: geo.size.width * Double(done) / Double(max(1, total)))
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: done)
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.bottom, 10)
                ForEach(conversation.tasks) { task in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(task.isDone ? Color.green : Color.primary.opacity(0.25))
                            .animation(.easeInOut(duration: 0.2), value: task.isDone)
                        Text(renderMarkdown(task.text))
                            .font(.system(size: 12))
                            .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                            .strikethrough(task.isDone, color: .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .animation(.easeInOut(duration: 0.2), value: task.isDone)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var progressStep: Int {
        if conversation.messages.isEmpty { return 0 }
        if providerManager.isLoading { return 1 }
        return 2
    }

    // MARK: - Arquivos do Projeto

    private func projectFilesContent(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !project.systemPrompt.isEmpty {
                projectFileRow(icon: "doc.text.fill", name: "Project instructions",
                               color: LumeTheme.clay, action: nil)
            }
            if let localURL = project.localURL {
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: localURL, includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
                )) ?? []
                let sorted = files.filter { !$0.hasDirectoryPath }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                // Área de arquivos com altura limitada e scroll interno (sem truncar).
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(sorted.enumerated()), id: \.offset) { _, url in
                            projectFileRow(icon: fileIcon(for: url.path), name: url.lastPathComponent,
                                           color: .secondary, action: { NSWorkspace.shared.open(url) })
                        }
                    }
                }
                .frame(maxHeight: 180)
                Button { NSWorkspace.shared.open(localURL) } label: {
                    Label("Open project folder", systemImage: "folder")
                        .font(.system(size: 11)).foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
    }

    private func projectFileRow(icon: String, name: String, color: Color, action: (() -> Void)?) -> some View {
        let row = HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color).frame(width: 16)
            Text(name).font(.system(size: 12)).lineLimit(1).foregroundStyle(.primary)
            Spacer()
            if action != nil {
                Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5).contentShape(Rectangle())
        if let action {
            return AnyView(Button(action: action) { row }.buttonStyle(.plain))
        } else {
            return AnyView(row)
        }
    }

    // MARK: - Contexto

    private var contextContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if attachedFiles.isEmpty && conversation.referencedFiles.isEmpty && conversation.contextTags.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                .frame(width: 40, height: 40)
                                .overlay(Image(systemName: "doc").font(.system(size: 12)).foregroundStyle(.tertiary))
                        }
                        Button { showFileImporter = true } label: {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                .frame(width: 40, height: 40)
                                .overlay(Image(systemName: "plus").font(.system(size: 14)).foregroundStyle(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Add files to give the conversation context.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            } else {
                if !conversation.contextTags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(conversation.contextTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.10), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                ForEach(attachedFiles, id: \.name) { file in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text").font(.system(size: 10)).foregroundStyle(LumeTheme.clay)
                        Text(file.name).font(.system(size: 11)).lineLimit(1).foregroundStyle(.secondary)
                        Spacer()
                        Text("~\(file.tokenEstimate)t").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                ForEach(conversation.referencedFiles, id: \.self) { filePath in
                    HStack(spacing: 8) {
                        Image(systemName: fileIcon(for: filePath))
                            .font(.system(size: 10)).foregroundStyle(LumeTheme.clay)
                        Text(URL(fileURLWithPath: filePath).lastPathComponent)
                            .font(.system(size: 11)).lineLimit(1).foregroundStyle(.primary)
                        Spacer()
                        Button {
                            conversation.referencedFiles.removeAll { $0 == filePath }
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { showFileImporter = true } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 11)).foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Notas

    private var notesContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editingNotes {
                TextEditor(text: $conversation.userNotes)
                    .font(.system(size: 11)).frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden).padding(6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                HStack {
                    Spacer()
                    Button("Save") { editingNotes = false; try? modelContext.save() }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            } else {
                Text(conversation.userNotes)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .onTapGesture { editingNotes = true }
                Button { editingNotes = true } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.system(size: 10)).foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Attachment Bar

    private var attachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachedFiles.enumerated()), id: \.offset) { idx, file in
                    AttachmentChipView(file: file) {
                        attachedFiles.remove(at: idx)
                        Task { await RAGEngine.shared.removeDocument(name: file.name) }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(Color(.controlBackgroundColor))
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - Computed

    private var providerIcon: String {
        switch conversation.providerType {
        case "openai": return "bolt.fill"
        case "anthropic": return "sparkles"
        default: return "circle.dotted"
        }
    }

    /// Rótulo compacto de uso: tokens + custo estimado.
    private var usageLabel: String {
        let tokens = ModelPricing.formatTokens(conversation.totalTokensUsed)
        if let cost = ModelPricing.estimatedCost(model: conversation.modelName,
                                                 tokens: conversation.totalTokensUsed) {
            return "\(tokens) tok · ~\(ModelPricing.formatCost(cost))"
        }
        return "\(tokens) tok"
    }

    /// Encurta nomes de modelo para exibição (remove prefixos/sufixos verbosos).
    private func shortModelName(_ model: String) -> String {
        model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
    }

    private var availableModels: [String] {
        let active = providerConfigs.filter { $0.isActive }
        if let match = active.first(where: { $0.providerType == conversation.providerType }) {
            // Usa modelos cacheados da API (mais completo e sempre atualizado)
            if !match.cachedModels.isEmpty {
                var seen = Set<String>()
                return match.cachedModels.filter { seen.insert($0).inserted }
            }
            // Fallback estático apenas para Anthropic/OpenAI diretos ainda sem cache
            switch match.providerType {
            case "openai":    return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
            case "anthropic": return ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
            default:
                // Gateways (litellm, custom, etc): sem cache ainda → mostra modelo atual
                return conversation.modelName.isEmpty ? [match.defaultModel] : [conversation.modelName]
            }
        }
        return conversation.modelName.isEmpty ? [] : [conversation.modelName]
    }

    private var inputPlaceholder: String {
        if dictation.isRecording { return "Ouvindo…" }
        return attachedFiles.isEmpty
            ? "Mensagem para \(conversation.modelName)… (↩)"
            : String(localized: "Ask about the documents… (↩)")
    }

    private var latestArtifactInConversation: Artifact? {
        conversation.messages.reversed().first(where: { $0.artifact != nil })?.artifact
    }

    private var allowedFileTypes: [UTType] {[
        .pdf, .image, .plainText, .json, .xml,
        UTType(filenameExtension: "md")    ?? .plainText,
        UTType(filenameExtension: "swift") ?? .plainText,
        UTType(filenameExtension: "py")    ?? .plainText,
    ]}

    private func fileIcon(for path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "go", "rs", "cpp", "c", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "pdf": return "doc.fill"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
        case "md", "txt": return "doc.text"
        case "json", "yaml", "yml": return "curlybraces"
        case "sh", "bash", "zsh": return "terminal"
        case "html", "css": return "globe"
        default: return "doc"
        }
    }

    // MARK: - Actions

    /// Drop de imagem em qualquer lugar da área de chat → anexa.
    private func handleChatImageDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadObject(ofClass: NSImage.self) { img, _ in
                    if let img = img as? NSImage {
                        DispatchQueue.main.async { attachedImages.append(img) }
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       let img = NSImage(contentsOf: url) {
                        DispatchQueue.main.async { attachedImages.append(img) }
                    }
                }
                handled = true
            }
        }
        return handled
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        Task {
            for url in urls {
                let path = url.path
                if !conversation.referencedFiles.contains(path) {
                    conversation.referencedFiles.append(path)
                    try? modelContext.save()
                }
                if let img = NSImage(contentsOf: url),
                   UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
                    await MainActor.run { attachedImages.append(img) }
                    continue
                }
                if let file = try? await FileIngestionManager.shared.ingest(url: url) {
                    await RAGEngine.shared.index(file: file)
                    await MainActor.run { attachedFiles.append(file) }
                }
            }
        }
    }

    private func restartConversation(from message: Message, withNewContent newContent: String?) {
        providerManager.cancelStreaming()
        guard let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) else { return }
        let content = newContent ?? message.content
        // Branching: arquiva o trecho que será substituído (nada é perdido).
        archiveBranch(fromIndex: idx, label: newContent != nil ? String(localized: "Before editing") : String(localized: "Before restarting"))
        conversation.messages.removeSubrange(idx...)
        conversation.updatedAt = Date()
        try? modelContext.save()
        conversation.messages.append(Message(role: .user, content: content))
        conversation.updatedAt = Date()
        Task {
            do {
                try await providerManager.streamMessage(content: content, conversation: conversation)
                try? modelContext.save()
            } catch {
                await MainActor.run { showErrorToast(error.localizedDescription) }
            }
        }
    }

    // MARK: - Branching (histórico de versões)

    /// Arquiva o trecho de mensagens a partir de `fromIndex` antes de removê-lo,
    /// para que a versão anterior possa ser restaurada. Mantém no máximo 12 versões.
    private func archiveBranch(fromIndex: Int, label: String) {
        guard fromIndex >= 0, fromIndex < conversation.messages.count else { return }
        let removed = conversation.messages[fromIndex...]
        let snapshot = removed.map {
            BranchMessage(role: $0.role.rawValue, content: $0.content, timestamp: $0.timestamp)
        }
        guard !snapshot.isEmpty else { return }
        conversation.versionBranches.append(
            ConversationBranch(fromIndex: fromIndex, label: label, messages: Array(snapshot))
        )
        if conversation.versionBranches.count > 12 {
            conversation.versionBranches.removeFirst(conversation.versionBranches.count - 12)
        }
    }

    /// Restaura uma versão arquivada. Antes, arquiva o estado atual (reversível),
    /// trunca a partir do ponto de origem e recria as mensagens do branch.
    private func restoreBranch(_ branch: ConversationBranch) {
        providerManager.cancelStreaming()
        let idx = min(max(0, branch.fromIndex), conversation.messages.count)
        if idx < conversation.messages.count {
            archiveBranch(fromIndex: idx, label: String(localized: "Before restoring"))
            conversation.messages.removeSubrange(idx...)
        }
        for bm in branch.messages {
            let role = MessageRole(rawValue: bm.role) ?? .assistant
            conversation.messages.append(Message(role: role, content: bm.content, timestamp: bm.timestamp))
        }
        conversation.versionBranches.removeAll { $0.id == branch.id }
        conversation.updatedAt = Date()
        try? modelContext.save()
    }

    private func sendMessage() {
        if dictation.isRecording { dictation.stopRecording() }
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || !attachedFiles.isEmpty || !attachedImages.isEmpty,
              !providerManager.isLoading else { return }

        onFirstMessage?()

        var displayParts: [String] = []
        if !text.isEmpty { displayParts.append(text) }
        if !attachedFiles.isEmpty {
            displayParts.append(attachedFiles.map { "📎 \($0.name)" }.joined(separator: ", "))
        }
        if !attachedImages.isEmpty {
            displayParts.append("🖼 \(attachedImages.count) imagem(ns) anexada(s)")
        }
        let display = displayParts.joined(separator: "\n")

        let modelHasVision = ModelCapabilities.supportsVision(conversation.modelName)
        var llmContent = text.isEmpty ? display : text
        // Modelos COM visão recebem a imagem em base64.
        if !attachedImages.isEmpty && modelHasVision {
            let imgs = attachedImages.compactMap { img -> String? in
                guard let tiff = img.tiffRepresentation,
                      let bmp = NSBitmapImageRep(data: tiff),
                      let jpeg = bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
                else { return nil }
                return "[IMAGE:data:image/jpeg;base64,\(jpeg.base64EncodedString())]"
            }.joined(separator: "\n")
            if !imgs.isEmpty { llmContent += "\n\n" + imgs }
        }
        // Modelos SEM visão: descrição local (OCR + classificação) no lugar do base64.
        let imagesForDescribe = modelHasVision ? [] : attachedImages

        conversation.messages.append(Message(role: .user, content: display))
        messageText = ""
        dictation.transcript = ""
        attachedImages = []
        conversation.updatedAt = Date()
        updateContextTags(from: text)

        let title = conversation.title
        Task {
            // Análise local (Vision) para modelos sem visão: OCR + classificação,
            // anexada como descrição textual da imagem.
            var finalLLM = llmContent
            if !imagesForDescribe.isEmpty {
                let desc = await VisionOCR.describe(in: imagesForDescribe)
                if !desc.isEmpty { finalLLM += "\n\n" + desc }
            }
            do {
                let response = try await providerManager.streamMessage(
                    content: finalLLM, conversation: conversation)
                conversation.updatedAt = Date()
                syncTasksFromAI(response: response,
                                messageID: conversation.messages.last?.id ?? "")
                try modelContext.save()
                if NSApp.isHidden || NSApp.mainWindow?.isKeyWindow == false {
                    AgentNotificationManager.shared.notifyAgentFinished(
                        conversationTitle: title, summary: String(response.prefix(80)))
                }
            } catch {
                await MainActor.run { showErrorToast(error.localizedDescription) }
            }
        }
    }

    private func syncTasksFromAI(response: String, messageID: String) {
        let parsed = ContextManager.extractTasks(from: response, messageID: messageID)
        guard !parsed.isEmpty else { return }
        var changed = false
        for parsedTask in parsed {
            let lowerText = parsedTask.text.lowercased()
            if let idx = conversation.tasks.firstIndex(where: { $0.text.lowercased() == lowerText }) {
                if conversation.tasks[idx].isDone != parsedTask.isDone {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        conversation.tasks[idx].isDone = parsedTask.isDone
                    }
                    changed = true
                }
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    conversation.tasks.append(parsedTask)
                }
                changed = true
            }
        }
        if changed { try? modelContext.save() }
    }

    private func updateContextTags(from text: String) {
        let lower = text.lowercased()
        var tags: Set<String> = Set(conversation.contextTags)
        let tagMap: [(String, String)] = [
            ("swift", "Swift"), ("python", "Python"), ("javascript", "JavaScript"),
            ("typescript", "TypeScript"), ("rust", "Rust"), ("go", "Go"),
            ("sql", "SQL"), ("html", "HTML"), ("css", "CSS"),
            ("docker", "Docker"), ("kubernetes", "K8s"), ("git", "Git"),
            ("api", "API"), ("json", "JSON"), ("machine learning", "ML"), ("ia", "IA")
        ]
        for (keyword, tag) in tagMap where lower.contains(keyword) { tags.insert(tag) }
        conversation.contextTags = Array(tags).sorted().prefix(8).map { $0 }
    }

    private func renderMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private func clearHistory() {
        conversation.messages.removeAll()
        conversation.tasks.removeAll()
        conversation.referencedFiles.removeAll()
        conversation.contextTags.removeAll()
        conversation.updatedAt = Date()
        try? modelContext.save()
    }

    private func deleteConversation() { modelContext.delete(conversation) }

    // MARK: - Error Toast

    private func showErrorToast(_ message: String) {
        errorToast = message
        Task {
            try? await Task.sleep(for: .seconds(6))
            await MainActor.run { if errorToast == message { errorToast = nil } }
        }
    }

    @ViewBuilder
    private var errorBannerView: some View {
        if let msg = errorToast {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13)).foregroundStyle(.orange)
                Text(msg)
                    .font(.system(size: 12)).foregroundStyle(.primary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { errorToast = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: 440)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Rótulo de velocidade de geração durante o streaming.
    private var streamingRateLabel: String {
        let elapsed = providerManager.streamingElapsed
        guard elapsed > 0.4 else { return "\(providerManager.streamingTokenCount) tok" }
        let rate = Double(providerManager.streamingTokenCount) / elapsed
        return String(format: "%.0f tok/s", rate)
    }

    // MARK: - Approval Card

    private func approvalCard(_ pending: ApprovalCoordinator.PendingApproval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: pending.isDestructive ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(pending.isDestructive ? .orange : Color.accentColor)
                Text(pending.summary)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(pending.toolName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            ScrollView {
                Text(pending.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .padding(8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 8) {
                Text("The agent wants to run this action.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Button("Decline") { approval.resolve(false) }
                    .buttonStyle(.bordered)
                Button("Approve") { approval.resolve(true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder((pending.isDestructive ? Color.orange : Color.accentColor).opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Queue (fila de mensagens)

    /// Enfileira a mensagem digitada para enviar quando a resposta atual terminar.
    private func queueMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachedImages.isEmpty else { return }
        queuedMessage = messageText
        messageText = ""
    }

    private func queuedChip(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11)).foregroundStyle(Color.accentColor)
            Text("In queue: \(text)")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button { queuedMessage = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08), in: Capsule())
        .padding(.horizontal, 14).padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            rowH = max(rowH, size.height); x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowH = max(rowH, size.height); x += size.width + spacing
        }
    }
}

// MARK: - Edit Message Sheet

struct EditMessageSheet: View {
    let message: Message
    let onConfirm: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String
    init(message: Message, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.message = message; self.onConfirm = onConfirm; self.onCancel = onCancel
        self._text = State(initialValue: message.content)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit message").font(.system(size: 16, weight: .bold, design: .rounded))
            TextEditor(text: $text)
                .font(.system(size: 14)).frame(minHeight: 120, maxHeight: 300)
                .scrollContentBackground(.hidden).padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            Text("The conversation will restart from this message. The previous version is saved in “Previous versions”.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { onCancel() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Resend") { onConfirm(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 420)
    }
}

// MARK: - Version History Sheet

struct VersionHistorySheet: View {
    let branches: [ConversationBranch]
    let onRestore: (ConversationBranch) -> Void
    let onDelete: (ConversationBranch) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Previous versions")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)

            Text("Excerpts are archived when you edit or restart the conversation. Restoring replaces the current excerpt — reversibly, since the current state is also archived.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20).padding(.bottom, 12)

            Divider()

            if branches.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text("No archived versions")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(branches) { branch in branchRow(branch) }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 480, height: 460)
    }

    private func branchRow(_ branch: ConversationBranch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(branch.label, systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                Spacer()
                Text(branch.createdAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Text(branch.preview)
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text("\(branch.messages.count) messages")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button(role: .destructive) { onDelete(branch) } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button { onRestore(branch) } label: {
                    Text("Restore").font(.system(size: 11, weight: .semibold))
                }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Inspector Section

struct InspectorSection<Content: View>: View {
    let title: String
    let icon: String
    @State private var isExpanded = true
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor)
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded { content().padding(.horizontal, 12).padding(.bottom, 12) }
        }
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Shared UI

struct EmptyStateView: View {
    let modelName: String
    var body: some View {
        VStack(spacing: 20) {
            Text(LumeTheme.greetingEmoji()).font(.system(size: 40))
            VStack(spacing: 6) {
                Text("\(LumeTheme.greeting())!").font(.system(size: 22, weight: .semibold))
                Text("How can I help today?").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                SuggestionChip(icon: "globe", text: String(localized: "Create a website"))
                SuggestionChip(icon: "chevron.left.forwardslash.chevron.right", text: String(localized: "Write code"))
            }
            HStack(spacing: 8) {
                SuggestionChip(icon: "doc.text", text: "Resuma documento")
                SuggestionChip(icon: "sparkles", text: "Explique conceito")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SuggestionChip: View {
    let icon: String; let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(LumeTheme.clay)
            Text(text).font(.system(size: 12))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct AttachmentChipView: View {
    let file: FileIngestionManager.IngestedFile
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: fileIcon).font(.system(size: 11, weight: .medium)).foregroundStyle(LumeTheme.clay)
            VStack(alignment: .leading, spacing: 0) {
                Text(file.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text("~\(file.tokenEstimate) tokens").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
    private var fileIcon: String {
        switch file.type {
        case .pdf: return "doc.fill"
        case .image: return "photo"
        case .docx: return "doc.richtext"
        default: return "doc.plaintext"
        }
    }
}

struct WindowButtonHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = nsView.window {
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        }
    }
}
