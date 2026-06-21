//
//  AIProviderConfig.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import SwiftData

@Model
final class AIProviderConfig {
    var id: String = UUID().uuidString
    var providerType: String // "openai", "anthropic", "openai_custom"
    var name: String
    var apiKey: String = "" // placeholder — real key in Keychain
    var baseURL: String
    var defaultModel: String
    var isActive: Bool = true
    var temperature: Double = 0.7
    var maxTokens: Int = 8192
    var createdAt: Date = Date()

    /// Models fetched from the provider API and cached locally.
    /// Updated when the user taps the refresh button in Settings.
    var cachedModels: [String] = []

    init(
        providerType: String,
        name: String,
        baseURL: String,
        defaultModel: String
    ) {
        self.providerType = providerType
        self.name = name
        self.baseURL = baseURL
        self.defaultModel = defaultModel
    }
}
