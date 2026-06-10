//
//  FullDiskAccessHelper.swift
//  Lume
//

import Foundation
import AppKit

enum FullDiskAccessHelper {

    /// Testa se o app tem Full Disk Access tentando ler um diretório protegido
    static var hasFullDiskAccess: Bool {
        let testPaths = [
            NSHomeDirectory() + "/Library/Mail",
            NSHomeDirectory() + "/Library/Safari",
            "/Library/Application Support/com.apple.TCC"
        ]
        for path in testPaths {
            if FileManager.default.isReadableFile(atPath: path) {
                return true
            }
        }
        // Fallback: tenta listar o Desktop
        let desktop = NSHomeDirectory() + "/Desktop"
        if let items = try? FileManager.default.contentsOfDirectory(atPath: desktop) {
            return !items.isEmpty || FileManager.default.isReadableFile(atPath: desktop)
        }
        return false
    }

    /// Mostra alerta pedindo ao usuário para conceder Full Disk Access
    @MainActor
    static func requestAccessIfNeeded() {
        guard !hasFullDiskAccess else { return }

        let alert = NSAlert()
        alert.messageText = "Lume precisa de Acesso Total ao Disco"
        alert.informativeText = """
        Para que o agente de código possa ler, editar e analisar os arquivos do seu projeto, o Lume precisa de permissão de Acesso Total ao Disco (Full Disk Access).

        Clique em "Abrir Configurações" e adicione o Lume na lista de apps com acesso total ao disco.

        Após conceder a permissão, reinicie o Lume.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Abrir Configurações")
        alert.addButton(withTitle: "Depois")

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    openFullDiskAccessSettings()
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                openFullDiskAccessSettings()
            }
        }
    }

    /// Abre diretamente as configurações de Full Disk Access
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
