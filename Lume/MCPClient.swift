//
//  MCPClient.swift
//  Lume
//
//  Cliente do Model Context Protocol (MCP) sobre transporte stdio.
//  Fala JSON-RPC 2.0 com mensagens delimitadas por newline (framing do MCP stdio):
//  handshake `initialize` + `notifications/initialized`, `tools/list` e `tools/call`.
//
//  O núcleo de framing/decodificação fica em `MCPFraming` (puro, testável). O
//  `MCPClient` é um `actor` para confinar o processo, os pipes e o mapa de
//  continuations pendentes sob strict concurrency.
//

import Foundation

// MARK: - Erros

enum MCPError: Error, LocalizedError {
    case notRunning
    case server(String)
    case decoding
    case timeout

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Servidor MCP não está em execução."
        case .server(let m): return "Erro do servidor MCP: \(m)"
        case .decoding:   return "Resposta MCP inválida."
        case .timeout:    return "Tempo esgotado aguardando o servidor MCP."
        }
    }
}

// MARK: - Tipos de protocolo

/// Resposta JSON-RPC genérica. `result` usa `JSONValue` para aceitar qualquer payload.
/// `nonisolated` para que a conformância a `Decodable` seja usável fora do MainActor
/// (ex.: no `decode` chamado pelo actor `MCPClient`).
nonisolated struct MCPResponse: Decodable {
    let id: Int?
    let result: JSONValue?
    let error: MCPErrorObject?
}

nonisolated struct MCPErrorObject: Decodable {
    let code: Int
    let message: String
}

/// Descrição de uma ferramenta exposta por um servidor MCP.
struct MCPToolInfo: Sendable, Equatable {
    let name: String
    let description: String
    /// JSON Schema cru do input (objeto com `properties`/`required`).
    let inputSchema: JSONValue

    init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    /// Constrói a partir de um item de `tools/list`.
    nonisolated init?(json: JSONValue) {
        guard let name = json["name"]?.string else { return nil }
        self.name = name
        self.description = json["description"]?.string ?? ""
        self.inputSchema = json["inputSchema"] ?? .object([:])
    }
}

// MARK: - Framing (puro / testável)

enum MCPFraming {

    /// Serializa uma mensagem JSON-RPC e acrescenta o delimitador `\n`.
    nonisolated static func frame(_ message: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        data.append(0x0A) // "\n"
        return data
    }

    /// Extrai do buffer todas as linhas completas (terminadas em `\n`), deixando
    /// o restante parcial no buffer para a próxima leitura.
    nonisolated static func extractLines(from buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            if !line.isEmpty { lines.append(Data(line)) }
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        return lines
    }

    /// Decodifica uma linha JSON-RPC em `MCPResponse`.
    nonisolated static func decode(_ line: Data) -> MCPResponse? {
        try? JSONDecoder().decode(MCPResponse.self, from: line)
    }
}

// MARK: - Cliente stdio

actor MCPClient {

    let connectorID: String
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private(set) var tools: [MCPToolInfo] = []
    private(set) var isInitialized = false

    init(connectorID: String) {
        self.connectorID = connectorID
    }

    // MARK: Ciclo de vida

    /// Lança o servidor MCP (via `/usr/bin/env <comando>`) e começa a ler o stdout.
    func start(command: String) throws {
        let parts = command.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { throw MCPError.notRunning }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = parts

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.ingest(data) }
        }

        try process.run()
        self.process = process
        self.stdin = inPipe.fileHandleForWriting
    }

    func stop() {
        process?.terminate()
        process = nil
        stdin = nil
        for (_, cont) in pending { cont.resume(throwing: MCPError.notRunning) }
        pending.removeAll()
        isInitialized = false
    }

    // MARK: Handshake

    /// Executa o handshake do MCP: `initialize` + notificação `initialized`.
    @discardableResult
    func initialize() async throws -> JSONValue {
        let params: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "Lume", "version": "1.0"]
        ]
        let result = try await request(method: "initialize", params: params)
        try notify(method: "notifications/initialized", params: [:])
        isInitialized = true
        return result
    }

    // MARK: Ferramentas

    /// Lista as ferramentas do servidor (`tools/list`).
    @discardableResult
    func listTools() async throws -> [MCPToolInfo] {
        let result = try await request(method: "tools/list", params: [:])
        let infos = (result["tools"]?.array ?? []).compactMap { MCPToolInfo(json: $0) }
        tools = infos
        return infos
    }

    /// Invoca uma ferramenta (`tools/call`) e devolve o texto concatenado do conteúdo.
    /// Recebe `[String: String]` (Sendable) — os valores são serializados como JSON
    /// dentro do actor, evitando enviar `[String: Any]` através da fronteira de isolamento.
    func callTool(name: String, arguments: [String: String]) async throws -> String {
        let result = try await request(
            method: "tools/call",
            params: ["name": name, "arguments": arguments]
        )
        if let content = result["content"]?.array {
            let text = content.compactMap { $0["text"]?.string }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        return result.string ?? "[sem saída]"
    }

    // MARK: JSON-RPC

    private func request(method: String, params: [String: Any]) async throws -> JSONValue {
        guard stdin != nil else { throw MCPError.notRunning }
        nextID += 1
        let id = nextID
        let message: [String: Any] = [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params
        ]
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            do {
                try write(message)
            } catch {
                pending[id] = nil
                cont.resume(throwing: error)
            }
        }
    }

    private func notify(method: String, params: [String: Any]) throws {
        try write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func write(_ message: [String: Any]) throws {
        guard let stdin else { throw MCPError.notRunning }
        let data = try MCPFraming.frame(message)
        try stdin.write(contentsOf: data)
    }

    /// Acumula bytes do stdout, separa por linha e despacha respostas.
    private func ingest(_ data: Data) {
        buffer.append(data)
        for line in MCPFraming.extractLines(from: &buffer) {
            guard let resp = MCPFraming.decode(line) else { continue }
            guard let id = resp.id, let cont = pending.removeValue(forKey: id) else { continue }
            if let err = resp.error {
                cont.resume(throwing: MCPError.server(err.message))
            } else {
                cont.resume(returning: resp.result ?? .null)
            }
        }
    }
}

// MARK: - Transporte HTTP

/// Cliente HTTP do MCP (JSON-RPC sobre POST). Cada chamada é um POST independente
/// para o endpoint do servidor. Assume respostas `application/json` (não trata
/// streaming SSE — servidores que respondem apenas via `text/event-stream` não são
/// suportados por este caminho). `nonisolated` — não toca estado isolado.
enum MCPHTTP {

    private nonisolated static func rpc(baseURL: String, method: String, params: [String: Any]) async throws -> JSONValue {
        guard let url = URL(string: baseURL) else { throw MCPError.notRunning }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": method, "params": params
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let resp = MCPFraming.decode(data) else { throw MCPError.decoding }
        if let err = resp.error { throw MCPError.server(err.message) }
        return resp.result ?? .null
    }

    nonisolated static func initialize(baseURL: String) async throws {
        _ = try await rpc(baseURL: baseURL, method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "Lume", "version": "1.0"]
        ])
    }

    nonisolated static func listTools(baseURL: String) async throws -> [MCPToolInfo] {
        let result = try await rpc(baseURL: baseURL, method: "tools/list", params: [:])
        return (result["tools"]?.array ?? []).compactMap { MCPToolInfo(json: $0) }
    }

    nonisolated static func callTool(baseURL: String, name: String, arguments: [String: String]) async throws -> String {
        let result = try await rpc(baseURL: baseURL, method: "tools/call",
                                   params: ["name": name, "arguments": arguments])
        if let content = result["content"]?.array {
            let text = content.compactMap { $0["text"]?.string }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        return result.string ?? "[sem saída]"
    }
}

// MARK: - Ponte para o agente

/// Adapta uma ferramenta MCP descoberta para o protocolo `AgentTool`, de modo que
/// apareça junto das ferramentas nativas (`AgentToolExecutor.availableTools`) e seja
/// oferecida ao modelo por todos os providers.
struct MCPAgentTool: AgentTool {
    let connectorID: String
    let name: String
    let description: String
    let parameters: [ToolParameter]

    init(connectorID: String, info: MCPToolInfo) {
        self.connectorID = connectorID
        self.name = info.name
        self.description = info.description.isEmpty ? "MCP tool \(info.name)" : info.description
        self.parameters = Self.parameters(from: info.inputSchema)
    }

    func execute(with input: [String: String]) async throws -> ToolResult {
        await MCPManager.shared.executeMCPTool(connectorID: connectorID, name: name, input: input)
    }

    /// Converte um JSON Schema de input (`properties`/`required`) em `[ToolParameter]`.
    nonisolated static func parameters(from schema: JSONValue) -> [ToolParameter] {
        let props = schema["properties"]?.object ?? [:]
        let required = Set((schema["required"]?.array ?? []).compactMap { $0.string })
        return props.map { key, val in
            ToolParameter(
                name: key,
                description: val["description"]?.string ?? "",
                type: val["type"]?.string ?? "string",
                required: required.contains(key)
            )
        }
        .sorted { $0.name < $1.name }
    }
}
