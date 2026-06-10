//
//  KeychainManager.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//
//  Sem Developer ID, o Keychain do sistema não funciona com assinatura ad-hoc.
//  Esta implementação salva as chaves em arquivo criptografado com AES-GCM
//  na pasta Application Support do app — sem nenhum entitlement especial.
//

import Foundation
import CryptoKit

actor KeychainManager {
    static let shared = KeychainManager()

    enum KeychainError: LocalizedError {
        case itemNotFound
        case encryptionFailed
        case decryptionFailed
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .itemNotFound:            return "Item not found"
            case .encryptionFailed:        return "Failed to encrypt key"
            case .decryptionFailed:        return "Failed to decrypt key"
            case .unexpectedStatus(let s): return "Error: \(s)"
            }
        }
    }

    // MARK: - Paths

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Lume", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".keys.enc")
    }

    private var masterKeyURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Lume", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".master.key")
    }

    // MARK: - Master Key

    /// Cria ou carrega a chave mestra AES-256 persistida em disco
    private func masterKey() -> SymmetricKey {
        if let data = try? Data(contentsOf: masterKeyURL),
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        // Gera nova chave e salva
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try? keyData.write(to: masterKeyURL, options: [.atomic, .completeFileProtection])
        return key
    }

    // MARK: - Storage (JSON dict em arquivo criptografado)

    private func loadStore() -> [String: String] {
        guard let encrypted = try? Data(contentsOf: storageURL) else { return [:] }
        do {
            let key = masterKey()
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let decrypted = try AES.GCM.open(box, using: key)
            let dict = try JSONDecoder().decode([String: String].self, from: decrypted)
            return dict
        } catch {
            return [:]
        }
    }

    private func saveStore(_ dict: [String: String]) throws {
        let key = masterKey()
        let data = try JSONEncoder().encode(dict)
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else { throw KeychainError.encryptionFailed }
        try combined.write(to: storageURL, options: [.atomic, .completeFileProtection])
    }

    // MARK: - Public API (mesma interface de antes)

    func saveAPIKey(_ key: String, for providerID: String) throws {
        var store = loadStore()
        store[providerID] = key
        try saveStore(store)
    }

    func retrieveAPIKey(for providerID: String) -> String {
        return loadStore()[providerID] ?? ""
    }

    func deleteAPIKey(for providerID: String) throws {
        var store = loadStore()
        store.removeValue(forKey: providerID)
        try saveStore(store)
    }
}
