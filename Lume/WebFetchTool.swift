//
//  WebFetchTool.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation

/// Busca e extrai o conteúdo textual de uma URL específica.
/// Usado para ler documentações, artigos e fontes completas.
struct WebFetchTool: AgentTool {
    let name = "web_fetch"
    let description = "Abre e lê o conteúdo de uma página web. Use para ler documentações, artigos, fontes específicas e qualquer URL."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "url", description: "URL completa da página a ser lida", type: "string", required: true),
        ToolParameter(name: "max_chars", description: "Máximo de caracteres a retornar (padrão: 8000)", type: "string", required: false)
    ]

    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let urlString = input["url"], !urlString.isEmpty else {
            return ToolResult(success: false, output: "Parâmetro 'url' é obrigatório.", metadata: [:])
        }

        // Garante que tem esquema
        let normalized = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        guard let url = URL(string: normalized) else {
            return ToolResult(success: false, output: "URL inválida: \(urlString)", metadata: [:])
        }

        let maxChars = Int(input["max_chars"] ?? "8000") ?? 8000
        return await fetchPage(url: url, maxChars: maxChars)
    }

    // MARK: - Fetch

    private func fetchPage(url: URL, maxChars: Int) async -> ToolResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return ToolResult(success: false, output: "Não foi possível acessar: \(url.absoluteString)", metadata: [:])
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode < 400 else {
            return ToolResult(success: false, output: "Erro HTTP \(statusCode) ao acessar: \(url.absoluteString)", metadata: [:])
        }

        // Detecta encoding
        let encoding = detectEncoding(from: response as? HTTPURLResponse, data: data)
        guard let html = String(data: data, encoding: encoding) ?? String(data: data, encoding: .utf8) else {
            return ToolResult(success: false, output: String(localized: "Could not decode the content."), metadata: [:])
        }

        let text = extractText(from: html, url: url)
        let truncated = text.count > maxChars ? String(text.prefix(maxChars)) + "\n\n[conteúdo truncado — \(text.count) chars total]" : text

        return ToolResult(
            success: true,
            output: truncated,
            metadata: [
                "url": url.absoluteString,
                "title": extractTitle(from: html),
                "chars": "\(text.count)",
                "status": "\(statusCode)"
            ]
        )
    }

    // MARK: - HTML → Texto

    private func extractText(from html: String, url: URL) -> String {
        var text = html

        // Remove scripts, styles, nav, footer, ads
        let removePatterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<nav[^>]*>[\\s\\S]*?</nav>",
            "<footer[^>]*>[\\s\\S]*?</footer>",
            "<header[^>]*>[\\s\\S]*?</header>",
            "<aside[^>]*>[\\s\\S]*?</aside>",
            "<!--[\\s\\S]*?-->",
            "<noscript[^>]*>[\\s\\S]*?</noscript>",
        ]
        for pattern in removePatterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // Converte tags estruturais em quebras de linha
        let blockTags = ["</p>", "</div>", "</li>", "</h1>", "</h2>", "</h3>",
                         "</h4>", "<br>", "<br/>", "<br />", "</tr>"]
        for tag in blockTags {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        // Remove todas as tags restantes
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decodifica entidades HTML
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")

        // Normaliza espaços e linhas
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Remove linhas duplicadas consecutivas
        var deduped: [String] = []
        var prev = ""
        for line in lines {
            if line != prev { deduped.append(line) }
            prev = line
        }

        return deduped.joined(separator: "\n")
    }

    private func extractTitle(from html: String) -> String {
        guard let match = html.firstMatch(of: /<title[^>]*>([\s\S]*?)<\/title>/) else { return "" }
        return String(match.1)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func detectEncoding(from response: HTTPURLResponse?, data: Data) -> String.Encoding {
        if let charset = response?.textEncodingName {
            let lower = charset.lowercased()
            if lower.contains("utf-8") { return .utf8 }
            if lower.contains("iso-8859-1") || lower.contains("latin") { return .isoLatin1 }
            if lower.contains("windows-1252") { return .windowsCP1252 }
        }
        // Tenta detectar pelo BOM
        if data.prefix(3) == Data([0xEF, 0xBB, 0xBF]) { return .utf8 }
        return .utf8
    }
}
