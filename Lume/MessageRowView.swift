//
//  MessageRowView.swift
//  Lume
//

import SwiftUI

struct MessageRowView: View {
    let message: Message
    var isStreaming: Bool = false
    var streamingActivity: String? = nil
    var toolCalls: [ToolCall] = []
    var isThinkingExpanded: Bool = false
    var onToggleThinking: (() -> Void)? = nil
    var onArtifactTap: ((Artifact) -> Void)? = nil
    var onRestartFrom: (() -> Void)? = nil
    var onEdit: ((String) -> Void)? = nil
    var onSuggestionSelected: ((String) -> Void)? = nil

    @State private var isHovering = false
    @State private var copied = false
    @State private var savedMemory = false
    @AppStorage("lume.messageFontScale") private var messageFontScale: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if message.role == .user {
                userMessage
            } else {
                assistantMessage
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    // MARK: - User Message

    private var userMessage: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 14 * CGFloat(messageFontScale)))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                    )

                userActionBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    // MARK: - User Action Bar

    private var userActionBar: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                actionButton(icon: "arrow.counterclockwise", help: "Reiniciar conversa a partir daqui") {
                    onRestartFrom?()
                }
                actionButton(icon: "pencil", help: "Editar mensagem") {
                    onEdit?(message.content)
                }
                actionButton(icon: savedMemory ? "checkmark" : "brain", help: "Salvar na memória") {
                    MemoryStore.shared.add(message.content)
                    withAnimation(.easeInOut(duration: 0.15)) { savedMemory = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.easeInOut(duration: 0.15)) { savedMemory = false }
                    }
                }
                actionButton(icon: copied ? "checkmark" : "doc.on.doc", help: "Copiar mensagem") {
                    copyMessage()
                }
            }
            .opacity(isHovering ? 1 : 0)

            Text(timeLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .frame(height: 28)
    }

    // MARK: - Shared action button

    private func actionButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Time label

    private var timeLabel: String {
        let elapsed = Date().timeIntervalSince(message.timestamp)
        let sixHours: TimeInterval = 6 * 3600
        if elapsed < sixHours {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: message.timestamp)
        } else {
            let hours = Int(elapsed / 3600)
            if hours < 24 { return "há \(hours)h" }
            return "há \(hours / 24)d"
        }
    }

    // MARK: - Assistant Message

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            assistantAvatar
                .padding(.top, 3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 10) {
                if !toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(toolCalls) { AgentToolCallView(toolCall: $0) }
                    }
                }

                if !message.content.isEmpty {
                    MarkdownTextView(
                        text: message.content,
                        isStreaming: isStreaming,
                        onSuggestionSelected: onSuggestionSelected
                    )
                    .environment(\.markdownFontScale, CGFloat(messageFontScale))
                    // Largura de leitura confortável em janelas largas (linhas não ficam enormes)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !message.ragSources.isEmpty {
                    ragSourcesView
                }

                if let artifact = message.artifact {
                    artifactChip(artifact)
                }

                if isStreaming {
                    HStack(spacing: 8) {
                        StarLoaderView(starSize: 16)
                        if let activity = streamingActivity, !activity.isEmpty {
                            Text(activity)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                                .id(activity)
                        }
                    }
                    .padding(.top, 2)
                    .animation(.easeInOut(duration: 0.2), value: streamingActivity)
                }

                assistantActionBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    // MARK: - Assistant Action Bar

    private var assistantActionBar: some View {
        let isSpeaking = SpeechManager.shared.speakingID == message.id
        return HStack(spacing: 4) {
            Text(timeLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize()

            HStack(spacing: 2) {
                actionButton(
                    icon: copied ? "checkmark" : "doc.on.doc",
                    help: "Copiar resposta"
                ) {
                    copyMessage()
                }

                actionButton(
                    icon: isSpeaking ? "stop.circle" : "speaker.wave.2",
                    help: isSpeaking ? "Parar leitura" : "Ler em voz alta"
                ) {
                    SpeechManager.shared.toggle(id: message.id, text: message.content)
                }

                actionButton(
                    icon: "arrow.turn.down.right",
                    help: "Continuar a partir daqui"
                ) {
                    onRestartFrom?()
                }
            }
            .opacity((isHovering || isSpeaking) && !isStreaming ? 1 : 0)
        }
        .frame(height: 28)
    }

    // MARK: - Artifact Chip

    private func artifactChip(_ artifact: Artifact) -> some View {
        Button { onArtifactTap?(artifact) } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: artifactIcon(for: artifact.type))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary).lineLimit(1)
                    Text(artifactTypeLabel(for: artifact.type))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var assistantAvatar: some View {
        // Mesma marca do ícone do app (squircle + estrela de 4 pontas).
        LumeMark(size: 28)
    }

    private var ragSourcesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fontes")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.6)
            FlowLayout(spacing: 6) {
                ForEach(message.ragSources) { source in
                    RAGSourceChip(source: source)
                }
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: 760, alignment: .leading)
    }

    private func artifactIcon(for type: ArtifactType) -> String {
        switch type {
        case .html: return "globe"
        case .svg: return "square.on.square.squareshape.controlhandles"
        case .javascript: return "chevron.left.forwardslash.chevron.right"
        case .css: return "paintbrush"
        case .react: return "atom"
        case .mermaid: return "arrow.triangle.branch"
        case .markdown: return "doc.text"
        case .unknown: return "doc"
        }
    }

    private func artifactTypeLabel(for type: ArtifactType) -> String {
        switch type {
        case .html: return "HTML Preview"
        case .svg: return "SVG Graphic"
        case .javascript: return "JavaScript"
        case .css: return "Stylesheet"
        case .react: return "React Component"
        case .mermaid: return "Diagram"
        case .markdown: return "Markdown"
        case .unknown: return "Artifact"
        }
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.15)) { copied = false }
        }
    }
}

// MARK: - View Extension

private extension View {
    func flexibleFrame(minWidth: CGFloat? = nil, maxWidth: CGFloat? = nil) -> some View {
        self.frame(minWidth: minWidth, maxWidth: maxWidth)
    }
}

// MARK: - RAG Source Chip

private struct RAGSourceChip: View {
    let source: RAGSource
    @State private var showPopover = false

    var body: some View {
        Button { showPopover.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 9))
                Text("\(source.document) · \(source.chunkIndex + 1)/\(source.totalChunks)")
                    .font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(source.document).font(.system(size: 12, weight: .semibold))
                Text("Trecho \(source.chunkIndex + 1) de \(source.totalChunks) · relevância \(String(format: "%.0f%%", min(max(source.score, 0), 1) * 100))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Divider()
                ScrollView {
                    Text(source.snippet)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            .padding(14).frame(width: 320)
        }
    }
}
