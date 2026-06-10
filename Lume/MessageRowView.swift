//
//  MessageRowView.swift
//  Lume
//

import SwiftUI

struct MessageRowView: View {
    let message: Message
    var isStreaming: Bool = false
    var toolCalls: [ToolCall] = []
    var onArtifactTap: ((Artifact) -> Void)? = nil
    var thinkingTracker: ThinkingTracker? = nil
    var onRestartFrom: (() -> Void)? = nil
    var onEdit: ((String) -> Void)? = nil
    var onSuggestionSelected: ((String) -> Void)? = nil

    @State private var isHovering = false
    @State private var copied = false

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
                    .font(.system(size: 14))
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
            Text(timeLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize()

            HStack(spacing: 2) {
                actionButton(icon: "arrow.counterclockwise", help: "Reiniciar conversa a partir daqui") {
                    onRestartFrom?()
                }
                actionButton(icon: "pencil", help: "Editar mensagem") {
                    onEdit?(message.content)
                }
                actionButton(icon: copied ? "checkmark" : "doc.on.doc", help: "Copiar mensagem") {
                    copyMessage()
                }
            }
            .opacity(isHovering ? 1 : 0)
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
                if let tracker = thinkingTracker,
                   (isStreaming || !tracker.steps.isEmpty) {
                    ThinkingPanelView(tracker: tracker, isStreaming: isStreaming)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

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
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let artifact = message.artifact {
                    artifactChip(artifact)
                }

                if isStreaming && message.content.isEmpty && toolCalls.isEmpty && thinkingTracker == nil {
                    thinkingIndicator
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
        HStack(spacing: 2) {
            actionButton(
                icon: copied ? "checkmark" : "doc.on.doc",
                help: "Copiar resposta"
            ) {
                copyMessage()
            }

            actionButton(
                icon: "arrow.turn.down.right",
                help: "Continuar a partir daqui"
            ) {
                onRestartFrom?()
            }
        }
        .frame(height: 28)
        .opacity(isHovering && !isStreaming ? 1 : 0)
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
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.98, green: 0.55, blue: 0.25),
                             Color(red: 0.85, green: 0.30, blue: 0.65)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 28, height: 28)
                .shadow(color: Color.orange.opacity(0.3), radius: 6, y: 2)
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in ThinkingDot(delay: Double(i) * 0.2) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
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

// MARK: - ThinkingDot

private struct ThinkingDot: View {
    let delay: Double
    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0.25

    var body: some View {
        Circle()
            .fill(.primary.opacity(0.5))
            .frame(width: 7, height: 7)
            .scaleEffect(scale).opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)) {
                    scale = 1.0; opacity = 1.0
                }
            }
    }
}
