//
//  ChatInputView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct ChatInputView: View {
    @Binding var text: String
    let placeholder: String
    let isLoading: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onAttach: () -> Void
    let onVoice: () -> Void
    var onQueue: () -> Void = {}
    let isDictating: Bool
    let modelName: String
    let availableModels: [String]
    let onModelChange: (String) -> Void
    /// Seleção dentro do submenu de um provider: troca o modelo E ativa o provider
    /// correspondente (evita ficar com o modelo de um provider e o backend de outro).
    var onProviderModelSelect: (AIProviderConfig, String) -> Void = { _, _ in }

    @Binding var attachedImages: [NSImage]

    @Query(filter: #Predicate<AIProviderConfig> { $0.isActive })
    private var activeProviders: [AIProviderConfig]

    @FocusState private var isFocused: Bool
    @State private var isDropTargeted = false
    @State private var approvalMode: ApprovalMode = LumeConfig.load().approvalMode
    @AppStorage(ThemeKeys.accent) private var accentRaw = AccentChoice.clay.rawValue

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.2)

            if !attachedImages.isEmpty {
                imagePreviewBar
            }

            pillContent
                .background { pillBackground }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            isDropTargeted
                                ? Color.accentColor.opacity(0.6)
                                : Color.white.opacity(0.15),
                            lineWidth: isDropTargeted ? 2 : 1
                        )
                }
                .shadow(
                    color: isLoading
                        ? Color.accentColor.opacity(0.25)
                        : Color.black.opacity(0.08),
                    radius: isLoading ? 12 : 4,
                    y: 2
                )
                .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
                    handleImageDrop(providers: providers)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .onAppear { isFocused = true }
    }

    // MARK: - Image Preview Bar

    private var imagePreviewBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachedImages.enumerated()), id: \.offset) { idx, img in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                        Button {
                            attachedImages.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.5), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .overlay(Divider(), alignment: .bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Pill content

    private var pillContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // TextEditor — sempre primeiro para definir o tamanho do ZStack
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .frame(minHeight: 36, maxHeight: 160)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isFocused)
                    .foregroundStyle(composerVibrant ? Color.white : Color.primary)
                    .onKeyPress(.return) {
                        let flags = NSApp.currentEvent?.modifierFlags ?? []
                        if flags.contains(.shift) { return .ignored }
                        onSend()
                        return .handled
                    }
                    .onPasteCommand(of: [.image]) { providers in
                        for provider in providers {
                            _ = provider.loadObject(ofClass: NSImage.self) { img, _ in
                                if let img = img as? NSImage {
                                    DispatchQueue.main.async { attachedImages.append(img) }
                                }
                            }
                        }
                    }

                // Placeholder alinhado com o cursor nativo do NSTextView
                // top=5 e leading=5 correspondem ao textContainerInset padrão do SwiftUI wrapper
                if text.isEmpty && !isDictating {
                    Text(isLoading ? "Gerando resposta…" : placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(
                            composerVibrant ? Color.white.opacity(0.85) : Color(.placeholderTextColor)
                        )
                        // Alinhado com o início do texto/cursor do TextEditor.
                        // (Se precisar de ajuste fino, este é o número a mexer.)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                if isDictating {
                    DictatingWaveView()
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Bottom toolbar — estilo Claude: ações à esquerda, modelo + enviar à direita
            HStack(spacing: 6) {
                pillActionBtn(
                    icon: "plus",
                    help: "Anexar arquivo",
                    tint: composerVibrant ? Color.white.opacity(0.7) : nil,
                    action: onAttach
                )

                approvalMenu

                Spacer()

                if !attachedImages.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "photo").font(.system(size: 10))
                        Text("\(attachedImages.count)").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                }

                modelMenu

                rightActionButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .animation(.easeInOut(duration: 0.18), value: hasContent)
            .animation(.easeInOut(duration: 0.18), value: isLoading)
        }
    }

    // MARK: - Model menu (texto discreto, à direita — estilo Claude)

    private var modelMenu: some View {
        Menu {
            if !activeProviders.isEmpty {
                ForEach(activeProviders) { provider in
                    let models = modelsFor(provider)
                    if !models.isEmpty {
                        Menu(provider.name) {
                            ForEach(models, id: \.self) { model in
                                Button { onProviderModelSelect(provider, model) } label: {
                                    if model == modelName {
                                        Label(model, systemImage: "checkmark")
                                    } else {
                                        Text(model)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                ForEach(Self.dedup(availableModels), id: \.self) { model in
                    Button { onModelChange(model) } label: {
                        if model == modelName {
                            Label(model, systemImage: "checkmark")
                        } else { Text(model) }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(shortModelName(modelName))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(composerVibrant ? Color.white : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(composerVibrant ? Color.black.opacity(0.22) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(composerVibrant ? Color.white : Color(.secondaryLabelColor))
        .fixedSize()
    }

    // MARK: - Approval menu (Perguntar antes de agir / Agir sem perguntar)

    private var approvalMenu: some View {
        Menu {
            Button { setApprovalMode(.strict) } label: {
                if approvalMode != .autonomous {
                    Label("Perguntar antes de agir", systemImage: "checkmark")
                } else {
                    Text("Perguntar antes de agir")
                }
            }
            Button { setApprovalMode(.autonomous) } label: {
                if approvalMode == .autonomous {
                    Label("Agir sem perguntar", systemImage: "checkmark")
                } else {
                    Text("Agir sem perguntar")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: approvalMode == .autonomous ? "forward.fill" : "hand.raised")
                    .font(.system(size: 11, weight: .medium))
                Text(approvalMode == .autonomous ? "Agir" : "Perguntar")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(composerVibrant ? Color.white : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(composerVibrant ? Color.black.opacity(0.22) : Color.primary.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(composerVibrant ? Color.white : Color(.secondaryLabelColor))
        .fixedSize()
        .help(approvalMode == .autonomous
              ? "Lume executa ações sem pedir aprovação"
              : "Lume pausa para você aprovar cada ação")
    }

    private func setApprovalMode(_ mode: ApprovalMode) {
        approvalMode = mode
        var cfg = LumeConfig.load()
        cfg.approvalMode = mode
        cfg.save()
    }

    // MARK: - Right action button (mic → enviar → parar/fila — estilo Claude)

    @ViewBuilder
    private var rightActionButton: some View {
        if isLoading {
            HStack(spacing: 8) {
                // Parar a geração atual
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .background(
                            Color(.controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Parar (⌘.)")
                .keyboardShortcut(".", modifiers: .command)

                // Enfileirar: envia a mensagem digitada quando a resposta atual terminar
                if hasContent {
                    Button(action: onQueue) {
                        HStack(spacing: 5) {
                            Image(systemName: "return")
                                .font(.system(size: 11, weight: .bold))
                            Text("Fila")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Enfileirar — envia ao terminar a resposta")
                    .transition(.scale.combined(with: .opacity))
                }
            }
        } else if canSend {
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Enviar (↩)")
            .transition(.scale.combined(with: .opacity))
        } else {
            // Campo vazio: microfone (ditado)
            Button(action: onVoice) {
                Image(systemName: isDictating ? "waveform" : "mic")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isDictating ? .red : Color(.secondaryLabelColor))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(isDictating ? "Parar gravação" : "Ditado")
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Há conteúdo para enviar/enfileirar (texto ou imagens), independente do estado de carregamento.
    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || !attachedImages.isEmpty
    }

    // MARK: - Liquid Glass background

    private var pillBackground: some View {
        ZStack {
            Color(.windowBackgroundColor).opacity(0.01)

            if isLoading {
                // Estado de processamento — ESTÁTICO (sem animação) para não pesar a CPU.
                LinearGradient(
                    colors: accentGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(isTyping ? 0.16 : 0.6)

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(isTyping ? 0.86 : 0.45)
            } else {
                // Visual estático de hoje (sem animação fora do processamento).
                Rectangle().fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        themeAccent.opacity(isFocused ? 0.06 : 0.02),
                        themeAccent.opacity(isFocused ? 0.03 : 0.01),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isLoading)
        .animation(.easeInOut(duration: 0.35), value: isTyping)
    }

    // MARK: - Estado visual da caixa

    /// Usuário está digitando (há texto) — usado para clarear a animação.
    private var isTyping: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Estado "vibrante" (fundo animado intenso): processando E sem texto.
    /// Quando o usuário digita, a caixa clareia e o texto volta a ser legível.
    private var composerVibrant: Bool { isLoading && !isTyping }

    /// Cor de acento do tema atual (concreta — base da animação).
    private var themeAccent: Color { (AccentChoice(rawValue: accentRaw) ?? .clay).color }

    /// Variações dentro da mesma paleta (mesmo matiz, brilho/saturação variando)
    /// para uma animação fluida e on-brand durante o processamento.
    private var accentGradientColors: [Color] {
        // Tons quentes vibrantes da marca (laranja → coral → rosa → âmbar),
        // visíveis e on-palette para a animação de processamento.
        [
            Color(red: 0.97, green: 0.55, blue: 0.30),
            Color(red: 0.95, green: 0.45, blue: 0.45),
            Color(red: 0.93, green: 0.42, blue: 0.60),
            Color(red: 0.98, green: 0.64, blue: 0.35),
            Color(red: 0.97, green: 0.55, blue: 0.30),
        ]
    }

    // MARK: - Drag & Drop

    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
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

    // MARK: - Helpers

    private var canSend: Bool {
        (!text.trimmingCharacters(in: .whitespaces).isEmpty || !attachedImages.isEmpty) && !isLoading
    }

    private func modelsFor(_ provider: AIProviderConfig) -> [String] {
        // Prioriza modelos buscados da API do provider
        if !provider.cachedModels.isEmpty { return Self.dedup(provider.cachedModels) }
        // Fallback estático apenas para providers diretos sem cache ainda
        switch provider.providerType {
        case "openai":    return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        case "anthropic": return ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
        default:
            // Para gateways (litellm, custom, etc): sem cache ainda, mostra só o modelo atual
            return provider.defaultModel.isEmpty ? [] : [provider.defaultModel]
        }
    }

    /// Remove duplicatas preservando a ordem. Listas de gateways frequentemente
    /// trazem o mesmo modelo repetido, o que gera IDs repetidos no ForEach e
    /// corrompe a seleção (você clica num modelo e outro é selecionado).
    static func dedup(_ models: [String]) -> [String] {
        var seen = Set<String>()
        return models.filter { seen.insert($0).inserted }
    }

    /// Exibe o nome do modelo de forma legível no botão — remove prefixos de provider
    /// Ex: "anthropic/claude-opus-4-8" → "claude-opus-4-8"
    ///     "vertex_ai/gemini-2.5-flash" → "gemini-2.5-flash"
    private func shortModelName(_ model: String) -> String {
        if model.isEmpty { return "Modelo" }
        // Remove prefixo provider/ se presente
        if let slash = model.firstIndex(of: "/") {
            let name = String(model[model.index(after: slash)...])
            return name.isEmpty ? model : name
        }
        return model
    }

    private func pillActionBtn(
        icon: String,
        help: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint ?? Color(.secondaryLabelColor))
                .frame(width: 26, height: 26)
                .background(
                    tint != nil && tint != .red
                        ? Color.white.opacity(0.12)
                        : (tint == .red ? Color.red.opacity(0.12) : Color.clear),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Dictating Wave

struct DictatingWaveView: View {
    @State private var levels: [CGFloat] = Array(repeating: 0.3, count: 16)
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<16, id: \.self) { i in
                Capsule()
                    .fill(Color.red.opacity(0.7))
                    .frame(width: 2, height: levels[i] * 20 + 3)
                    .animation(.easeInOut(duration: 0.08), value: levels[i])
            }
        }
        .onReceive(timer) { _ in
            for i in 0..<16 { levels[i] = CGFloat.random(in: 0.1...1.0) }
        }
    }
}
