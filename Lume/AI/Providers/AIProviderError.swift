//
//  AIProviderError.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation

enum AIProviderError: LocalizedError {
    case invalidAPIKey
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case rateLimited
    case apiError(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "API Key inválida ou expirada"
        case .invalidResponse:
            return "Resposta inválida do provider"
        case .networkError(let error):
            return "Erro de rede: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Erro ao decodificar: \(error.localizedDescription)"
        case .rateLimited:
            return "Limite de requisições excedido"
        case .apiError(let message):
            return "Erro da API: \(message)"
        case .unknown(let message):
            return message
        }
    }
}
