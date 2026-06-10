//
//  KeychainMigration.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import Security

/// Deleta TODOS os itens do keychain com service "com.lume.ai" que foram
/// criados sem o entitlement correto. Roda uma única vez após o app ser
/// atualizado com Keychain Sharing ativado.
enum KeychainMigration {
    private static let migrationKey = "lume_keychain_migration_v1"

    static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        // Busca todos os itens do service sem restrição de acessibilidade
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      "com.lume.ai",
            kSecMatchLimit as String:       kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            // Nunca mostra UI — se não conseguir acessar, só ignora
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let items = result as? [[String: Any]] {
            for item in items {
                guard let account = item[kSecAttrAccount as String] as? String else { continue }
                let deleteQuery: [String: Any] = [
                    kSecClass as String:       kSecClassGenericPassword,
                    kSecAttrService as String: "com.lume.ai",
                    kSecAttrAccount as String: account
                ]
                SecItemDelete(deleteQuery as CFDictionary)
            }
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}
