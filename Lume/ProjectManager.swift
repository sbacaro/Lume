//
//  ProjectManager.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import AppKit

/// Manages the ~/Lume/ directory and project folders.
/// Each project owns exactly one sandbox folder — the agent operates only within it.
@MainActor
final class ProjectManager {
    static let shared = ProjectManager()

    // MARK: - Base directory: ~/Lume

    var lumeDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Lume")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        _ = lumeDirectory
    }

    // MARK: - Create from scratch

    func createProjectFolder(name: String) throws -> URL {
        let sanitized = sanitize(name)
        let url = lumeDirectory.appendingPathComponent(sanitized)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let instructions = """
        # \(name)

        Este é o diretório do projeto **\(name)** gerenciado pelo Lume.

        ## Instruções para o assistente

        - Trabalhe apenas dentro desta pasta
        - Mantenha os arquivos organizados
        - Documente mudanças importantes
        """
        let instructionsURL = url.appendingPathComponent("LUME.md")
        if !FileManager.default.fileExists(atPath: instructionsURL.path) {
            try instructions.write(to: instructionsURL, atomically: true, encoding: .utf8)
        }

        return url
    }

    // MARK: - Import existing folder

    func importExistingFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Selecione a pasta do projeto"
        panel.prompt = "Usar esta pasta"
        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
        return response == .OK ? panel.url : nil
    }

    // MARK: - Import from conversation

    func importFromConversation(name: String, messages: [Message]) throws -> URL {
        let url = try createProjectFolder(name: name)
        let markdown = messages.map { "**\($0.role.rawValue.capitalized):**\n\n\($0.content)" }
            .joined(separator: "\n\n---\n\n")
        let exportURL = url.appendingPathComponent("conversa-importada.md")
        try markdown.write(to: exportURL, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - List files in project

    func listFiles(in project: Project) -> [URL] {
        guard let url = project.localURL else { return [] }
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return items.filter { item in
            let values = try? item.resourceValues(forKeys: Set(resourceKeys))
            return values?.isRegularFile == true
        }
    }

    // MARK: - Sandbox check

    func isPathAllowed(_ path: String, for project: Project) -> Bool {
        guard let url = project.localURL else { return false }
        let resolved = URL(fileURLWithPath: path).standardized
        return resolved.path.hasPrefix(url.standardized.path)
    }

    // MARK: - Open in Finder

    func revealInFinder(_ project: Project) {
        guard let url = project.localURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_ "))
        return name
            .components(separatedBy: allowed.inverted).joined()
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
            .trimmingCharacters(in: .init(charactersIn: "-_"))
    }
}
