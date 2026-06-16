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

/// Wrapper observável sobre o updater padrão do Sparkle.
@MainActor
final class SparkleUpdater: ObservableObject {
    /// Inicia e mantém o ciclo de vida do updater (checagens automáticas em background).
    private let controller: SPUStandardUpdaterController

    /// Reflete se uma checagem pode ser iniciada agora (para habilitar o item de menu).
    @Published var canCheckForUpdates = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
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
