//
//  SuggestionCardsView.swift
//  Lume
//

import SwiftUI

struct SuggestionCardsView: View {
    let block: ContextManager.SuggestionBlock
    let onSelect: (String) -> Void

    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            VStack(alignment: .leading, spacing: 0) {
                // Cabeçalho com a pergunta
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text(block.question)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { dismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 20, height: 20)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().opacity(0.3)

                // Opções clicáveis
                VStack(spacing: 0) {
                    ForEach(Array(block.options.enumerated()), id: \.offset) { idx, option in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { dismissed = true }
                            onSelect(option)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 22, height: 22)
                                    .background(Color.accentColor.opacity(0.10), in: Circle())

                                Text(option)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)

                                Spacer()

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SuggestionOptionButtonStyle())

                        if idx < block.options.count - 1 {
                            Divider()
                                .padding(.leading, 50)
                                .opacity(0.3)
                        }
                    }
                }
            }
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .scale(scale: 0.95).combined(with: .opacity)
            ))
        }
    }
}

// MARK: - Button Style

struct SuggestionOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.accentColor.opacity(0.06)
                    : Color.clear
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
