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
    @Query private var providerConfigs: [AIProviderConfig]

    @State private var messageText = ""
    @State private var activeArtifact: Artifact? = nil
    @State private var activeToolCalls: [String: [ToolCall]] = [:]
    @State private var workspaceURL: URL? = nil
    @State private var showTerminal = false
    @State private var showInspector = true
    @State private var dictation = VoiceDictationManager()
    @State private var attachedFiles: [FileIngestionManager.IngestedFile] = []
    @State private var attachedImages: [NSImage] = []
    @State private var showFileImporter = false
    @State private var editingMessage: Message? = nil
    @State private var focusInput = false
    @State private var editingNotes = false
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var isAtBottom = true

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                chatHeader
                Divider()
                messageList
                if !attachedFiles.isEmpty { attachmentBar }
                ChatInputView(
                    text: $messageText,
                    placeholder: inputPlaceholder,
                    isLoading: providerManager.isLoading,
                    onSend: sendMessage,
                    onStop: { providerManager.cancelStreaming() },
                    onAttach: { showFileImporter = true },
                    onVoice: { Task { await dictation.toggleRecording() } },
                    isDictating: dictation.isRecording,
                    modelName: conversation.modelName,
                    availableModels: availableModels,
                    onModelChange: { newModel in
                        conversation.modelName = newModel
                        providerManager.changeModel(newModel)
                    },
                    attachedImages: $attachedImages
                )
            }
            .frame(minWidth: 380)
            .background(Color(.windowBackgroundColor))

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
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedFileTypes,
            allowsMultipleSelection: true
        ) { handleFileImport(result: $0) }
        .sheet(isPresented: $showTerminal) {
            TerminalSheetView(workingDirectory: workspaceURL?.path)
        }
        .sheet(item: $editingMessage) { msg in
            EditMessageSheet(message: msg) { newContent in
                restartConversation(from: msg, withNewContent: newContent)
                editingMessage = nil
            } onCancel: { editingMessage = nil }
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
        .alert("Erro no Ditado", isPresented: .constant(dictation.error != nil)) {
            Button("OK") { dictation.error = nil }
        } message: { Text(dictation.error ?? "") }
        .task { await AgentNotificationManager.shared.requestPermission() }
    }

    // MARK: - Chat Header

    private var chatHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Sem título", text: $conversation.title)
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

                    if providerManager.lastCacheHit {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                }
            }

            Spacer()

            if dictation.isRecording {
                HStack(spacing: 5) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                        .shadow(color: .red.opacity(0.6), radius: 3)
                    Text("Gravando…").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            headerButton(icon: "terminal", isActive: false) { showTerminal = true }.help("Terminal")

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
                Button("Exportar como Markdown", action: exportConversation)
                Divider()
                Button("Limpar Cache") { Task { await SemanticCache.shared.clear() } }
                Divider()
                Button("Limpar Histórico", action: clearHistory)
                Divider()
                Button("Deletar Conversa", role: .destructive, action: deleteConversation)
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
                            let sortedMessages = conversation.messages.sorted { $0.timestamp < $1.timestamp }
                            ForEach(sortedMessages, id: \.id) { message in
                                MessageRowView(
                                    message: message,
                                    isStreaming: providerManager.streamingMessageID == message.id,
                                    toolCalls: activeToolCalls[message.id] ?? [],
                                    onArtifactTap: { artifact in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if activeArtifact?.id == artifact.id {
                                                activeArtifact = nil; showInspector = true
                                            } else {
                                                activeArtifact = artifact; showInspector = false
                                            }
                                        }
                                    },
                                    onRestartFrom: {
                                        if message.role == .user {
                                            restartConversation(from: message, withNewContent: nil)
                                        } else {
                                            focusInput = true
                                        }
                                    },
                                    onEdit: { _ in editingMessage = message },
                                    onSuggestionSelected: { selectedOption in
                                        messageText = selectedOption
                                        sendMessage()
                                    }
                                )
                                .id(message.id)
                            }
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

    private var inspectorPanel: some View {
        ScrollView {
            VStack(spacing: 12) {
                InspectorSection(title: "Progresso", icon: "checkmark.circle") {
                    progressContent
                }
                if let project = conversation.project {
                    InspectorSection(title: project.name, icon: project.icon) {
                        projectFilesContent(project)
                    }
                }
                InspectorSection(title: "Contexto", icon: "doc.text.magnifyingglass") {
                    contextContent
                }
                if !conversation.userNotes.isEmpty || editingNotes {
                    InspectorSection(title: "Notas", icon: "note.text") {
                        notesContent
                    }
                } else {
                    Button { editingNotes = true } label: {
                        Label("Adicionar nota", systemImage: "note.text.badge.plus")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .overlay(Divider(), alignment: .leading)
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
                         ? "Processando…"
                         : "O progresso das tarefas aparecerá aqui\nautomaticamente conforme a IA avança.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                let done = conversation.tasks.filter { $0.isDone }.count
                let total = conversation.tasks.count
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(done) de \(total) concluídas")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(Double(done) / Double(max(1, total)) * 100))%")
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
                projectFileRow(icon: "doc.text.fill", name: "Instruções do projeto",
                               color: LumeTheme.clay, action: nil)
            }
            if let localURL = project.localURL {
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: localURL, includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
                )) ?? []
                let sorted = files.filter { !$0.hasDirectoryPath }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                    .prefix(12)
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, url in
                    projectFileRow(icon: fileIcon(for: url.path), name: url.lastPathComponent,
                                   color: .secondary, action: { NSWorkspace.shared.open(url) })
                }
                if files.count > 12 {
                    Text("+ \(files.count - 12) arquivos")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .padding(.leading, 22).padding(.top, 2)
                }
                Divider().opacity(0.4).padding(.vertical, 4)
                Button { NSWorkspace.shared.open(localURL) } label: {
                    Label("Abrir pasta do projeto", systemImage: "folder")
                        .font(.system(size: 11)).foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
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
                    Text("Adicione arquivos para contextualizar a conversa.")
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
                    Label("Adicionar", systemImage: "plus")
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
                    Button("Salvar") { editingNotes = false; try? modelContext.save() }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            } else {
                Text(conversation.userNotes)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .onTapGesture { editingNotes = true }
                Button { editingNotes = true } label: {
                    Label("Editar", systemImage: "pencil")
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

    private var availableModels: [String] {
        let active = providerConfigs.filter { $0.isActive }
        if let match = active.first(where: { $0.providerType == conversation.providerType }) {
            if !match.cachedModels.isEmpty {
                var seen = Set<String>()
                return match.cachedModels.filter { seen.insert($0).inserted }
            }
            switch match.providerType {
            case "openai":    return ["gpt-4o", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo"]
            case "anthropic": return ["claude-opus-4-5", "claude-sonnet-4-5", "claude-3-5-haiku-20241022"]
            default:          return [match.defaultModel]
            }
        }
        return [conversation.modelName]
    }

    private var inputPlaceholder: String {
        if dictation.isRecording { return "Ouvindo…" }
        return attachedFiles.isEmpty
            ? "Mensagem para \(conversation.modelName)… (↩)"
            : "Pergunte sobre os documentos… (↩)"
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
                conversation.messages.append(
                    Message(role: .assistant, content: "**Erro:** \(error.localizedDescription)"))
            }
        }
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

        var llmContent = text.isEmpty ? display : text
        if !attachedImages.isEmpty {
            let imgs = attachedImages.compactMap { img -> String? in
                guard let tiff = img.tiffRepresentation,
                      let bmp = NSBitmapImageRep(data: tiff),
                      let jpeg = bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
                else { return nil }
                return "[IMAGE:data:image/jpeg;base64,\(jpeg.base64EncodedString())]"
            }.joined(separator: "\n")
            if !imgs.isEmpty { llmContent += "\n\n" + imgs }
        }

        conversation.messages.append(Message(role: .user, content: display))
        messageText = ""
        dictation.transcript = ""
        attachedImages = []
        conversation.updatedAt = Date()
        updateContextTags(from: text)

        let title = conversation.title
        Task {
            do {
                let response = try await providerManager.streamMessage(
                    content: llmContent, conversation: conversation)
                conversation.updatedAt = Date()
                syncTasksFromAI(response: response,
                                messageID: conversation.messages.last?.id ?? "")
                try modelContext.save()
                if NSApp.isHidden || NSApp.mainWindow?.isKeyWindow == false {
                    AgentNotificationManager.shared.notifyAgentFinished(
                        conversationTitle: title, summary: String(response.prefix(80)))
                }
            } catch {
                conversation.messages.append(
                    Message(role: .assistant, content: "**Erro:** \(error.localizedDescription)"))
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

    private func exportConversation() {
        let md = conversation.messages
            .map { "**\($0.role.rawValue.capitalized):**\n\n\($0.content)" }
            .joined(separator: "\n\n---\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    private func clearHistory() {
        conversation.messages.removeAll()
        conversation.tasks.removeAll()
        conversation.referencedFiles.removeAll()
        conversation.contextTags.removeAll()
        conversation.updatedAt = Date()
    }

    private func deleteConversation() { modelContext.delete(conversation) }
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
            Text("Editar mensagem").font(.system(size: 16, weight: .bold, design: .rounded))
            TextEditor(text: $text)
                .font(.system(size: 14)).frame(minHeight: 120, maxHeight: 300)
                .scrollContentBackground(.hidden).padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            Text("A conversa será reiniciada a partir desta mensagem.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("Cancelar", role: .cancel) { onCancel() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Reenviar") { onConfirm(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 420)
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
                Text("Como posso ajudar hoje?").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                SuggestionChip(icon: "globe", text: "Crie um site")
                SuggestionChip(icon: "chevron.left.forwardslash.chevron.right", text: "Escreva código")
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

// MARK: - Terminal Sheet
// ✅ Barra customizada estilo macOS com semáforo + título "Lume Terminal"

struct TerminalSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let workingDirectory: String?
    @State private var isHoveringClose = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Barra de título customizada ──────────────────────
            ZStack {
                // Fundo da barra — cinza escuro igual à imagem
                Color(red: 0.18, green: 0.18, blue: 0.18)

                // Título centralizado
                Text("Lume Terminal")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 0.85))

                // Botões semáforo à esquerda
                HStack(spacing: 6) {
                    // ✅ Vermelho — fecha
                    Button { dismiss() } label: {
                        Circle()
                            .fill(isHoveringClose
                                  ? Color(red: 1.0, green: 0.27, blue: 0.22)
                                  : Color(red: 0.92, green: 0.25, blue: 0.20))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Image(systemName: "xmark")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(.black.opacity(isHoveringClose ? 0.7 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringClose = $0 }

                    // Amarelo — decorativo
                    Circle()
                        .fill(Color(red: 0.95, green: 0.73, blue: 0.10))
                        .frame(width: 12, height: 12)

                    // Verde — decorativo
                    Circle()
                        .fill(Color(red: 0.15, green: 0.78, blue: 0.25))
                        .frame(width: 12, height: 12)

                    Spacer()
                }
                .padding(.leading, 12)
            }
            .frame(height: 36)

            // ── Terminal ─────────────────────────────────────────
            TerminalView()
                .frame(minWidth: 700, minHeight: 420)
                .background(Color.black)
        }
        .frame(minWidth: 700, minHeight: 456)
        .background(Color.black)
        // ✅ Esconde botões nativos do macOS
        .background(WindowButtonHider())
    }
}

// ✅ Esconde os botões da janela assim que a view entra na hierarquia
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
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        }
    }
}
