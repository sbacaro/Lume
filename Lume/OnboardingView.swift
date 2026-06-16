//
//  OnboardingView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import SwiftData

// MARK: - Onboarding Entry Point

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: OnboardingStep = .welcome
    @State private var animateIn = false

    // Provider setup
    @State private var selectedProvider: ProviderOption = .openai
    @State private var apiKey = ""
    @State private var customBaseURL = ""
    @State private var customModelName = ""
    @State private var isSavingProvider = false
    @State private var providerSaved = false

    // Google Search setup
    @State private var googleAPIKey = UserDefaults.standard.string(forKey: "google_search_api_key") ?? ""
    @State private var googleCX = UserDefaults.standard.string(forKey: "google_search_cx") ?? ""

    // Validation
    @State private var validationError: String? = nil

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case provider = 1
        case search = 2
        case ready = 3

        var title: String {
            switch self {
            case .welcome:  return "Welcome to Lume"
            case .provider: return String(localized: "Connect AI")
            case .search:   return "Web Search"
            case .ready:    return "Tudo pronto!"
            }
        }

        var icon: String {
            switch self {
            case .welcome:  return "sparkles"
            case .provider: return "bolt.fill"
            case .search:   return "globe"
            case .ready:    return "checkmark.seal.fill"
            }
        }
    }

    enum ProviderOption: String, CaseIterable, Identifiable {
        case openai    = "openai"
        case anthropic = "anthropic"
        case custom    = "openai_custom"

        var id: String { rawValue }

        var name: String {
            switch self {
            case .openai:    return "OpenAI"
            case .anthropic: return "Anthropic"
            case .custom:    return "Personalizado"
            }
        }

        var subtitle: String {
            switch self {
            case .openai:    return "GPT-4o, GPT-4 Turbo e outros"
            case .anthropic: return "Claude Opus, Sonnet, Haiku"
            case .custom:    return "Ollama, vLLM, LiteLLM, Portkey…"
            }
        }

        var icon: String {
            switch self {
            case .openai:    return "bolt.fill"
            case .anthropic: return "sparkles"
            case .custom:    return "server.rack"
            }
        }

        var color: Color {
            switch self {
            case .openai:    return Color(red: 0.12, green: 0.78, blue: 0.54)
            case .anthropic: return Color(red: 0.85, green: 0.55, blue: 0.25)
            case .custom:    return Color(red: 0.45, green: 0.45, blue: 0.95)
            }
        }

        var keyPlaceholder: String {
            switch self {
            case .openai:    return "sk-..."
            case .anthropic: return "sk-ant-..."
            case .custom:    return String(localized: "Optional — leave empty if not needed")
            }
        }

        var defaultModel: String {
            switch self {
            case .openai:    return "gpt-4o"
            case .anthropic: return "claude-sonnet-4-5"
            case .custom:    return "llama3"
            }
        }

        var baseURL: String {
            switch self {
            case .openai:    return "https://api.openai.com/v1"
            case .anthropic: return "https://api.anthropic.com"
            case .custom:    return "http://localhost:11434/v1"
            }
        }

        var keyURL: String {
            switch self {
            case .openai:    return "https://platform.openai.com/api-keys"
            case .anthropic: return "https://console.anthropic.com/keys"
            case .custom:    return ""
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.purple.opacity(0.04),
                    Color(.windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 28)
                    .padding(.horizontal, 40)

                Group {
                    switch currentStep {
                    case .welcome:  welcomeStep
                    case .provider: providerStep
                    case .search:   searchStep
                    case .ready:    readyStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(currentStep)

                navigationButtons
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)
            }
        }
        .frame(width: 620, height: 580)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                animateIn = true
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= currentStep.rawValue
                                  ? Color.accentColor
                                  : Color.primary.opacity(0.1))
                            .frame(width: 28, height: 28)
                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(step == currentStep ? .white : .secondary)
                        }
                    }
                    .animation(.spring(response: 0.3), value: currentStep)

                    if step != OnboardingStep.allCases.last {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue
                                  ? Color.accentColor
                                  : Color.primary.opacity(0.1))
                            .frame(height: 2)
                            .animation(.easeInOut(duration: 0.3), value: currentStep)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Step: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.purple.opacity(0.1)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 100, height: 100)
                        .scaleEffect(animateIn ? 1 : 0.5)
                        .opacity(animateIn ? 1 : 0)

                    Image(systemName: "sparkles")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(animateIn ? 1 : 0.3)
                        .opacity(animateIn ? 1 : 0)
                }
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: animateIn)

                VStack(spacing: 10) {
                    Text("Welcome to Lume")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text(String(localized: "Your native AI client for macOS.\nSmart chat, projects, code, and agents — all in one place."))
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 10)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)

                HStack(spacing: 10) {
                    featurePill(icon: "bubble.left.and.text.bubble.right", label: "Chat")
                    featurePill(icon: "checklist", label: "Projects")
                    featurePill(icon: "chevron.left.forwardslash.chevron.right", label: "Code")
                    featurePill(icon: "cpu", label: "Agentes")
                }
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 15)
                .animation(.easeOut(duration: 0.5).delay(0.35), value: animateIn)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private func featurePill(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }

    // MARK: - Step: Provider

    private var providerStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Connect an AI Provider")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Choose where Lume gets its intelligence.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    ForEach(ProviderOption.allCases) { option in
                        providerOptionRow(option)
                    }
                }

                Divider().opacity(0.4)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("API Key", systemImage: "key.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if !selectedProvider.keyURL.isEmpty {
                            Link("Get key →", destination: URL(string: selectedProvider.keyURL)!)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    SecureField(selectedProvider.keyPlaceholder, text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                        .onChange(of: apiKey) { _, _ in validationError = nil }

                    if selectedProvider == .custom {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Base URL", systemImage: "network")
                                .font(.system(size: 13, weight: .semibold))
                            TextField("http://localhost:11434/v1", text: $customBaseURL)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.primary.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                            Label("Default model", systemImage: "cpu")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.top, 4)
                            TextField("llama3, mistral, phi3…", text: $customModelName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.primary.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                    }

                    if let error = validationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if providerSaved {
                        Label("Provider saved successfully!", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(.horizontal, 2)
                .animation(.easeInOut(duration: 0.2), value: validationError)
                .animation(.easeInOut(duration: 0.2), value: providerSaved)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 40)
        }
    }

    private func providerOptionRow(_ option: ProviderOption) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedProvider = option
                apiKey = ""
                providerSaved = false
                validationError = nil
                if option == .custom {
                    customBaseURL = option.baseURL
                    customModelName = option.defaultModel
                }
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(option.color.opacity(selectedProvider == option ? 0.18 : 0.08))
                        .frame(width: 42, height: 42)
                    Image(systemName: option.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(option.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(option.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .strokeBorder(selectedProvider == option
                                      ? Color.accentColor
                                      : Color.primary.opacity(0.2),
                                      lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if selectedProvider == option {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 11, height: 11)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: selectedProvider)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                selectedProvider == option
                    ? AnyShapeStyle(Color.accentColor.opacity(0.06))
                    : AnyShapeStyle(Color.primary.opacity(0.03)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selectedProvider == option
                            ? Color.accentColor.opacity(0.25)
                            : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step: Search

    private var searchStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 72, height: 72)
                        Image(systemName: "globe")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(Color.blue)
                    }

                    Text("Web Search")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DuckDuckGo on by default")
                            .font(.system(size: 13, weight: .semibold))
                        Text("No setup, no key — configured by default.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.green.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.15), lineWidth: 1))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Google Custom Search (optional)", systemImage: "magnifyingglass.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Link("How to set up →",
                             destination: URL(string: "https://developers.google.com/custom-search/v1/introduction")!)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        SecureField("AIzaSy...", text: $googleAPIKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Color.primary.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                            .onChange(of: googleAPIKey) { _, v in
                                UserDefaults.standard.set(v, forKey: "google_search_api_key")
                            }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Search Engine ID (cx)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("xxxxxxxxxxxxxxx", text: $googleCX)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Color.primary.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                            .onChange(of: googleCX) { _, v in
                                UserDefaults.standard.set(v, forKey: "google_search_cx")
                            }
                    }

                    if !googleAPIKey.isEmpty && !googleCX.isEmpty {
                        Label("Google configured!", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.03),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
                .animation(.easeInOut(duration: 0.2), value: googleAPIKey.isEmpty || googleCX.isEmpty)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Step: Ready

    private var readyStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.green.opacity(0.2), Color.accentColor.opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 100, height: 100)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green, Color.accentColor],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(spacing: 10) {
                    Text("All set! 🎉")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(String(localized: "Lume is set up and ready to use.\nHere's what you can do now:"))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                // ✅ Bullet "Ditar por voz" removido
                VStack(spacing: 8) {
                    quickStartRow(
                        icon: "bubble.left.and.text.bubble.right",
                        color: Color.accentColor,
                        title: String(localized: "Start a chat"),
                        subtitle: String(localized: "Ask anything in the Chat tab")
                    )
                    quickStartRow(
                        icon: "folder.badge.plus",
                        color: LumeTheme.clay,
                        title: String(localized: "Create a project"),
                        subtitle: String(localized: "Organize conversations with context and files")
                    )
                    quickStartRow(
                        icon: "terminal",
                        color: LumeTheme.moss,
                        title: String(localized: "Use the code agent"),
                        subtitle: String(localized: "Terminal, Git, and code analysis in the Code tab")
                    )
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private func quickStartRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentStep == .welcome {
                Button("Skip setup") {
                    completeOnboarding()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            } else if currentStep != .ready {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .welcome
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Back")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Spacer()
            }

            Spacer()

            if currentStep == .ready {
                Button {
                    completeOnboarding()
                } label: {
                    HStack(spacing: 6) {
                        Text("Start using Lume")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
            } else if currentStep == .provider {
                HStack(spacing: 8) {
                    if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty || selectedProvider == .custom {
                        Button {
                            Task { await saveProvider() }
                        } label: {
                            HStack(spacing: 6) {
                                if isSavingProvider {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: providerSaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text(providerSaved ? "Saved!" : "Save")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(providerSaved ? Color.green : Color.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                (providerSaved ? Color.green : Color.accentColor).opacity(0.1),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSavingProvider || providerSaved)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentStep = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .ready
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(apiKey.isEmpty && selectedProvider != .custom ? "Skip" : "Next")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .ready
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("Next")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Actions

    private func saveProvider() async {
        isSavingProvider = true
        validationError = nil

        let key = apiKey.trimmingCharacters(in: .whitespaces)
        let baseURL = selectedProvider == .custom
            ? (customBaseURL.isEmpty ? selectedProvider.baseURL : customBaseURL)
            : selectedProvider.baseURL
        let model = selectedProvider == .custom
            ? (customModelName.isEmpty ? selectedProvider.defaultModel : customModelName)
            : selectedProvider.defaultModel

        if selectedProvider != .custom && key.isEmpty {
            validationError = String(localized: "Enter the API Key to continue.")
            isSavingProvider = false
            return
        }

        let config = AIProviderConfig(
            providerType: selectedProvider.rawValue,
            name: selectedProvider.name,
            baseURL: baseURL,
            defaultModel: model
        )
        config.isActive = true
        modelContext.insert(config)

        if !key.isEmpty {
            try? await KeychainManager.shared.saveAPIKey(key, for: config.id)
        }

        try? modelContext.save()

        isSavingProvider = false
        withAnimation(.spring(response: 0.3)) { providerSaved = true }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "lume_onboarding_completed")
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .modelContainer(for: [AIProviderConfig.self], inMemory: true)
}
