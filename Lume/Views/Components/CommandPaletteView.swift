//
//  CommandPaletteView.swift
//  Lume
//
//  Paleta de comandos (⌘K): busca global por título E conteúdo das mensagens,
//  além de ações rápidas. Selecionar abre a conversa correspondente.
//

import SwiftUI

struct CommandPaletteView: View {
    let conversations: [Conversation]
    let onSelectConversation: (Conversation) -> Void
    let onNewConversation: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [Conversation] {
        let q = trimmedQuery
        guard !q.isEmpty else {
            return conversations
                .filter { !$0.isArchived }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(8).map { $0 }
        }
        return conversations
            .filter { c in
                c.title.localizedCaseInsensitiveContains(q) ||
                c.messages.contains { $0.content.localizedCaseInsensitiveContains(q) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(25).map { $0 }
    }

    private var showNewAction: Bool {
        trimmedQuery.isEmpty || "nova conversa".localizedCaseInsensitiveContains(trimmedQuery)
            || "new conversation".localizedCaseInsensitiveContains(trimmedQuery)
    }
    private var showSettingsAction: Bool {
        trimmedQuery.isEmpty || "configurações".localizedCaseInsensitiveContains(trimmedQuery)
            || "settings".localizedCaseInsensitiveContains(trimmedQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Campo de busca
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                TextField("Search conversations, messages, or actions…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { if let first = results.first { open(first) } }
                Text("esc")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if showNewAction || showSettingsAction {
                        sectionLabel(String(localized: "Actions"))
                        if showNewAction {
                            actionRow(icon: "plus.bubble", title: "New conversation", shortcut: "⌘N") {
                                onNewConversation(); dismiss()
                            }
                        }
                        if showSettingsAction {
                            actionRow(icon: "gearshape", title: "Settings", shortcut: "⌘,") {
                                onOpenSettings(); dismiss()
                            }
                        }
                    }

                    if !results.isEmpty {
                        sectionLabel(String(localized: "Conversations"))
                        ForEach(results) { conv in
                            conversationRow(conv)
                        }
                    } else if !trimmedQuery.isEmpty {
                        Text("No results for “\(trimmedQuery)”")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 16)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 580, height: 440)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { focused = true }
    }

    // MARK: - Rows

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.8)
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
    }

    private func actionRow(icon: String, title: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                Text(title).font(.system(size: 14)).foregroundStyle(.primary)
                Spacer()
                Text(shortcut)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaletteRowButtonStyle())
    }

    private func conversationRow(_ conv: Conversation) -> some View {
        Button { open(conv) } label: {
            HStack(spacing: 12) {
                Image(systemName: conv.tags.contains("code") ? "chevron.left.forwardslash.chevron.right"
                                  : conv.project != nil ? "folder" : "bubble.left")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conv.title)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let snippet = matchSnippet(for: conv) {
                        Text(snippet)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(conv.modelName)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(conv.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaletteRowButtonStyle())
    }

    /// Trecho da mensagem que casou com a busca, para dar contexto.
    private func matchSnippet(for conv: Conversation) -> String? {
        let q = trimmedQuery
        guard !q.isEmpty,
              let msg = conv.messages.first(where: { $0.content.localizedCaseInsensitiveContains(q) }),
              let range = msg.content.range(of: q, options: .caseInsensitive)
        else { return nil }
        let start = msg.content.index(range.lowerBound, offsetBy: -30, limitedBy: msg.content.startIndex) ?? msg.content.startIndex
        let end = msg.content.index(range.upperBound, offsetBy: 60, limitedBy: msg.content.endIndex) ?? msg.content.endIndex
        let prefix = start > msg.content.startIndex ? "…" : ""
        let suffix = end < msg.content.endIndex ? "…" : ""
        let fragment = msg.content[start..<end].replacingOccurrences(of: "\n", with: " ")
        return prefix + fragment + suffix
    }

    private func open(_ conv: Conversation) {
        onSelectConversation(conv)
        dismiss()
    }
}

// MARK: - Row Button Style (hover highlight)

private struct PaletteRowButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                (hovering || configuration.isPressed)
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .onHover { hovering = $0 }
    }
}
