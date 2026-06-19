//
//  SparkleUpdater.swift
//  Lume
//
//  Atualização automática via Sparkle: baixa o .dmg do release, instala e
//  reinicia o app sozinho. Na próxima abertura o usuário já está na versão nova.
//
//  O código fica envolto em `#if canImport(Sparkle)` para que o projeto compile
//  ANTES de o pacote ser adicionado (nesse estado, "Verificar" só abre a página
//  de releases). Depois de adicionar o pacote SPM Sparkle e configurar as chaves
//  e o appcast (veja SETUP_SPARKLE.md), o updater real entra em ação.
//

#if canImport(Sparkle)

import SwiftUI
import Combine
import Sparkle

/// URL do appcast (fonte de verdade do feed de atualização).
private let lumeAppcastURL = "https://raw.githubusercontent.com/sbacaro/Lume/main/appcast.xml"

/// Wrapper observável sobre o updater padrão do Sparkle.
///
/// Fornece a URL do appcast pelo delegate (`feedURLString(for:)`) — assim o feed é
/// garantido mesmo que o `SUFeedURL` não chegue ao Info.plist gerado.
@MainActor
final class SparkleUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    /// Inicia e mantém o ciclo de vida do updater (checagens automáticas em background).
    private var controller: SPUStandardUpdaterController!

    /// Reflete se uma checagem pode ser iniciada agora (para habilitar o item de menu).
    @Published var canCheckForUpdates = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Sparkle pergunta a URL do feed aqui — independente do Info.plist.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        lumeAppcastURL
    }

    /// Checagem manual — mostra a UI padrão do Sparkle (download, install, relaunch).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

#else

import SwiftUI
import Combine
import AppKit

/// Stub usado enquanto o pacote Sparkle NÃO está adicionado ao target.
/// Mantém o app compilando e oferece um fallback (abre a página de releases).
@MainActor
final class SparkleUpdater: ObservableObject {
    @Published var canCheckForUpdates = true

    func checkForUpdates() {
        if let url = URL(string: "https://github.com/sbacaro/Lume/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}

#endif
