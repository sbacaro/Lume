//
//  AIGateway.swift
//  Lume
//
//  Gateway de IA compatível com LiteLLM, Portkey, Langfuse, vLLM, TGI.
//  Qualquer provider que expõe API compatível com OpenAI pode ser usado.
//

import Foundation

// MARK: - Gateway Config

struct GatewayConfig {
    let type: GatewayType
    let baseURL: URL
    var apiKey: String
    var extraHeaders: [String: String]
    var projectID: String?
    var traceEnabled: Bool

    enum GatewayType: String, CaseIterable {
        case litellm    = "LiteLLM"
        case portkey    = "Portkey"
        case langfuse   = "Langfuse"
        case vllm       = "vLLM"
        case tgi        = "HuggingFace TGI"
        case ollama     = "Ollama"
        case custom     = "Custom OpenAI-compatible"

        var defaultPort: Int {
            switch self {
            case .litellm:  return 4000
            case .vllm:     return 8000
            case .tgi:      return 8080
            case .ollama:   return 11434
            default:        return 443
            }
        }

        var completionPath: String {
            switch self {
            case .ollama: return "/api/chat"
            default:      return "/v1/chat/completions"
            }
        }

        var requiresAPIKey: Bool {
            switch self {
            case .vllm, .tgi, .ollama: return false
            default: return true
            }
        }

        var icon: String {
            switch self {
            case .litellm:  return "server.rack"
            case .portkey:  return "arrow.triangle.2.circlepath"
            case .langfuse: return "chart.bar.xaxis"
            case .vllm:     return "cpu"
            case .tgi:      return "brain"
            case .ollama:   return "desktopcomputer"
            case .custom:   return "puzzlepiece.extension"
            }
        }
    }

    // Headers específicos por gateway
    var resolvedHeaders: [String: String] {
        var headers = extraHeaders
        switch type {
        case .portkey:
            headers["x-portkey-api-key"] = apiKey
            if let project = projectID {
                headers["x-portkey-config"] = project
            }
        case .langfuse:
            headers["x-langfuse-public-key"] = apiKey
            if traceEnabled {
                headers["x-langfuse-trace-id"] = UUID().uuidString
            }
        case .litellm:
            headers["Authorization"] = "Bearer \(apiKey)"
            if let project = projectID {
                headers["x-litellm-project"] = project
            }
        case .vllm, .tgi:
            if !apiKey.isEmpty {
                headers["Authorization"] = "Bearer \(apiKey)"
            }
        case .ollama:
            break // Ollama não usa auth por padrão
        case .custom:
            if !apiKey.isEmpty {
                headers["Authorization"] = "Bearer \(apiKey)"
            }
        }
        return headers
    }
}

// MARK: - Gateway Manager

final class AIGatewayManager {
    static let shared = AIGatewayManager()
    private init() {}

    private var activeGateway: GatewayConfig?

    func configure(gateway: GatewayConfig) {
        activeGateway = gateway
    }

    func clearGateway() {
        activeGateway = nil
    }

    var isGatewayActive: Bool { activeGateway != nil }
    var currentGateway: GatewayConfig? { activeGateway }

    /// Testa a conexão com o gateway
    func testConnection() async -> Result<String, Error> {
        guard let gateway = activeGateway else {
            return .failure(NSError(domain: "Gateway", code: 0,
                                   userInfo: [NSLocalizedDescriptionKey: "Nenhum gateway configurado"]))
        }

        let modelsURL = gateway.baseURL.appendingPathComponent("/v1/models")
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 10
        for (key, value) in gateway.resolvedHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode < 400 {
                if let json = try? JSONDecoder().decode(ModelsResponse.self, from: data) {
                    let names = json.data.prefix(5).map { $0.id }.joined(separator: ", ")
                    return .success("Conectado. Modelos: \(names)")
                }
                return .success("Conectado (\(statusCode))")
            } else {
                return .failure(NSError(domain: "Gateway", code: statusCode,
                                       userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"]))
            }
        } catch {
            return .failure(error)
        }
    }

    /// Lista modelos disponíveis no gateway
    func listModels() async -> [String] {
        guard let gateway = activeGateway else { return [] }
        let url = gateway.baseURL.appendingPathComponent("/v1/models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        for (key, value) in gateway.resolvedHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(ModelsResponse.self, from: data)
        else { return [] }
        return response.data.map { $0.id }
    }

    private struct ModelsResponse: Decodable {
        let data: [ModelEntry]
        struct ModelEntry: Decodable { let id: String }
    }
}
