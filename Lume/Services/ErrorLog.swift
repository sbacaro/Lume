//
//  ErrorLog.swift
//  Lume
//
//  Log de erros em arquivo, acessível ao usuário (Application Support/Lume/errors.log).
//  Permite copiar e inspecionar erros que antes só apareciam num toast transitório.
//

import Foundation
import AppKit

enum ErrorLog {
    /// Arquivo de log persistente. Computado e `nonisolated` para poder ser usado tanto do
    /// `record` (nonisolated) quanto do `reveal` (MainActor) sob a isolação MainActor padrão.
    nonisolated static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lume", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("errors.log")
    }

    /// Acrescenta uma linha com timestamp ao log.
    nonisolated static func record(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// Mostra o arquivo de log no Finder (cria vazio se ainda não existir).
    @MainActor static func reveal() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? Data().write(to: fileURL)
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
