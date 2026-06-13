//
//  NewProjectSheet.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import SwiftData

struct NewProjectSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var step: Step = .choose

    enum Step { case choose, fromScratch, importConversation }

    var body: some View {
        Group {
            switch step {
            case .choose:
                chooseView
            case .fromScratch:
                FromScratchView(onDone: { dismiss() }, onBack: { step = .choose })
            case .importConversation:
                ImportConversationView(conversations: conversations,
                                       onDone: { dismiss() }, onBack: { step = .choose })
            }
        }
        .frame(minWidth: 420, maxWidth: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var chooseView: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Criar um novo projeto")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Um lugar dedicado para trabalho contínuo, onde o contexto se acumula ao longo do tempo. Arquivos e instruções ficam em uma pasta no seu computador.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                projectOptionRow(icon: "plus", title: "Começar do zero",
                    subtitle: "Configure uma nova pasta com instruções e arquivos.") { step = .fromScratch }
                projectOptionRow(icon: "tray.and.arrow.down", title: "Importar um projeto",
                    subtitle: "Traga um projeto que você criou no Chat para o Cowork.") { step = .importConversation }
                projectOptionRow(icon: "folder", title: "Usar uma pasta existente",
                    subtitle: "Dê ao Lume uma pasta da qual você já trabalha.") { importExisting() }
            }
        }
        .padding(28)
    }

    private func projectOptionRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.10)).frame(width: 44, height: 44)
                    .overlay(Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(.primary))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func importExisting() {
        Task {
            if let url = await ProjectManager.shared.importExistingFolder() {
                let name = url.lastPathComponent
                let project = Project(name: name, icon: "folder", localPath: url.path)
                modelContext.insert(project)
                try? modelContext.save()
                // ✅ Salva bookmark de segurança para acesso futuro em sandbox
                AIProviderManager.saveBookmark(for: url, projectID: project.id)
                await indexProjectFiles(project)
                dismiss()
            }
        }
    }

    private func indexProjectFiles(_ project: Project) async {
        let files = ProjectManager.shared.listFiles(in: project)
        for url in files {
            if let file = try? await FileIngestionManager.shared.ingest(url: url) {
                await RAGEngine.shared.index(file: file)
            }
        }
    }
}

// MARK: - From Scratch

struct FromScratchView: View {
    @Environment(\.modelContext) private var modelContext
    let onDone: () -> Void
    let onBack: () -> Void

    @State private var name = ""
    @State private var icon = "folder"
    @State private var systemPrompt = "You are a helpful assistant."
    @State private var isCreating = false
    @State private var errorMessage = ""

    let icons = ["folder", "doc.text", "globe", "hammer", "brain",
                 "briefcase", "chart.bar", "graduationcap", "atom", "paintbrush",
                 "star", "heart", "bolt", "leaf", "camera"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Button { onBack() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text("Começar do zero").font(.system(size: 18, weight: .bold, design: .rounded))
            }

            Text("Uma pasta **~/Lume/\(sanitizedName.isEmpty ? "nome-do-projeto" : sanitizedName)** será criada no seu computador.")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Nome do Projeto").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("Meu Projeto", text: $name).textFieldStyle(.roundedBorder)
                if !name.isEmpty {
                    Text("~/Lume/\(sanitizedName)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Ícone").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36, maximum: 40), spacing: 6)], spacing: 6) {
                    ForEach(icons, id: \.self) { i in
                        Button { icon = i } label: {
                            Image(systemName: i).font(.system(size: 14))
                                .frame(width: 34, height: 34)
                                .background(icon == i ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(icon == i ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Instruções para o assistente").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextEditor(text: $systemPrompt)
                    .font(.system(size: 12)).frame(height: 72)
                    .scrollContentBackground(.hidden).padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !errorMessage.isEmpty {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Cancelar", role: .cancel) { onBack() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button {
                    createProject()
                } label: {
                    HStack(spacing: 6) {
                        if isCreating { ProgressView().scaleEffect(0.6) }
                        Text("Criar Projeto")
                    }
                }
                .disabled(name.isEmpty || isCreating)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .onChange(of: name) { _, n in
            systemPrompt = "You are a helpful assistant working on the \(n) project."
        }
    }

    private var sanitizedName: String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-")).inverted)
            .joined()
    }

    private func createProject() {
        guard !name.isEmpty else { return }
        isCreating = true
        Task {
            do {
                let url = try ProjectManager.shared.createProjectFolder(name: name)
                let project = Project(name: name, icon: icon, systemPrompt: systemPrompt, localPath: url.path)
                modelContext.insert(project)
                try modelContext.save()
                // ✅ Salva bookmark para acesso futuro em sandbox
                AIProviderManager.saveBookmark(for: url, projectID: project.id)
                await indexProjectFiles(project)
                onDone()
            } catch {
                errorMessage = "Erro ao criar pasta: \(error.localizedDescription)"
                isCreating = false
            }
        }
    }

    private func indexProjectFiles(_ project: Project) async {
        let files = ProjectManager.shared.listFiles(in: project)
        for url in files {
            if let file = try? await FileIngestionManager.shared.ingest(url: url) {
                await RAGEngine.shared.index(file: file)
            }
        }
    }
}

// MARK: - Import from Conversation

struct ImportConversationView: View {
    @Environment(\.modelContext) private var modelContext
    let conversations: [Conversation]
    let onDone: () -> Void
    let onBack: () -> Void

    @State private var selectedConversationID: String? = nil
    @State private var projectName = ""
    @State private var isImporting = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Button { onBack() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text("Importar um projeto").font(.system(size: 18, weight: .bold, design: .rounded))
            }

            Text("Selecione uma conversa para importar como projeto. O histórico será salvo em **~/Lume/\(projectName.isEmpty ? "..." : projectName)**.")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Nome do Projeto").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("Nome", text: $projectName).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Selecionar Conversa").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if conversations.isEmpty {
                    Text("Nenhuma conversa disponível").font(.system(size: 12)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity).padding(16)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(conversations.prefix(10)) { conv in
                                ConversationRowButton(conv: conv, isSelected: selectedConversationID == conv.id) {
                                    selectedConversationID = conv.id
                                    if projectName.isEmpty { projectName = conv.title }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            if !errorMessage.isEmpty {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Cancelar", role: .cancel) { onBack() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button {
                    importProject()
                } label: {
                    HStack(spacing: 6) {
                        if isImporting { ProgressView().scaleEffect(0.6) }
                        Text("Importar")
                    }
                }
                .disabled(selectedConversationID == nil || projectName.isEmpty || isImporting)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func importProject() {
        guard let convID = selectedConversationID,
              let conv = conversations.first(where: { $0.id == convID }),
              !projectName.isEmpty else { return }
        isImporting = true
        Task {
            do {
                let url = try ProjectManager.shared.importFromConversation(
                    name: projectName, messages: conv.messages)
                let project = Project(name: projectName, icon: "tray.and.arrow.down",
                                      systemPrompt: conv.systemPrompt, localPath: url.path)
                modelContext.insert(project)
                conv.project = project
                try modelContext.save()
                // ✅ Salva bookmark para acesso futuro em sandbox
                AIProviderManager.saveBookmark(for: url, projectID: project.id)
                onDone()
            } catch {
                errorMessage = "Erro ao importar: \(error.localizedDescription)"
                isImporting = false
            }
        }
    }
}

// MARK: - Conversation Row Button

private struct ConversationRowButton: View {
    let conv: Conversation
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conv.title).font(.system(size: 13)).lineLimit(1).foregroundStyle(.primary)
                    Text("\(conv.messages.count) mensagens · \(conv.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
