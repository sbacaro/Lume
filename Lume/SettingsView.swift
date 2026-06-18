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
        case agent      = "Agent"
        case github     = "GitHub"
        case style      = "Style"
        case memory     = "Memory"
        case mcp        = "MCP"
        case workflows  = "Workflows"
        case tasks      = "Tasks"
        case advanced   = "Advanced"

        /// Localized display title (rawValue stays a stable English identifier).
        var title: LocalizedStringKey {
            switch self {
            case .providers: return "Providers"
            case .agent:     return "Agent"
            case .github:    return "GitHub"
            case .style:     return "Style"
            case .memory:    return "Memory"
            case .mcp:       return "MCP"
            case .workflows: return "Workflows"
            case .tasks:     return "Tasks"
            case .advanced:  return "Advanced"
            }
        }

        var icon: String {
            switch self {
            case .providers: return "bolt.fill"
            case .agent:     return "cpu"
            case .github:    return "chevron.left.forwardslash.chevron.right"
            case .style:     return "paintbrush.fill"
            case .memory:    return "brain.head.profile"
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
                    Text("Settings")
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
                            Text(tab.title)
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
                        Text("Close")
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
                case .github:    GitHubSettingsView()
                case .style:     StyleSettingsView()
                case .memory:    MemorySettingsView()
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
    @State private var cacheCleared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsSection(String(localized: "Approval Mode")) {
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
                        Text("Max. agent iterations")
                        Spacer()
                        Stepper("\(config.maxAgentIterations)", value: $config.maxAgentIterations, in: 1...50)
                            .onChange(of: config.maxAgentIterations) { _, _ in config.save() }
                    }
                    .font(.system(size: 13))
                    Divider().opacity(0.4)
                    HStack {
                        Text("Max context tokens")
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

                settingsSection(String(localized: "Optimizations")) {
                    Toggle("Automatic model routing", isOn: $config.enableModelRouting)
                        .onChange(of: config.enableModelRouting) { _, _ in config.save() }
                    Divider().opacity(0.4)
                    Toggle("Semantic cache", isOn: $config.enableSemanticCache)
                        .onChange(of: config.enableSemanticCache) { _, _ in config.save() }
                    HStack {
                        Text("Repeated answers come from the cache. Clear it if you see old/wrong answers.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button {
                            Task { await SemanticCache.shared.clear() }
                            cacheCleared = true
                        } label: {
                            Label(cacheCleared ? "Cache cleared ✓" : "Clear cache", systemImage: "trash")
                                .font(.system(size: 11))
                        }
                        .disabled(cacheCleared)
                    }
                    Divider().opacity(0.4)
                    Toggle("RAG on documents", isOn: $config.enableRAG)
                        .onChange(of: config.enableRAG) { _, _ in config.save() }
                    Divider().opacity(0.4)
                    Toggle("Prompt Caching (Anthropic)", isOn: $config.enablePromptCaching)
                        .onChange(of: config.enablePromptCaching) { _, _ in config.save() }
                    Divider().opacity(0.4)
                    Toggle("Persistent memory", isOn: $config.enableMemory)
                        .onChange(of: config.enableMemory) { _, _ in config.save() }
                }
                .font(.system(size: 13))
            }
            .padding(24)
        }
    }
}

// MARK: - Memory Settings

struct MemorySettingsView: View {
    @State private var store = MemoryStore.shared
    @State private var newText = ""
    @State private var newCategory: MemoryCategory = .general
    @State private var editingID: String?
    @State private var editingText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsSection(String(localized: "Add memory")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Facts the AI should remember across all conversations (e.g., \"I work at Rumo Logística\", \"I prefer concise answers in Portuguese\")."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Picker("", selection: $newCategory) {
                                ForEach(MemoryCategory.allCases, id: \.self) { c in
                                    Label(c.label, systemImage: c.icon).tag(c)
                                }
                            }
                            .labelsHidden().frame(width: 150)
                            TextField("New memory…", text: $newText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addMemory() }
                            Button("Add") { addMemory() }
                                .buttonStyle(.lumePrimaryCompact)
                                .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                settingsSection(String(localized: "Memories (\(store.items.count))")) {
                    if store.items.isEmpty {
                        Text("No memories yet. You can also save memories directly from a message, using the brain button.")
                            .font(.system(size: 12)).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(store.items) { item in
                            memoryRow(item)
                            if item.id != store.items.last?.id { Divider().opacity(0.3) }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func memoryRow(_ item: MemoryItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.categoryEnum.icon)
                .font(.system(size: 12))
                .foregroundStyle(item.isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            if editingID == item.id {
                TextField("", text: $editingText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitEdit(item) }
                Button("OK") { commitEdit(item) }.buttonStyle(.lumePrimaryCompact)
            } else {
                Text(item.content)
                    .font(.system(size: 12))
                    .foregroundStyle(item.isEnabled ? .primary : .secondary)
                    .strikethrough(!item.isEnabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { editingID = item.id; editingText = item.content }
            }

            Toggle("", isOn: Binding(get: { item.isEnabled }, set: { _ in store.toggle(item) }))
                .labelsHidden().controlSize(.mini)
                .help(item.isEnabled ? "Active" : "Disabled")

            Button { store.delete(item) } label: {
                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Delete")
        }
        .padding(.vertical, 4)
    }

    private func addMemory() {
        store.add(newText, category: newCategory)
        newText = ""
    }

    private func commitEdit(_ item: MemoryItem) {
        var updated = item
        updated.content = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !updated.content.isEmpty { store.update(updated) }
        editingID = nil
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
                    Text("No style profile")
                        .font(.system(size: 15, weight: .semibold))
                    Text("A default profile will be created automatically.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Create default profile") {
                        let p = StyleProfile(
                            name: "Default",
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
                    .buttonStyle(.lumePrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if profiles.isEmpty {
                let p = StyleProfile(
                    name: "Default",
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

                settingsSection(String(localized: "Response Tone")) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach([
                            ("formal",    String(localized: "Formal"),      "briefcase",           String(localized: "Professional and objective")),
                            ("casual",    String(localized: "Casual"),      "bubble.left",         String(localized: "Friendly and relaxed")),
                            ("technical", String(localized: "Technical"),     "terminal",            String(localized: "Precise and specialized")),
                            ("creative",  "Creative",    "paintbrush",          String(localized: "Expressive and original")),
                            ("balanced",  String(localized: "Balanced"),  "slider.horizontal.3", String(localized: "Neutral and adaptable")),
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

                settingsSection(String(localized: "Verbosity")) {
                    HStack(spacing: 8) {
                        ForEach([
                            ("concise",  String(localized: "Concise"),     String(localized: "Short answers")),
                            ("balanced", String(localized: "Balanced"), String(localized: "Appropriate length")),
                            ("detailed", String(localized: "Detailed"),   String(localized: "Full explanations")),
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

                settingsSection(String(localized: "Custom Instructions")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Appended to the end of the system prompt in all conversations.")
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
                    settingsSection(String(localized: "System Prompt Preview")) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("This text will be automatically added to the system prompt:")
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
                        Text("No MCP connector").font(.system(size: 13, weight: .medium))
                        Text("Connect the agent to external tools").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
            }
            Divider().opacity(0.4)
            HStack(spacing: 10) {
                Button("Add Connector") { showAdd = true }.buttonStyle(.lumePrimary)
                Button("Connect / Refresh") {
                    Task { await MCPManager.shared.syncConnectors(connectors) }
                }
                .buttonStyle(.lumeSecondary)
                .disabled(connectors.allSatisfy { !$0.isEnabled })
                if !MCPManager.shared.discoveredTools.isEmpty {
                    Text("\(MCPManager.shared.discoveredTools.count) tools")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Link("About MCP →", destination: URL(string: "https://modelcontextprotocol.io")!)
                    .font(.system(size: 11)).foregroundStyle(Color.accentColor)
            }
            .padding()
        }
        .task { await MCPManager.shared.syncConnectors(connectors) }
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
            Text("New MCP Connector").font(.system(size: 18, weight: .bold, design: .rounded))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            Picker("Transport", selection: $transport) {
                Text("stdio").tag("stdio"); Text("HTTP/SSE").tag("http")
            }.pickerStyle(.segmented)
            if transport == "stdio" {
                TextField("Command", text: $command).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
            } else {
                TextField("URL", text: $url).textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(.lumeSecondary)
                Spacer()
                Button("Add") {
                    let c = MCPConnector(name: name, transport: transport, command: command, url: url)
                    modelContext.insert(c); try? modelContext.save(); dismiss()
                }
                .disabled(name.isEmpty || (transport == "stdio" ? command.isEmpty : url.isEmpty))
                .buttonStyle(.lumePrimary)
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
                        Text("No workflows").foregroundStyle(.secondary)
                    }
                }
            }
            Divider().opacity(0.4)
            HStack {
                Text("Workflow editor coming soon").font(.system(size: 11)).foregroundStyle(.tertiary)
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
                    Text("No scheduled tasks").foregroundStyle(.secondary)
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
    @AppStorage("lume.messageFontScale") private var messageFontScale: Double = 1.0
    @AppStorage(ThemeKeys.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                settingsSection(String(localized: "Message Appearance")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Text size")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker("", selection: $messageFontScale) {
                                Text("Small").tag(0.85)
                                Text("Default").tag(1.0)
                                Text("Large").tag(1.15)
                                Text("Extra").tag(1.3)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 280)
                        }
                        Text("Preview")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        MarkdownTextView(text: String(localized: "The **Lume** renders tables, lists, and code.\n\n| Model | Window |\n|---|---:|\n| Opus 4.8 | 200k |\n| GPT-4o | 128k |\n\n- [x] Tables\n- [ ] More themes"))
                            .environment(\.markdownFontScale, CGFloat(messageFontScale))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                settingsSection(String(localized: "Theme")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Appearance").font(.system(size: 12, weight: .medium))
                            Spacer()
                            Picker("", selection: $appearanceRaw) {
                                ForEach(AppearanceChoice.allCases) { c in
                                    Label(c.label, systemImage: c.icon).tag(c.rawValue)
                                }
                            }
                            .pickerStyle(.segmented).frame(width: 260)
                        }
                    }
                }

                LanguageSettingsSection()

                settingsSection("Web Search") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Google Custom Search (optional)")
                                .font(.system(size: 12, weight: .semibold))
                            Text(String(localized: "No setup, uses DuckDuckGo for free.\nTo use Google, get the keys at developers.google.com/custom-search"))
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
                                Label("Google configured", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.green)
                            } else {
                                Label("Using DuckDuckGo", systemImage: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Link("How to get the keys →",
                                 destination: URL(string: "https://developers.google.com/custom-search/v1/introduction")!)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .font(.system(size: 13))

                settingsSection(String(localized: "Security")) {
                    Toggle("Block dangerous shell commands", isOn: $config.blockDangerousShellCommands)
                        .onChange(of: config.blockDangerousShellCommands) { _, _ in config.save() }
                    Divider().opacity(0.4)
                    Toggle("Require a workspace for file operations", isOn: $config.requireWorkspaceForFileOps)
                        .onChange(of: config.requireWorkspaceForFileOps) { _, _ in config.save() }
                }
                .font(.system(size: 13))

                settingsSection(String(localized: "Configuration File")) {
                    HStack {
                        Text(LumeConfig.configFilePath)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Reveal") {
                            NSWorkspace.shared.selectFile(LumeConfig.configFilePath, inFileViewerRootedAtPath: "")
                        }
                        .buttonStyle(.lumeSecondaryCompact)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                settingsSection(String(localized: "Getting Started")) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Setup assistant")
                                .font(.system(size: 13, weight: .medium))
                            Text("Reconfigure providers, web search, and see app tips.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            UserDefaults.standard.set(false, forKey: "lume_onboarding_completed")
                            showOnboarding = true
                        } label: {
                            Label("Open", systemImage: "sparkles")
                        }
                        .buttonStyle(.lumePrimary)
                    }
                }

                settingsSection("Reset") {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Clear app data")
                                .font(.system(size: 13, weight: .medium))
                            Text("Deletes conversations, projects, tasks, and workflows. Settings are preserved.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            showResetConfirmation = true
                        } label: {
                            Label("Reset", systemImage: "trash")
                        }
                        .buttonStyle(.lumeDestructive)
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView().environment(\.modelContext, modelContext)
        }
        .alert("Reset application?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetAppData()
            }
        } message: {
            Text(String(localized: "This action will delete all conversations, projects, tasks, and workflows, but will keep your provider, security, and preference settings.\n\nThis action cannot be undone."))
        }
    }

    private func resetAppData() {
        // Deletar todas as conversas
        let conversationDescriptor = FetchDescriptor<Conversation>()
        if let conversations = try? modelContext.fetch(conversationDescriptor) {
            conversations.forEach { modelContext.delete($0) }
        }

        // Deletar todos os projetos
        let projectDescriptor = FetchDescriptor<Project>()
        if let projects = try? modelContext.fetch(projectDescriptor) {
            projects.forEach { modelContext.delete($0) }
        }

        // Deletar todas as tarefas agendadas
        let taskDescriptor = FetchDescriptor<ScheduledTask>()
        if let tasks = try? modelContext.fetch(taskDescriptor) {
            tasks.forEach { modelContext.delete($0) }
        }

        // Deletar todos os workflows
        let workflowDescriptor = FetchDescriptor<Workflow>()
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
    @State private var providerManager = AIProviderManager.shared
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

// MARK: - In-app language selection

/// Available interface languages. `system` follows macOS; others force a per-app language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case portuguese = "pt-BR"

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system:     return "System"
        case .english:    return "English"
        case .portuguese: return "Portuguese (Brazil)"
        }
    }

    /// The language code currently applied via `AppleLanguages`, mapped back to a case.
    static var current: AppLanguage {
        guard let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
              let first = langs.first else { return .system }
        if first.hasPrefix("pt") { return .portuguese }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    /// Applies the language by writing `AppleLanguages`, then relaunches the app.
    func applyAndRestart() {
        let defaults = UserDefaults.standard
        switch self {
        case .system:
            defaults.removeObject(forKey: "AppleLanguages")
        case .english, .portuguese:
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
        defaults.synchronize()

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

struct LanguageSettingsSection: View {
    @AppStorage("app_language") private var stored = AppLanguage.current.rawValue
    @State private var selection = AppLanguage.current
    @State private var showRestartConfirm = false

    var body: some View {
        settingsSection(String(localized: "App Language")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Interface Language")
                            .font(.system(size: 13, weight: .medium))
                        Text("Choose the app language. Lume restarts to apply the change.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $selection) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                if selection != AppLanguage.current {
                    HStack {
                        Spacer()
                        Button {
                            showRestartConfirm = true
                        } label: {
                            Label("Apply and Restart", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.lumePrimary)
                    }
                }
            }
        }
        .confirmationDialog(
            "Restart Lume to apply the new language?",
            isPresented: $showRestartConfirm,
            titleVisibility: .visible
        ) {
            Button("Restart") {
                stored = selection.rawValue
                selection.applyAndRestart()
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}
