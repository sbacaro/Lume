//
//  ProviderSettingsView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import SwiftData

struct ProviderSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AIProviderConfig.createdAt) private var providers: [AIProviderConfig]
    var providerManager: AIProviderManager

    @State private var showAddProvider = false
    @State private var selectedProvider: AIProviderConfig?

    var body: some View {
        VStack(spacing: 0) {

            // ── Provider chips no topo ───────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(providers) { provider in
                        ProviderChip(
                            provider: provider,
                            isSelected: selectedProvider?.id == provider.id
                        ) {
                            selectedProvider = provider
                        }
                    }
                    Button {
                        showAddProvider = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.lumeSecondaryCompact)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(.ultraThinMaterial)

            Divider().opacity(0.4)

            // ── Detalhe do provider selecionado ──────────────────
            if let provider = selectedProvider ?? providers.first {
                ProviderDetailView(
                    provider: provider,
                    providerManager: providerManager
                )
                .id(provider.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                        .symbolRenderingMode(.hierarchical)
                    Text("Add a provider to get started")
                        .foregroundStyle(.secondary)
                    Button("Add Provider") { showAddProvider = true }
                        .buttonStyle(.lumePrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddProvider) {
            AddProviderView()
        }
        .onAppear {
            if selectedProvider == nil {
                selectedProvider = providers.first
            }
        }
    }
}

// MARK: - Provider Chip

struct ProviderChip: View {
    let provider: AIProviderConfig
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                        .frame(width: 22, height: 22)
                    Image(systemName: providerIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Color.secondary)
                }
                Text(provider.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                if provider.isActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                        .shadow(color: .green.opacity(0.6), radius: 2)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                    : AnyShapeStyle(isHovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.04)),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private var providerIcon: String {
        switch provider.providerType {
        case "openai":        return "bolt.fill"
        case "anthropic":     return "sparkles"
        case "openai_custom": return "gearshape.2.fill"
        default:              return "questionmark"
        }
    }
}

// MARK: - Provider Detail View

struct ProviderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var provider: AIProviderConfig
    var providerManager: AIProviderManager

    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var validationMessage = ""
    @State private var showPassword = false
    @State private var isFetchingModels = false
    @State private var fetchError = ""
    @State private var maxTokensText = ""

    private var staticModels: [String] {
        switch provider.providerType {
        case "openai":    return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        case "anthropic": return ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
        default:          return []
        }
    }

    private var displayedModels: [String] {
        let models = provider.cachedModels.isEmpty ? staticModels : provider.cachedModels
        var seen = Set<String>()
        return models.filter { seen.insert($0).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Nome + Tipo ──────────────────────────────────
                HStack(spacing: 16) {
                    settingsSection("Name") {
                        TextField("Provider Name", text: $provider.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    settingsSection("Tipo") {
                        Text(provider.providerType.capitalized.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 13))
                            .padding(7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                // ── Base URL (custom) ────────────────────────────
                if provider.providerType == "openai_custom" {
                    settingsSection("Base URL") {
                        TextField("https://api.example.com/v1", text: $provider.baseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // ── API Key ──────────────────────────────────────
                settingsSection("API Key") {
                    HStack(spacing: 8) {
                        Group {
                            if showPassword {
                                TextField("Paste your API Key here", text: $apiKey)
                            } else {
                                SecureField("Paste your API Key here", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await validateAndSaveProviderTask() }
                        } label: {
                            HStack(spacing: 5) {
                                if isValidating {
                                    ProgressView().scaleEffect(0.6).frame(width: 12)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                }
                                Text(isValidating ? "Validating…" : "Validate and Save")
                            }
                        }
                        .buttonStyle(.lumePrimary)
                        .disabled(apiKey.isEmpty || isValidating)
                    }

                    if !validationMessage.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: validationMessage.contains("✓") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(validationMessage.contains("✓") ? Color.green : Color.orange)
                            Text(validationMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Modelos — Picker dropdown ─────────────────────
                settingsSection(String(localized: "Default Model")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(String(localized: "\(displayedModels.count) models available"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                Task { await fetchModels() }
                            } label: {
                                HStack(spacing: 4) {
                                    if isFetchingModels {
                                        ProgressView().scaleEffect(0.6)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 10))
                                    }
                                    Text(isFetchingModels ? "Searching…" : "Refresh list")
                                }
                            }
                            .buttonStyle(.lumeSecondaryCompact)
                            .disabled(isFetchingModels || apiKey.isEmpty)
                        }

                        if !fetchError.isEmpty {
                            Text(fetchError).font(.caption2).foregroundStyle(.red)
                        }

                        if displayedModels.isEmpty {
                            Text("Save the API Key and click Refresh to load the models.")
                                .font(.caption2).foregroundStyle(.tertiary)
                        } else {
                            // ✅ Picker dropdown — limpo e sem duplicatas
                            Picker("", selection: $provider.defaultModel) {
                                ForEach(displayedModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .onChange(of: provider.defaultModel) { _, _ in saveProvider() }

                            if !provider.cachedModels.isEmpty {
                                Text("\(provider.cachedModels.count) models loaded from the server.")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                // ── Temperatura + Max Tokens ─────────────────────
                HStack(alignment: .top, spacing: 16) {
                    settingsSection("Temperatura (\(String(format: "%.1f", provider.temperature)))") {
                        VStack(spacing: 4) {
                            Slider(value: $provider.temperature, in: 0...2, step: 0.1)
                            HStack {
                                Text("Precise").font(.system(size: 10)).foregroundStyle(.tertiary)
                                Spacer()
                                Text("Creative").font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                    }

                    settingsSection(String(localized: "Max tokens")) {
                        HStack(spacing: 6) {
                            TextField("Auto", text: $maxTokensText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .onSubmit { applyMaxTokens() }
                                .onChange(of: maxTokensText) { _, _ in applyMaxTokens() }
                            ForEach([0, 4096, 8192, 32768], id: \.self) { val in
                                let isSelected = provider.maxTokens == val
                                Button(val == 0 ? "Auto" : "\(val/1024)k") {
                                    provider.maxTokens = val
                                    maxTokensText = val == 0 ? "" : "\(val)"
                                    saveProvider()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(
                                    isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.20)) : AnyShapeStyle(Color.primary.opacity(0.06)),
                                    in: Capsule()
                                )
                                .contentShape(Capsule())
                            }
                        }
                    }
                }

                // ── Active Toggle + Salvar + Delete ─────────────
                HStack {
                    Toggle(isOn: $provider.isActive) {
                        HStack(spacing: 6) {
                            Text("Active Provider")
                                .font(.system(size: 13, weight: .semibold))
                            if provider.isActive {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                    .shadow(color: .green.opacity(0.6), radius: 2)
                            }
                        }
                    }
                    .onChange(of: provider.isActive) { _, _ in saveProvider() }

                    Spacer()

                    Button {
                        saveProvider()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(.lumePrimary)
                    .keyboardShortcut(.defaultAction)

                    Button(role: .destructive) {
                        deleteProvider()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.lumeDestructive)
                }
            }
            .padding(20)
        }
        .task(id: provider.id) {
            apiKey = await KeychainManager.shared.retrieveAPIKey(for: provider.id)
            validationMessage = ""
            fetchError = ""
            maxTokensText = provider.maxTokens > 0 ? "\(provider.maxTokens)" : ""
        }
    }

    // MARK: - Helpers

    private func applyMaxTokens() {
        if maxTokensText.isEmpty {
            provider.maxTokens = 0
        } else if let val = Int(maxTokensText), val >= 0 {
            provider.maxTokens = val
        }
    }

    private func fetchModels() async {
        guard !apiKey.isEmpty else { return }
        isFetchingModels = true
        fetchError = ""
        do {
            let tempProvider: AIProvider
            switch provider.providerType {
            case "openai":
                tempProvider = OpenAIProvider(apiKey: apiKey)
            case "anthropic":
                tempProvider = AnthropicProvider(apiKey: apiKey)
            default:
                // Todos os providers OpenAI-compatible (openai_custom, litellm, ollama,
                // vllm, tgi, portkey, etc.) usam o mesmo endpoint /models
                guard !provider.baseURL.isEmpty, let url = URL(string: provider.baseURL) else {
                    fetchError = String(localized: "Configure the Base URL before fetching models")
                    isFetchingModels = false
                    return
                }
                tempProvider = OpenAIProvider(apiKey: apiKey, baseURL: url)
            }
            // Remove duplicatas preservando a ordem (gateways às vezes repetem modelos).
            var seen = Set<String>()
            let models = try await tempProvider.fetchAvailableModels().filter { seen.insert($0).inserted }
            provider.cachedModels = models
            if !models.isEmpty && !models.contains(provider.defaultModel) {
                provider.defaultModel = models[0]
            }
            try? modelContext.save()
            validationMessage = String(localized: "✓ \(models.count) models loaded")
        } catch {
            fetchError = String(localized: "Error fetching models: \(error.localizedDescription)")
        }
        isFetchingModels = false
    }

    private func validateAndSaveProviderTask() async {
        guard !apiKey.isEmpty else { return }
        isValidating = true
        validationMessage = ""
        do {
            let isValid = try await providerManager.validateProvider(config: provider, apiKey: apiKey)
            try await KeychainManager.shared.saveAPIKey(apiKey, for: provider.id)
            validationMessage = isValid ? "✓ Chave salva e validada!" : "✓ Chave salva."
            saveProvider()
            try? await providerManager.activateProvider(config: provider, apiKey: apiKey)
            await fetchModels()
        } catch {
            try? await KeychainManager.shared.saveAPIKey(apiKey, for: provider.id)
            saveProvider()
            try? await providerManager.activateProvider(config: provider, apiKey: apiKey)
            validationMessage = String(localized: "Key saved. Connectivity error.")
        }
        isValidating = false
    }

    private func saveProvider() {
        do { try modelContext.save() } catch {
            validationMessage = String(localized: "Error saving: \(error.localizedDescription)")
        }
    }

    private func deleteProvider() {
        Task {
            try? await KeychainManager.shared.deleteAPIKey(for: provider.id)
            modelContext.delete(provider)
            try? modelContext.save()
        }
    }
}

// MARK: - Add Provider View

struct AddProviderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType = "openai"
    @State private var providerName = ""
    @State private var apiKey = ""
    @State private var baseURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add New Provider")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Picker("Provider Type", selection: $selectedType) {
                Text("OpenAI").tag("openai")
                Text("Anthropic").tag("anthropic")
                Text("Custom (OpenAI)").tag("openai_custom")
            }
            .pickerStyle(.segmented)

            TextField("Name (e.g. My ChatGPT, Local Llama)", text: $providerName)
                .textFieldStyle(.roundedBorder)

            if selectedType == "openai_custom" {
                TextField("Base URL (e.g. https://api.example.com/v1)", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            SecureField("API Key (optional for some servers)", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            Text(providerDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.lumeSecondary)
                Spacer()
                Button("Add") { addProvider() }
                    .buttonStyle(.lumePrimary)
                    .disabled(providerName.isEmpty || (selectedType == "openai_custom" && baseURL.isEmpty))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, maxWidth: 440)
    }

    private var providerDescription: String {
        switch selectedType {
        case "openai":        return String(localized: "Official OpenAI provider. Requires an API Key from platform.openai.com")
        case "anthropic":     return String(localized: "Official Anthropic provider. Requires an API Key from console.anthropic.com")
        case "openai_custom": return String(localized: "OpenAI-compatible server (LiteLLM, Ollama, vLLM, etc). After saving, click Refresh to load the models.")
        default: return ""
        }
    }

    private func addProvider() {
        let finalBaseURL: String
        let finalDefaultModel: String
        switch selectedType {
        case "openai":
            finalBaseURL = "https://api.openai.com/v1"
            finalDefaultModel = "gpt-4o"
        case "anthropic":
            finalBaseURL = "https://api.anthropic.com/v1"
            finalDefaultModel = "claude-opus-4-8"
        case "openai_custom":
            finalBaseURL = baseURL
            finalDefaultModel = "default"
        default: return
        }
        let config = AIProviderConfig(
            providerType: selectedType,
            name: providerName,
            baseURL: finalBaseURL,
            defaultModel: finalDefaultModel
        )
        if selectedType == "openai_custom" { config.maxTokens = 0 }
        modelContext.insert(config)
        Task {
            if !apiKey.isEmpty {
                try? await KeychainManager.shared.saveAPIKey(apiKey, for: config.id)
            }
            try? modelContext.save()
            dismiss()
        }
    }
}
