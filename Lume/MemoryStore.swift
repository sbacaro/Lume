//
//  MemoryStore.swift
//  Lume
//
//  Memória persistente entre conversas: fatos sobre o usuário, preferências e
//  contexto que devem valer em todas as conversas. Persistido em JSON no diretório
//  de suporte (mesmo padrão do LumeConfig) — sem dependência de SwiftData.
//

import Foundation
import Observation

// MARK: - Categoria

enum MemoryCategory: String, Codable, CaseIterable {
    case general    // Geral
    case personal   // Pessoal
    case work       // Trabalho
    case preference // Preferência

    var label: String {
        switch self {
        case .general:    return "Geral"
        case .personal:   return "Pessoal"
        case .work:       return "Trabalho"
        case .preference: return "Preferência"
        }
    }

    var icon: String {
        switch self {
        case .general:    return "circle.grid.2x2"
        case .personal:   return "person"
        case .work:       return "briefcase"
        case .preference: return "slider.horizontal.3"
        }
    }
}

// MARK: - Item

struct MemoryItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var content: String
    var category: String = MemoryCategory.general.rawValue
    var isEnabled: Bool = true
    var createdAt: Date = Date()

    var categoryEnum: MemoryCategory {
        MemoryCategory(rawValue: category) ?? .general
    }
}

// MARK: - Store

@Observable
final class MemoryStore {
    static let shared = MemoryStore()

    private(set) var items: [MemoryItem] = []

    init() { load() }

    // MARK: Mutations

    func add(_ content: String, category: MemoryCategory = .general) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Evita duplicatas exatas (case-insensitive).
        guard !items.contains(where: { $0.content.compare(trimmed, options: .caseInsensitive) == .orderedSame })
        else { return }
        items.insert(MemoryItem(content: trimmed, category: category.rawValue), at: 0)
        save()
    }

    func update(_ item: MemoryItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        save()
    }

    func toggle(_ item: MemoryItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isEnabled.toggle()
        save()
    }

    func delete(_ item: MemoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearAll() {
        items.removeAll()
        save()
    }

    // MARK: Context

    /// Bloco de contexto com as memórias ativas, para injetar no system prompt.
    func contextBlock() -> String? {
        let enabled = items.filter {
            $0.isEnabled && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !enabled.isEmpty else { return nil }
        var lines = ["## Memória do usuário",
                     "Fatos persistentes que você deve considerar em todas as respostas:"]
        for item in enabled {
            lines.append("- \(item.content)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Persistence

    private static let fileURL: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Lume")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("memory.json")
    }()

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    static var filePath: String { fileURL.path }
}
