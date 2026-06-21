//
//  UpdateNotificationCard.swift
//  Lume
//

import SwiftUI

// MARK: - Update Notification Card

struct UpdateNotificationCard: View {
    let release: AppRelease
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    @State private var isExpanded = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                // Ícone animado
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.accentColor, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 32, height: 32)
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.lume(.title3, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Update available")
                        .font(.lume(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Lume \(release.version)")
                        .font(.lume(.footnote))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Fechar
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.lume(.caption, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Release notes (expansível)
            if !release.releaseNotes.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Hide what’s new" : "See what’s new")
                            .font(.lume(.caption))
                            .foregroundStyle(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.lume(.caption2, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ScrollView {
                        Text(release.releaseNotes)
                            .font(.lume(.caption))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                    .frame(maxHeight: 100)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Divider().opacity(0.3)

            // Botões de ação
            HStack(spacing: 6) {
                Button(action: onDismiss) {
                    Text("Later")
                        .font(.lume(.footnote))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)

                Button(action: onUpdate) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.lume(.caption, weight: .semibold))
                        Text("Download")
                            .font(.lume(.footnote, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .glassEffect(.regular,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        .frame(width: 240)
        .offset(y: appeared ? 0 : 20)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Sidebar Update Badge

/// Popup compacto de "atualização disponível" para a sidebar — no estilo do Lume
/// (vidro + gradiente da marca + borda de acento). Fica logo acima do nome do modelo.
struct SidebarUpdateBadge: View {
    let version: String
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(LumeBrand.gradient)
                    .frame(width: 26, height: 26)
                    .shadow(color: LumeBrand.glow.opacity(0.40), radius: 4, y: 1)
                Image(systemName: "sparkles")
                    .font(.lume(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Update available")
                    .font(.lume(.footnote, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Lume \(version)")
                    .font(.lume(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.lume(.caption2, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.accentColor.opacity(0.12), Color.accentColor.opacity(0.02), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(hovering ? 0.5 : 0.22), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { onUpdate() }
        .onHover { hovering = $0 }
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { appeared = true }
        }
        .help("Update Lume to \(version)")
    }
}
