//
//  WebSearchTool.swift
//  Lume
//

import Foundation

// MARK: - Web Search Tool

struct WebSearchTool: AgentTool {
    let name = "web_search"
    let description = "Busca informações na internet."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "query", description: "Termos de busca", type: "string", required: true),
        ToolParameter(name: "max_results", description: "Número máximo de resultados (padrão: 5)", type: "string", required: false)
    ]

    func execute(with input: [String: String]) async throws -> ToolResult {
        guard let query = input["query"], !query.isEmpty else {
            return ToolResult(success: false, output: "Parâmetro 'query' é obrigatório.", metadata: [:])
        }
        let maxResults = Int(input["max_results"] ?? "5") ?? 5

        // Tenta Google primeiro se a chave estiver configurada
        if let googleResult = await searchGoogle(query: query, maxResults: maxResults) {
            return googleResult
        }

        // Fallback: DuckDuckGo
        if let instantResult = await duckDuckGoInstant(query: query) {
            return instantResult
        }
        return await duckDuckGoHTML(query: query, maxResults: maxResults)
    }

    // MARK: - Google Custom Search API

    private func searchGoogle(query: String, maxResults: Int) async -> ToolResult? {
        // Lê as chaves do UserDefaults (configuradas nas Settings)
        let apiKey = UserDefaults.standard.string(forKey: "google_search_api_key") ?? ""
        let cx     = UserDefaults.standard.string(forKey: "google_search_cx") ?? ""

        guard !apiKey.isEmpty, !cx.isEmpty else { return nil }

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/customsearch/v1?key=\(apiKey)&cx=\(cx)&q=\(encoded)&num=\(min(maxResults, 10))")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200
        else { return nil }

        guard let json = try? JSONDecoder().decode(GoogleSearchResponse.self, from: data),
              !json.items.isEmpty
        else { return nil }

        let results = json.items.prefix(maxResults).map { item in
            "**\(item.title)**\n\(item.snippet ?? "")\nURL: \(item.link)"
        }.joined(separator: "\n\n")

        let urls = json.items.prefix(maxResults).map { $0.link }.joined(separator: ",")

        return ToolResult(
            success: true,
            output: "Resultados do Google para \"\(query)\":\n\n\(results)",
            metadata: ["source": "Google", "query": query,
                       "count": "\(json.items.count)",
                       "urls": urls]
        )
    }

    // MARK: - DuckDuckGo Instant Answer

    private func duckDuckGoInstant(query: String) async -> ToolResult? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Lume/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONDecoder().decode(DDGResponse.self, from: data)
        else { return nil }

        var parts: [String] = []
        if !json.AbstractText.isEmpty {
            parts.append("**\(json.Heading)**\n\(json.AbstractText)")
            if !json.AbstractURL.isEmpty { parts.append("Fonte: \(json.AbstractURL)") }
        }
        for topic in json.RelatedTopics.prefix(5) where !topic.Text.isEmpty {
            parts.append("• \(topic.Text)")
        }

        if parts.isEmpty { return nil }
        return ToolResult(success: true, output: parts.joined(separator: "\n\n"),
                          metadata: ["source": "DuckDuckGo Instant", "query": query])
    }

    // MARK: - DuckDuckGo HTML

    func duckDuckGoHTML(query: String, maxResults: Int) async -> ToolResult {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)")
        else {
            return ToolResult(success: false, output: "Não foi possível construir URL.", metadata: [:])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8)
        else {
            return ToolResult(success: false, output: "Erro ao conectar.", metadata: [:])
        }

        let results = parseHTMLResults(html: html, maxResults: maxResults)
        if results.isEmpty {
            return ToolResult(success: false, output: "Nenhum resultado para: \(query)", metadata: [:])
        }

        let output = results.enumerated().map { i, r in
            "**\(i + 1). \(r.title)**\n\(r.snippet)\nURL: \(r.url)"
        }.joined(separator: "\n\n")

        return ToolResult(
            success: true,
            output: "Resultados para \"\(query)\":\n\n\(output)",
            metadata: ["source": "DuckDuckGo", "query": query,
                       "count": "\(results.count)",
                       "urls": results.map { $0.url }.joined(separator: ",")]
        )
    }

    // MARK: - HTML Parser

    struct SearchResult { let title: String; let snippet: String; let url: String }

    func parseHTMLResults(html: String, maxResults: Int) -> [SearchResult] {
        var results: [SearchResult] = []
        let titlePattern  = /<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/
        let snippetPattern = /<a[^>]*class="result__snippet"[^>]*>([\s\S]*?)<\/a>/
        let blockPattern  = /<div[^>]*class="[^"]*result[^"]*"[^>]*>([\s\S]*?)<\/div>\s*<\/div>/

        let blocks = html.matches(of: blockPattern).prefix(maxResults * 2)
        for block in blocks {
            guard results.count < maxResults else { break }
            let text    = String(block.1)
            let title   = text.firstMatch(of: titlePattern).map { stripHTML(String($0.2)) } ?? ""
            let url     = text.firstMatch(of: titlePattern).map { String($0.1) } ?? ""
            let snippet = text.firstMatch(of: snippetPattern).map { stripHTML(String($0.1)) } ?? ""
            if !title.isEmpty { results.append(SearchResult(title: title, snippet: snippet, url: url)) }
        }
        return results
    }

    func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Google Search Response

private struct GoogleSearchResponse: Decodable {
    let items: [GoogleSearchItem]

    struct GoogleSearchItem: Decodable {
        let title: String
        let link: String
        let snippet: String?
    }
}

// MARK: - DDG JSON types

private struct DDGResponse: Decodable {
    let AbstractText: String
    let AbstractURL: String
    let Heading: String
    let RelatedTopics: [DDGTopic]
}

private struct DDGTopic: Decodable {
    let Text: String
    let FirstURL: String
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        Text     = (try? c.decode(String.self, forKey: .Text)) ?? ""
        FirstURL = (try? c.decode(String.self, forKey: .FirstURL)) ?? ""
    }
    enum CodingKeys: String, CodingKey { case Text, FirstURL }
}
