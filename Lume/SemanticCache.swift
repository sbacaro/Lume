//
//  SemanticCache.swift
//  Lume
//

import Foundation

actor SemanticCache {
    // Swift 6: static let shared em actor é ok — criado uma vez antes de qualquer isolamento
    static let shared = SemanticCache()

    private struct Entry {
        let response: String
        let timestamp: Date
        let hitCount: Int
    }

    private var cache: [String: Entry] = [:]
    private var loaded = false
    private let maxEntries = 500
    private let ttl: TimeInterval = 3600 * 24
    private let diskURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("lume_semantic_cache.json")
    }()

    // Swift 6: init privado sem nonisolated — o actor garante isolamento correto
    private init() {}

    // MARK: - Get

    func get(prompt: String, model: String) -> String? {
        if !loaded { loadFromDisk(); loaded = true }
        let key = cacheKey(prompt: prompt, model: model)
        guard let entry = cache[key] else { return nil }
        guard Date().timeIntervalSince(entry.timestamp) < ttl else {
            cache.removeValue(forKey: key); return nil
        }
        cache[key] = Entry(response: entry.response, timestamp: entry.timestamp,
                           hitCount: entry.hitCount + 1)
        return entry.response
    }

    // MARK: - Set

    func set(prompt: String, model: String, response: String) {
        if !loaded { loadFromDisk(); loaded = true }
        let key = cacheKey(prompt: prompt, model: model)
        cache[key] = Entry(response: response, timestamp: Date(), hitCount: 0)
        evictIfNeeded()
        saveToDisk()
    }

    // MARK: - Clear

    func clear() {
        cache.removeAll()
        loaded = false
        try? FileManager.default.removeItem(at: diskURL)
    }

    var totalEntries: Int { cache.count }
    var totalHits: Int { cache.values.map { $0.hitCount }.reduce(0, +) }

    // MARK: - Private

    private func cacheKey(prompt: String, model: String) -> String {
        let normalized = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "\(model):\(normalized.prefix(256))"
    }

    private func evictIfNeeded() {
        guard cache.count > maxEntries else { return }
        let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
        sorted.prefix(cache.count - maxEntries + 50).forEach { cache.removeValue(forKey: $0.key) }
    }

    private struct DiskEntry: Codable {
        let key: String; let response: String
        let timestamp: Date; let hitCount: Int
    }

    private func saveToDisk() {
        let entries = cache.map {
            DiskEntry(key: $0.key, response: $0.value.response,
                      timestamp: $0.value.timestamp, hitCount: $0.value.hitCount)
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: diskURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: diskURL),
              let entries = try? JSONDecoder().decode([DiskEntry].self, from: data)
        else { return }
        let now = Date()
        for entry in entries where now.timeIntervalSince(entry.timestamp) < ttl {
            cache[entry.key] = Entry(response: entry.response,
                                     timestamp: entry.timestamp, hitCount: entry.hitCount)
        }
    }
}
