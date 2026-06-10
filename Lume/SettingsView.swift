//
//  SettingsView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = SettingsTab.providers

    enum SettingsTab: String, CaseIterable {
        case providers  = "Providers"
        case agent      = "Agente"
        case style      = "Estilo"
        case mcp        = "MCP"
        case workflows  = "Workflows"
        case tasks      = "Tarefas"
        case advanced   = "Avançado"

        var icon: String {
            switch self {
            case .providers: return "bolt.fill"
            case .agent:     return "cpu"
            case .style:     return "paintbrush.fill"
            case .mcp:       return "puzzlepiece.extension.fill"
            case .workflows: return "arrow.triangle.branch"
            case .tasks:     return "calendar.badge.clock"
            case .advanced:  return "gear.badge"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // ── Sidebar esquerda ─────────────────────────────────
            VStack(spacing: 2) {
                HStack {
                    Text("Configurações")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)

                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 20)
                                .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                            Text(tab.rawValue)
                                .font(.system(size: 13))
                                .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab
                                ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                                : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }

                Spacer()

                // ✅ Botão Fechar no rodapé
                Divider().opacity(0.4).padding(.horizontal, 8)
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("Fechar")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .frame(width: 190)
            .background(.ultraThinMaterial)

            Divider().opacity(0.5)

            Group {
                switch selectedTab {
                case .providers: ProviderSettingsContent()
                case .agent:     AgentSettingsView()
                case .style:     StyleSettingsView()
                case .mcp:       MCPSettingsView()
                case .workflows: WorkflowSettingsView()
                case .tasks:     TaskSettingsView()
                case .advanced:  AdvancedSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.windowBackgroundColor).opacity(0.6))
        }
        .frame(minWidth: 640, idealWidth: 720, maxWidth: .infinity,
               minHeight: 440, idealHeight: 500, maxHeight: .infinity)
    }
}

// MARK: - Agent Settings

struct AgentSettingsView: View {
    @State private var config = LumeConfig.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsSection("Modo de Aprovação") {
                    ForEach(ApprovalMode.allCases, id: \.self) { mode in
                        Button {
                            config.approvalMode = mode
                            config.save()
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(config.approvalMode == mode
                                              ? Color.accentColor.opacity(0.15)
                                              : Color.primary.opacity(0.05))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(config.approvalMode == mode ? Color.accentColor : Color.secondary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.label).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                                    Text(mode.description).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if config.approvalMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color.accentColor)
                                        .symbolRenderingMode(.hierarchical)
                                }
                            }
                            .padding(10)
                            .background(
                                config.approvalMode == mode
                                    ? AnyShapeStyle(Color.accentColor.opacity(0.06))
                                    : AnyShapeStyle(.ultraThinMaterial),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        config.approvalMode == mode ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                settingsSection("Limites") {
                    HStack {
                        Text("Máx. iterações do agente")
                        Spacer()
                        Stepper("\(config.maxAgentIterations)", value: $config.maxAgentIterations, in: 1...50)
                            .onChange(of: config.maxAgentIterations) { _, _ in config.save() }
                    }
                    .font(.system(size: 13))
                    Divider().opacity(0.4)
                    HStack {
                        Text("Tokens máximos de contexto")
                        Spacer()
                        Picker("", selection: $config.maxContextTokens) {
                            Text("8k").tag(8_000)
                            Text("12k").tag(12_000)
                            Text("32k").tag(32_000)
                            Text("100k").tag(100_000)
                        }
                        .frame(width: 90)
                        .onChange(of: config.maxContextTokens) { _, _ in config.save() }
                    }
                    .font(.system(size: 13))
                }

                settingsSection("Otimizações") {
                    Toggle("Roteamento automático de modelos", isOn: $config.enableModelRouting)
                        .onChange(of: config.enableModelRouting) { _, _ in config.save() }
                    Divider().opacity(0.4)
                    Toggle("Cache semântico", isOn: $config.enableSemanticCache)
                        .onChange(of: config.enableSemanticCache) { _, _ in config.save() }
                    Divider().opacity(0.4)
                    Toggle("RAG em documentos", isOn: $config.enableRAG)
                        .onChange(of: config.enableRAG) { _, _ in config.save() }
                    Divider().opacity(0.4)
                    Toggle("Prompt Caching (Anthropic)", isOn: $config.enablePromptCaching)
                        .onChange(of: config.enablePromptCaching) { _, _ in config.save() }
                }
                .font(.system(size: 13))
            }
            .padding(24)
        }
    }
}

// MARK: - Style Settings

struct StyleSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [StyleProfile]

    private var activeProfile: StyleProfile? {
        profiles.first(where: { $0.isDefault }) ?? profiles.first
    }

    var body: some View {
        Group {
            if let profile = activeProfile {
                StyleProfileDetailView(profile: profile)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                        .symbolRenderingMode(.hierarchical)
                    Text("Nenhum perfil de estilo")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Um perfil padrão será criado automaticamente.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Criar perfil padrão") {
                        let p = StyleProfile(
                            name: "Padrão",
                            tone: "balanced",
                            verbosity: "balanced",
                            language: "pt-BR",
                            customInstructions: ""
                        )
                        p.isDefault = true
                        modelContext.insert(p)
                        try? modelContext.save()
                        StyleSettingsView.syncDefaultProfile(profiles: [p])
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if profiles.isEmpty {
                let p = StyleProfile(
                    name: "Padrão",
                    tone: "balanced",
                    verbosity: "balanced",
                    language: "pt-BR",
                    customInstructions: ""
                )
                p.isDefault = true
                modelContext.insert(p)
                try? modelContext.save()
                StyleSettingsView.syncDefaultProfile(profiles: [p])
            }
        }
    }

    static func syncDefaultProfile(profiles: [StyleProfile]) {
        if let active = profiles.first(where: { $0.isDefault }) {
            UserDefaults.standard.set(active.systemPromptSuffix, forKey: "active_style_suffix")
        } else {
            UserDefaults.standard.removeObject(forKey: "active_style_suffix")
        }
    }
}

struct StyleProfileDetailView: View {
    @Bindable var profile: StyleProfile
    @Environment(\.modelContext) private var modelContext
    @Query private var allProfiles: [StyleProfile]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                settingsSection("Tom de Resposta") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach([
                            ("formal",    "Formal",      "briefcase",           "Profissional e objetivo"),
                            ("casual",    "Casual",      "bubble.left",         "Amigável e descontraído"),
                            ("technical", "Técnico",     "terminal",            "Preciso e especializado"),
                            ("creative",  "Criativo",    "paintbrush",          "Expressivo e original"),
                            ("balanced",  "Balanceado",  "slider.horizontal.3", "Neutro e adaptável"),
                        ], id: \.0) { value, label, icon, desc in
                            Button {
                                profile.tone = value
                                try? modelContext.save()
                                syncIfDefault()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: icon)
                                        .font(.system(size: 13))
                                        .foregroundStyle(profile.tone == value ? Color.accentColor : Color.secondary)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(label).font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text(desc).font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if profile.tone == value {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(10)
                                .background(
                                    profile.tone == value
                                        ? AnyShapeStyle(Color.accentColor.opacity(0.08))
                                        : AnyShapeStyle(Color.primary.opacity(0.04)),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(profile.tone == value ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                settingsSection("Verbosidade") {
                    HStack(spacing: 8) {
                        ForEach([
                            ("concise",  "Conciso",     "Respostas curtas"),
                            ("balanced", "Equilibrado", "Tamanho adequado"),
                            ("detailed", "Detalhado",   "Explicações completas"),
                        ], id: \.0) { value, label, desc in
                            Button {
                                profile.verbosity = value
                                try? modelContext.save()
                                syncIfDefault()
                            } label: {
                                VStack(spacing: 4) {
                                    Text(label)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(profile.verbosity == value ? Color.accentColor : Color.primary)
                                    Text(desc)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    profile.verbosity == value
                                        ? AnyShapeStyle(Color.accentColor.opacity(0.08))
                                        : AnyShapeStyle(Color.primary.opacity(0.04)),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(profile.verbosity == value ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                settingsSection("Instruções Personalizadas") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Adicionadas ao final do system prompt em todas as conversas.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $profile.customInstructions)
                            .font(.system(size: 12))
                            .frame(minHeight: 80, maxHeight: 160)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .onChange(of: profile.customInstructions) { _, _ in
                                try? modelContext.save()
                                syncIfDefault()
                            }
                    }
                }

                if !profile.systemPromptSuffix.isEmpty {
                    settingsSection("Preview do System Prompt") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Este texto será adicionado automaticamente ao system prompt:")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(profile.systemPromptSuffix)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.04),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func syncIfDefault() {
        if profile.isDefault {
            UserDefaults.standard.set(profile.systemPromptSuffix, forKey: "active_style_suffix")
        }
    }
}

// MARK: - MCP Settings

struct MCPSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var connectors: [MCPConnector]
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(connectors) { MCPConnectorRow(connector: $0) }
                    .onDelete { offsets in offsets.forEach { modelContext.delete(connectors[$0]) } }
            }
            .listStyle(.inset).scrollContentBackground(.hidden)
            .overlay {
                if connectors.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 32)).foregroundStyle(.tertiary).symbolRenderingMode(.hierarchical)
                        Text("Nenhum conector MCP").font(.system(size: 13, weight: .medium))
                        Text("Conecte o agente a ferramentas externas").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
            }
            Divider().opacity(0.4)
            HStack {
                Button("Adicionar Conector") { showAdd = true }.buttonStyle(.borderedProminent)
                Spacer()
                Link("Sobre MCP →", destination: URL(string: "https://modelcontextprotocol.io")!)
                    .font(.system(size: 11)).foregroundStyle(Color.accentColor)
            }
            .padding()
        }
        .sheet(isPresented: $showAdd) { AddMCPConnectorSheet().presentationBackground(.ultraThinMaterial) }
    }
}

struct MCPConnectorRow: View {
    @Bindable var connector: MCPConnector
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(connector.name).font(.system(size: 13, weight: .medium))
                Text(connector.transport == "stdio" ? connector.command : connector.url)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $connector.isEnabled).labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct AddMCPConnectorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var transport = "stdio"
    @State private var command = ""
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Novo Conector MCP").font(.system(size: 18, weight: .bold, design: .rounded))
            TextField("Nome", text: $name).textFieldStyle(.roundedBorder)
            Picker("Transporte", selection: $transport) {
                Text("stdio").tag("stdio"); Text("HTTP/SSE").tag("http")
            }.pickerStyle(.segmented)
            if transport == "stdio" {
                TextField("Comando", text: $command).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
            } else {
                TextField("URL", text: $url).textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Cancelar", role: .cancel) { dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Adicionar") {
                    let c = MCPConnector(name: name, transport: transport, command: command, url: url)
                    modelContext.insert(c); try? modelContext.save(); dismiss()
                }
                .disabled(name.isEmpty || (transport == "stdio" ? command.isEmpty : url.isEmpty))
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 420)
    }
}

// MARK: - Workflow Settings

struct WorkflowSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workflows: [Workflow]

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(workflows) { WorkflowRow(workflow: $0) }
                    .onDelete { offsets in offsets.forEach { modelContext.delete(workflows[$0]) } }
            }
            .listStyle(.inset).scrollContentBackground(.hidden)
            .overlay {
                if workflows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 28)).foregroundStyle(.tertiary)
                        Text("Nenhum workflow").foregroundStyle(.secondary)
                    }
                }
            }
            Divider().opacity(0.4)
            HStack {
                Text("Editor de workflows em breve").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
            }.padding()
        }
    }
}

struct WorkflowRow: View {
    let workflow: Workflow
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name).font(.system(size: 13, weight: .medium))
                Text("\(workflow.steps.count) steps · \(workflow.triggerType)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if let last = workflow.lastRunAt {
                Text(last.formatted(.relative(presentation: .named))).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Task Settings

struct TaskSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduledTask.scheduledAt) private var tasks: [ScheduledTask]

    var body: some View {
        List {
            ForEach(tasks) { task in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).font(.system(size: 13, weight: .medium))
                        Text(task.scheduledAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if task.isCompleted { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green).symbolRenderingMode(.hierarchical) }
                    Text(task.recurrence).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .onDelete { offsets in offsets.forEach { modelContext.delete(tasks[$0]) } }
        }
        .listStyle(.inset).scrollContentBackground(.hidden)
        .overlay {
            if tasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 28)).foregroundStyle(.tertiary).symbolRenderingMode(.hierarchical)
                    Text("Nenhuma tarefa agendada").foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var config = LumeConfig.load()
    @State private var googleAPIKey = UserDefaults.standard.string(forKey: "google_search_api_key") ?? ""
    @State private var googleCX     = UserDefaults.standard.string(forKey: "google_search_cx") ?? ""
    @State private var showOnboarding = false
    @State private var showResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                settingsSection("Idioma do App") {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Idioma da Interface")
                                .font(.system(size: 13, weight: .medium))
                            Text("O idioma do Lume segue as preferências do sistema macOS.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
                            )
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "globe")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Abrir Preferências")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.accentColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                settingsSection("Busca na Web") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Google Custom Search (opcional)")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Sem configuração, usa DuckDuckGo gratuitamente.\nPara usar o Google, obtenha as chaves em developers.google.com/custom-search")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            SecureField("AIzaSy...", text: $googleAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: googleAPIKey) { _, v in
                                    UserDefaults.standard.set(v, forKey: "google_search_api_key")
                                }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Search Engine ID (cx)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            TextField("xxxxxxxxxxxxxxx", text: $googleCX)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: googleCX) { _, v in
                                    UserDefaults.standard.set(v, forKey: "google_search_cx")
                                }
                        }
                        HStack {
                            if !googleAPIKey.isEmpty && !googleCX.isEmpty {
                                Label("Google configurado", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.green)
                            } else {
                                Label("Usando DuckDuckGo", systemImage: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Link("Como obter as chaves →",
                                 destination: URL(string: "https://developers.google.com/custom-search/v1/introduction")!)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .font(.system(size: 13))

                settingsSection("Segurança") {
                    Toggle("Bloquear comandos shell perigosos", isOn: $config.blockDangerousShellCommands)
                        .onChange(of: config.blockDangerousShellCommands) { _, _ in config.save() }
                    Divider().opacity(0.4)
                    Toggle("Exigir workspace para operações de arquivo", isOn: $config.requireWorkspaceForFileOps)
                        .onChange(of: config.requireWorkspaceForFileOps) { _, _ in config.save() }
                }
                .font(.system(size: 13))

                settingsSection("Arquivo de Configuração") {
                    HStack {
                        Text(LumeConfig.configFilePath)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Revelar") {
                            NSWorkspace.shared.selectFile(LumeConfig.configFilePath, inFileViewerRootedAtPath: "")
                        }
                        .font(.system(size: 11))
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                settingsSection("Primeiros Passos") {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Assistente de configuração")
                                .font(.system(size: 13, weight: .medium))
                            Text("Reconfigure providers, busca na web e veja dicas do app.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            UserDefaults.standard.set(false, forKey: "lume_onboarding_completed")
                            showOnboarding = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                                Text("Abrir").font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.accentColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                settingsSection("Reset") {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Limpar dados do app")
                                .font(.system(size: 13, weight: .medium))
                            Text("Apaga conversas, projetos, tarefas e workflows. As configurações são preservadas.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            showResetConfirmation = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                                Text("Resetar").font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.red, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
        .alert("Resetar aplicação?", isPresented: $showResetConfirmation) {
            Button("Cancelar", role: .cancel) { }
            Button("Resetar", role: .destructive) {
                resetAppData()
            }
        } message: {
            Text("Esta ação apagará todas as conversas, projetos, tarefas e workflows, mas manterá suas configurações de providers, segurança e preferências.\n\nEsta ação não pode ser desfeita.")
        }
    }

    private func resetAppData() {
        // Deletar todas as conversas
        var conversationDescriptor = FetchDescriptor<Conversation>()
        if let conversations = try? modelContext.fetch(conversationDescriptor) {
            conversations.forEach { modelContext.delete($0) }
        }

        // Deletar todos os projetos
        var projectDescriptor = FetchDescriptor<Project>()
        if let projects = try? modelContext.fetch(projectDescriptor) {
            projects.forEach { modelContext.delete($0) }
        }

        // Deletar todas as tarefas agendadas
        var taskDescriptor = FetchDescriptor<ScheduledTask>()
        if let tasks = try? modelContext.fetch(taskDescriptor) {
            tasks.forEach { modelContext.delete($0) }
        }

        // Deletar todos os workflows
        var workflowDescriptor = FetchDescriptor<Workflow>()
        if let workflows = try? modelContext.fetch(workflowDescriptor) {
            workflows.forEach { modelContext.delete($0) }
        }

        // Salvar mudanças
        do {
            try modelContext.save()
        } catch {
            print("❌ Erro ao resetar dados: \(error)")
        }
    }
}

// MARK: - Provider Settings Content

struct ProviderSettingsContent: View {
    @State private var providerManager = AIProviderManager()
    var body: some View {
        ProviderSettingsView(providerManager: providerManager)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helpers

@ViewBuilder
func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.8)
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private func settingsRow<Content: View>(
    _ label: String,
    @ViewBuilder trailing: () -> Content
) -> some View {
    HStack {
        Text(label).font(.system(size: 13))
        Spacer()
        trailing()
    }
}
