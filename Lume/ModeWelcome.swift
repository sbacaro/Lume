//
//  ModeWelcome.swift
//  Lume
//
//  Componentes compartilhados das telas iniciais dos modos (Chat / Cowork / Code).
//  Mesma linguagem visual nativa; cada modo compõe o conteúdo e as ações próprias.
//

import SwiftUI

/// Tile arredondado com o glyph do modo, na cor de destaque.
struct ModeGlyph: View {
    let icon: String
    let accent: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(accent.opacity(0.13))
            .frame(width: 60, height: 60)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(accent)
            )
    }
}

/// Cabeçalho comum: glyph + título + subtítulo.
struct ModeWelcomeHeader: View {
    let icon: String
    let accent: Color
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            ModeGlyph(icon: icon, accent: accent)
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }
}

/// Linha de capacidade (ícone + texto), usada na lista "o que o modo faz".
struct CapabilityRow: View {
    let icon: String
    let text: String
    let accent: Color
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(accent)
                .frame(width: 20)
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

/// Botão primário preenchido — a ação principal de cada modo.
struct ModePrimaryButton: View {
    let icon: String
    let label: String
    let accent: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Botão secundário em pill (contorno tingido) — mesma linguagem do primário.
struct ModeSecondaryButton: View {
    let label: String
    let accent: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(accent.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Cores de destaque por modo.
enum ModeAccent {
    static let chat = Color(red: 0.40, green: 0.60, blue: 1.00)
    static let code = Color(red: 0.20, green: 0.60, blue: 1.00)
    // Cowork usa LumeTheme.clay.
}
