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
                    .font(.lume(.title1, weight: .medium))
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
            Text(title).font(.lume(.title1, weight: .semibold))
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
                .font(.lume(.body))
                .foregroundStyle(accent)
                .frame(width: 20)
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

/// Capacidades do modo em grade de 2 colunas, centralizada — em vez de uma lista solta.
struct CapabilityGrid: View {
    let items: [(icon: String, text: String)]
    let accent: Color
    var body: some View {
        let mid = (items.count + 1) / 2
        HStack(alignment: .top, spacing: 28) {
            column(Array(items.prefix(mid)))
            column(Array(items.suffix(items.count - mid)))
        }
    }

    private func column(_ rows: [(icon: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 9) {
                    Image(systemName: item.icon)
                        .font(.lume(.body)).foregroundStyle(accent).frame(width: 20)
                    Text(item.text).font(.callout).foregroundStyle(.secondary)
                }
            }
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
                Image(systemName: icon).font(.lume(.callout, weight: .semibold))
                Text(label).font(.lume(.callout, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .glassEffect(.regular.tint(accent).interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Botão secundário em pill de vidro (Liquid Glass) — mesma linguagem do primário.
struct ModeSecondaryButton: View {
    let label: String
    let accent: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.lume(.callout, weight: .medium))
                .foregroundStyle(accent)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: Capsule())
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


// MARK: - Segmented em pill (substitui o .pickerStyle(.segmented) nativo, no idioma do app)

struct PillSegmented<T: Hashable>: View {
    let options: [(label: String, value: T)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let isSelected = selection == opt.value
                Button { selection = opt.value } label: {
                    Text(opt.label)
                        .font(.lume(.subheadline, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.20)) : AnyShapeStyle(Color.clear),
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}
