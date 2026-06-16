//
//  AboutView.swift
//  Lume
//
//  Tela "Sobre o Lume" — janela de identidade do app no padrão profissional do
//  macOS: ícone, nome, versão/build, descrição, atalhos para repositório,
//  notas de versão, licença e verificação de atualizações.
//

import SwiftUI
import AppKit

struct AboutView: View {
    @State private var updater = UpdateManager.shared

    // MARK: - Metadados do app

    private let repoURL      = URL(string: "https://github.com/sbacaro/Lume")!
    private let releasesURL  = URL(string: "https://github.com/sbacaro/Lume/releases")!
    private let issuesURL    = URL(string: "https://github.com/sbacaro/Lume/issues")!
    private let licenseURL   = URL(string: "https://github.com/sbacaro/Lume/blob/main/LICENSE")!

    private var version: String { updater.currentVersion }
    private var build: String   { updater.currentBuild }
    private var copyrightYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    descriptionBlock
                    updateBlock
                    linksBlock
                    techBlock
                }
                .padding(22)
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 440, height: 560)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Cabeçalho (ícone + nome + versão)

    private var header: some View {
        VStack(spacing: 12) {
            appIcon
                .frame(width: 88, height: 88)
                .shadow(color: LumeBrand.glow.opacity(0.25), radius: 14, y: 5)

            VStack(spacing: 3) {
                Text("Lume")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Cliente Nativo de IA para macOS")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text("Versão \(version) (build \(build))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .textSelection(.enabled)
                .help("Clique para selecionar e copiar")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    /// Usa o ícone real do app quando disponível; caso contrário, a marca vetorial.
    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
        } else {
            LumeMark(size: 88)
        }
    }

    // MARK: - Descrição

    private var descriptionBlock: some View {
        Text("Chat, projetos, código e agentes em um só lugar. O Lume conecta múltiplos provedores de IA com ferramentas, memória e automações — tudo nativo no macOS, com seus dados e chaves guardados localmente.")
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(2)
    }

    // MARK: - Atualizações

    private var updateBlock: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Atualizações")
                    .font(.system(size: 12, weight: .semibold))
                Text(updateStatusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await updater.checkForUpdatesForced() }
            } label: {
                HStack(spacing: 5) {
                    if updater.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("Verificar").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(updater.isChecking)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var updateStatusText: String {
        if updater.isChecking { return "Procurando novas versões…" }
        if let rel = updater.availableRelease {
            return "Nova versão disponível: \(rel.version)"
        }
        if let err = updater.error { return "Erro: \(err)" }
        if updater.lastChecked != nil { return "Você está na versão mais recente." }
        return "Verifique se há uma nova versão."
    }

    // MARK: - Links

    private var linksBlock: some View {
        VStack(spacing: 0) {
            linkRow("Repositório no GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: repoURL)
            Divider().opacity(0.35)
            linkRow("Notas de versão", systemImage: "doc.text", url: releasesURL)
            Divider().opacity(0.35)
            linkRow("Reportar um problema", systemImage: "ladybug", url: issuesURL)
            Divider().opacity(0.35)
            linkRow("Licença MIT", systemImage: "checkmark.seal", url: licenseURL)
        }
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func linkRow(_ title: String, systemImage: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Requisitos técnicos

    private var techBlock: some View {
        HStack(spacing: 16) {
            techItem("macOS", "14 ou superior")
            Divider().frame(height: 28).opacity(0.4)
            techItem("Swift", "5.9+")
            Divider().frame(height: 28).opacity(0.4)
            techItem("Interface", "SwiftUI")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func techItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rodapé

    private var footer: some View {
        VStack(spacing: 3) {
            Text("© \(copyrightYear) Samuel Bacaro · Distribuído sob licença MIT")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Feito com ♥ e SwiftUI")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

#Preview {
    AboutView()
}
