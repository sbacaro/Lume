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
    let isDictating: Bool
    let modelName: String
    let availableModels: [String]
    let onModelChange: (String) -> Void

    @Binding var attachedImages: [NSImage]

    @Query(filter: #Predicate<AIProviderConfig> { $0.isActive })
    private var activeProviders: [AIProviderConfig]

    @FocusState private var isFocused: Bool
    @State private var animateGradient = false
    @State private var gradientAngle: Double = 0
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.2)

            if !attachedImages.isEmpty {
                imagePreviewBar
            }

            HStack(alignment: .bottom, spacing: 10) {
                pillContent
                    .background { pillBackground }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
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

                if isLoading {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.controlBackgroundColor), in: Circle())
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Cancelar (⌘.)")
                    .keyboardShortcut(".", modifiers: .command)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(canSend ? .white : Color(.tertiaryLabelColor))
                            .frame(width: 36, height: 36)
                            .background(
                                canSend ? Color.accentColor : Color(.controlBackgroundColor),
                                in: Circle()
                            )
                            .overlay(Circle().strokeBorder(Color.primary.opacity(canSend ? 0 : 0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("Enviar (↩)")
                    .animation(.easeInOut(duration: 0.2), value: canSend)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .onAppear {
            isFocused = true
            startGradientAnimation()
        }
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
                    .foregroundStyle(isLoading ? Color.white : Color.primary)
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
                            isLoading ? Color.white.opacity(0.7) : Color(.placeholderTextColor)
                        )
                        .padding(.top, 5)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                if isDictating {
                    DictatingWaveView()
                        .padding(.top, 5)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Bottom toolbar
            HStack(spacing: 6) {
                Menu {
                    if !activeProviders.isEmpty {
                        ForEach(activeProviders) { provider in
                            let models = modelsFor(provider)
                            if !models.isEmpty {
                                Menu(provider.name) {
                                    ForEach(models, id: \.self) { model in
                                        Button { onModelChange(model) } label: {
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
                        ForEach(availableModels, id: \.self) { model in
                            Button { onModelChange(model) } label: {
                                if model == modelName {
                                    Label(model, systemImage: "checkmark")
                                } else { Text(model) }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Modelos")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(isLoading ? Color.white.opacity(0.8) : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isLoading ? Color.white.opacity(0.15) : Color.primary.opacity(0.05))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

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

                pillActionBtn(
                    icon: "paperclip",
                    help: "Anexar arquivo",
                    tint: isLoading ? Color.white.opacity(0.7) : nil,
                    action: onAttach
                )

                pillActionBtn(
                    icon: isDictating ? "waveform" : "mic",
                    help: isDictating ? "Parar gravação" : "Ditado",
                    tint: isDictating ? .red : (isLoading ? Color.white.opacity(0.7) : nil),
                    action: onVoice
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Liquid Glass background

    private var pillBackground: some View {
        ZStack {
            Color(.windowBackgroundColor).opacity(0.01)

            if isLoading {
                AngularGradient(
                    colors: [
                        Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.85),
                        Color(red: 1.0, green: 0.3, blue: 0.5).opacity(0.85),
                        Color(red: 0.7, green: 0.3, blue: 1.0).opacity(0.85),
                        Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.85),
                        Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.85),
                    ],
                    center: .center,
                    angle: .degrees(gradientAngle)
                )
                .blur(radius: 12)
                .scaleEffect(1.4)
                .transition(.opacity)

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.45)
            } else {
                Rectangle().fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(isFocused ? 0.06 : 0.02),
                        Color.purple.opacity(isFocused ? 0.04 : 0.01),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isLoading)
    }

    // MARK: - Gradient animation

    private func startGradientAnimation() {
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
            gradientAngle = 360
        }
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
        if !provider.cachedModels.isEmpty { return provider.cachedModels }
        switch provider.providerType {
        case "openai":    return ["gpt-4o", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo"]
        case "anthropic": return ["claude-opus-4-5", "claude-sonnet-4-5", "claude-3-5-haiku-20241022"]
        default:          return provider.defaultModel.isEmpty ? [] : [provider.defaultModel]
        }
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
