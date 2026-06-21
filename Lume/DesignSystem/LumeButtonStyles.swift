//
//  LumeButtonStyles.swift
//  Lume
//
//  Sistema único de botões de ação do app. Todas as telas (Configurações,
//  sheets, diálogos) devem usar estes estilos para garantir forma, tamanho e
//  comportamento consistentes — no padrão de um app nativo do macOS.
//
//  Uso:
//      Button("Reveal") { … }.buttonStyle(.lumeSecondary)
//      Button { … } label: { Label("Open", systemImage: "sparkles") }
//          .buttonStyle(.lumePrimary)
//      Button("Reset", role: .destructive) { … }.buttonStyle(.lumeDestructive)
//

import SwiftUI

// MARK: - Estilo base

struct LumeButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, destructive }

    var role: Role = .secondary
    /// Tamanho compacto para barras de ferramentas/linhas densas.
    var compact: Bool = false

    @Environment(\.isEnabled) private var isEnabled

    // Métricas únicas — a mesma forma (cápsula) e altura em todo o app.
    private var hPadding: CGFloat { compact ? 11 : 14 }
    private var vPadding: CGFloat { compact ? 5 : 7 }
    private var fontSize: CGFloat { compact ? 11 : 12 }
    private var minHeight: CGFloat { compact ? 24 : 28 }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.lume(size: fontSize, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .frame(minHeight: minHeight)
            .background(
                background(pressed: configuration.isPressed),
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    // MARK: Cores por papel

    private var foreground: Color {
        switch role {
        case .primary:     return .white
        case .destructive: return .red     // padrão macOS: texto vermelho, não pill vermelho cheio
        case .secondary:   return .primary
        }
    }

    private func background(pressed: Bool) -> Color {
        switch role {
        case .primary:     return Color.accentColor.opacity(pressed ? 0.82 : 1)
        case .destructive: return Color.red.opacity(pressed ? 0.20 : 0.10)
        case .secondary:   return Color.primary.opacity(pressed ? 0.12 : 0.07)
        }
    }

    private var borderColor: Color {
        switch role {
        case .primary:     return .clear
        case .destructive: return Color.red.opacity(0.30)
        case .secondary:   return Color.primary.opacity(0.12)
        }
    }
}

// MARK: - Atalhos de uso

extension ButtonStyle where Self == LumeButtonStyle {
    /// Ação principal (preenchido com a cor de acento).
    static var lumePrimary: LumeButtonStyle { LumeButtonStyle(role: .primary) }
    /// Ação secundária/neutra (fundo sutil com borda).
    static var lumeSecondary: LumeButtonStyle { LumeButtonStyle(role: .secondary) }
    /// Ação destrutiva (preenchido em vermelho).
    static var lumeDestructive: LumeButtonStyle { LumeButtonStyle(role: .destructive) }

    /// Versões compactas para linhas densas.
    static var lumePrimaryCompact: LumeButtonStyle { LumeButtonStyle(role: .primary, compact: true) }
    static var lumeSecondaryCompact: LumeButtonStyle { LumeButtonStyle(role: .secondary, compact: true) }
    static var lumeDestructiveCompact: LumeButtonStyle { LumeButtonStyle(role: .destructive, compact: true) }
}
