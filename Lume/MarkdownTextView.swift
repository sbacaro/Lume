//
//  MarkdownTextView.swift
//  Lume
//

import SwiftUI
import AppKit
import Foundation

// MARK: - Font Scale Environment

/// Escala aplicada a todo o texto renderizado das mensagens.
/// Ajustável pelo usuário em Configurações → Aparência. 1.0 = tamanho padrão.
private struct MarkdownFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var markdownFontScale: CGFloat {
        get { self[MarkdownFontScaleKey.self] }
        set { self[MarkdownFontScaleKey.self] = newValue }
    }
}

// MARK: - Inline Markdown Cache

/// Parsear markdown inline (`AttributedString(markdown:)`) é caro. Durante o
/// streaming a `body` re-executa ~20x/s e, sem cache, TODOS os blocos estáveis
/// seriam reparseados a cada flush — custo O(n²) que estoura CPU e memória.
/// Memoiza o resultado por string. `NSCache` é thread-safe e libera entradas
/// automaticamente sob pressão de memória, então não cresce sem limite.
private final class AttrBox { let value: AttributedString; init(_ v: AttributedString) { value = v } }

enum MarkdownInlineCache {
    private static let cache: NSCache<NSString, AttrBox> = {
        let c = NSCache<NSString, AttrBox>()
        c.countLimit = 800
        return c
    }()

    static func render(_ text: String) -> AttributedString {
        let key = text as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .full
        let attr = (try? AttributedString(markdown: text, options: opts)) ?? AttributedString(text)
        cache.setObject(AttrBox(attr), forKey: key)
        return attr
    }
}

// MARK: - Main View

struct MarkdownTextView: View {
    let text: String
    var isStreaming: Bool = false
    var onSuggestionSelected: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Extrai o "processo" (raciocínio + ferramentas, em ordem) e a resposta final.
            let (events, answer) = extractProcess(text)

            if !events.isEmpty {
                ProcessTimelineView(events: events, isStreaming: isStreaming)
            }

            if isStreaming {
                let cleanedContent = removeSuggestionsBlock(from: answer)
                let blocks = parseBlocks(cleanedContent)
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    let isLast = index == blocks.count - 1
                    MarkdownBlockView(block: block, isStreaming: isLast).equatable()
                }
            } else if let suggestion = ContextManager.extractSuggestions(from: answer) {
                if !suggestion.textBefore.isEmpty {
                    ForEach(Array(parseBlocks(suggestion.textBefore).enumerated()), id: \.offset) { _, block in
                        MarkdownBlockView(block: block, isStreaming: false).equatable()
                    }
                }
                if let onSelect = onSuggestionSelected {
                    SuggestionCardsView(block: suggestion, onSelect: onSelect)
                        .padding(.vertical, 4)
                }
                if !suggestion.textAfter.isEmpty {
                    ForEach(Array(parseBlocks(suggestion.textAfter).enumerated()), id: \.offset) { _, block in
                        MarkdownBlockView(block: block, isStreaming: false).equatable()
                    }
                }
            } else {
                let blocks = parseBlocks(answer)
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    MarkdownBlockView(block: block, isStreaming: false).equatable()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func removeSuggestionsBlock(from content: String) -> String {
        let marker = "```suggestions"
        guard let start = content.range(of: marker) else { return content }
        if let end = content.range(of: "```", range: start.upperBound..<content.endIndex) {
            let before = String(content[content.startIndex..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(content[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return [before, after].filter { !$0.isEmpty }.joined(separator: "\n\n")
        } else {
            return String(content[content.startIndex..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func extractThinking(_ raw: String) -> (thinking: String?, main: String) {
        var thinkingParts: [String] = []
        var main = raw

        while let start = main.range(of: "<think>"),
              let end = main.range(of: "</think>", range: start.upperBound..<main.endIndex) {
            let thinkContent = String(main[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !thinkContent.isEmpty { thinkingParts.append(thinkContent) }
            let beforeThink = String(main[main.startIndex..<start.lowerBound])
            let afterThink = String(main[end.upperBound...])
            main = (beforeThink + afterThink).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = main.range(of: "<think>") {
            let thinkContent = String(main[start.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !thinkContent.isEmpty { thinkingParts.append(thinkContent) }
            main = String(main[main.startIndex..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let combined = thinkingParts.isEmpty ? nil : thinkingParts.joined(separator: "\n\n---\n\n")
        return (combined, main)
    }

    /// Extrai o processo (raciocínio `<think>` + ferramentas `[[TOOL:]]`, na ordem)
    /// e devolve também a resposta final já sem esses marcadores.
    func extractProcess(_ raw: String) -> (events: [ProcessEvent], answer: String) {
        var events: [ProcessEvent] = []
        var answer = ""
        var rest = Substring(raw)

        while !rest.isEmpty {
            let thinkR = rest.range(of: "<think>")
            let toolR = rest.range(of: "[[TOOL:")
            let lowers = [thinkR, toolR].compactMap { $0?.lowerBound }
            guard let nextLower = lowers.min() else {
                answer += rest
                break
            }
            answer += rest[rest.startIndex..<nextLower]

            if let tr = thinkR, tr.lowerBound == nextLower {
                let after = rest[tr.upperBound...]
                if let end = after.range(of: "</think>") {
                    let content = String(after[after.startIndex..<end.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty { events.append(ProcessEvent(kind: .reasoning(content))) }
                    rest = after[end.upperBound...]
                } else {
                    let content = String(after).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty { events.append(ProcessEvent(kind: .reasoning(content))) }
                    rest = Substring()
                }
            } else {
                let after = rest[nextLower...]   // começa em "[[TOOL:"
                if let end = after.range(of: "]]") {
                    let blockStr = String(after[after.startIndex..<end.upperBound])
                    if let item = Self.parseToolBlock(blockStr) {
                        events.append(ProcessEvent(kind: .tool(item)))
                    }
                    rest = after[end.upperBound...]
                } else {
                    rest = Substring()   // ferramenta parcial (streaming) — ignora
                }
            }
        }
        return (events, answer.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Converte "[[TOOL:name|input|output|success]]" em ToolCallItem.
    static func parseToolBlock(_ block: String) -> ToolCallItem? {
        guard block.hasPrefix("[[TOOL:"), block.hasSuffix("]]") else { return nil }
        let inner = String(block.dropFirst(7).dropLast(2))
        var parts: [String] = []
        for sep in ["∣", "|"] {
            parts = inner.components(separatedBy: sep)
            if parts.count >= 3 { break }
        }
        guard parts.count >= 3 else { return nil }
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        var input = parts[1].trimmingCharacters(in: .whitespaces)
        var output = parts[2].trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "⏎", with: "\n")   // restaura quebras de linha
        let success = parts.count >= 4 ? parts[3].trimmingCharacters(in: .whitespaces) == "1" : true
        if input.hasPrefix("{") || input.hasPrefix("[") {
            if let data = input.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                input = json.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            }
        }
        if output.count > 4000 { output = String(output.prefix(4000)) + "…" }
        return ToolCallItem(name: name, input: input, output: output, success: success)
    }

    func parseBlocks(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = raw.components(separatedBy: "\n")
        var i = 0

        // Nível de indentação para listas aninhadas (2 espaços ou 1 tab = 1 nível, máx. 6).
        func indentLevel(of line: String) -> Int {
            var spaces = 0
            for ch in line {
                if ch == " " { spaces += 1 }
                else if ch == "\t" { spaces += 4 }
                else { break }
            }
            return min(spaces / 2, 6)
        }

        // Divide uma linha de tabela em células, removendo as bordas externas.
        func splitRow(_ line: String) -> [String] {
            var s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("|") { s.removeFirst() }
            if s.hasSuffix("|") { s.removeLast() }
            return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        // Verifica se a linha é o separador de cabeçalho de tabela (ex.: |---|:--:|).
        func isTableSeparator(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.contains("-"), t.contains("|") else { return false }
            let cells = splitRow(t)
            guard !cells.isEmpty else { return false }
            return cells.allSatisfy { cell in
                let c = cell.trimmingCharacters(in: .whitespaces)
                return !c.isEmpty && c.contains("-") && c.allSatisfy { $0 == "-" || $0 == ":" }
            }
        }

        func parseAlignments(_ line: String) -> [TableColumnAlignment] {
            splitRow(line).map { cell in
                let c = cell.trimmingCharacters(in: .whitespaces)
                let left = c.hasPrefix(":")
                let right = c.hasSuffix(":")
                if left && right { return .center }
                if right { return .trailing }
                return .leading
            }
        }

        while i < lines.count {
            let rawLine = lines[i]
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let indent = indentLevel(of: rawLine)

            // Detecta bloco de tool call — formato: [[TOOL:nome∣input∣output∣success]]
            if line.hasPrefix("[[TOOL:") && line.hasSuffix("]]") {
                let inner = String(line.dropFirst(7).dropLast(2))
                let separators = ["∣", "|"]
                var parts: [String] = []
                for separator in separators {
                    parts = inner.components(separatedBy: separator)
                    if parts.count >= 3 { break }
                }
                if parts.count >= 3 {
                    let name = parts[0].trimmingCharacters(in: .whitespaces)
                    var input = parts[1].trimmingCharacters(in: .whitespaces)
                    var output = parts[2].trimmingCharacters(in: .whitespaces)
                    let success = parts.count >= 4 ? parts[3].trimmingCharacters(in: .whitespaces) == "1" : true
                    if input.hasPrefix("{") || input.hasPrefix("[") {
                        if let data = input.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            input = formatJSON(json)
                        }
                    }
                    if output.count > 500 {
                        output = String(output.prefix(500)) + "..."
                    }
                    let item = ToolCallItem(name: name, input: input, output: output, success: success)
                    // Agrupa chamadas consecutivas numa única caixa.
                    if case .toolGroup(let items)? = blocks.last {
                        blocks[blocks.count - 1] = .toolGroup(calls: items + [item])
                    } else {
                        blocks.append(.toolGroup(calls: [item]))
                    }
                    i += 1; continue
                }
            }

            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language,
                                    content: codeLines.joined(separator: "\n")))
                i += 1; continue
            }

            // Tabela: linha com "|" seguida por uma linha separadora (|---|---|).
            if line.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                let headers = splitRow(line)
                let alignments = parseAlignments(lines[i + 1])
                i += 2
                var rows: [[String]] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty || !t.contains("|") { break }
                    rows.append(splitRow(t))
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows, alignments: alignments))
                continue
            }

            // Blockquote: agrupa linhas consecutivas iniciadas por ">".
            if line.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    let stripped = String(t.drop(while: { $0 == ">" })).trimmingCharacters(in: .whitespaces)
                    quoteLines.append(stripped)
                    i += 1
                }
                blocks.append(.blockquote(lines: quoteLines))
                continue
            }

            if line.hasPrefix("#### ")      { blocks.append(.heading(level: 4, content: String(line.dropFirst(5)))); i += 1; continue }
            if line.hasPrefix("### ")       { blocks.append(.heading(level: 3, content: String(line.dropFirst(4)))); i += 1; continue }
            if line.hasPrefix("## ")        { blocks.append(.heading(level: 2, content: String(line.dropFirst(3)))); i += 1; continue }
            if line.hasPrefix("# ")         { blocks.append(.heading(level: 1, content: String(line.dropFirst(2)))); i += 1; continue }

            // Task list (checkbox) — precisa vir antes do bullet genérico.
            if let task = Self.parseTaskItem(line) {
                blocks.append(.taskItem(checked: task.checked, content: task.content, indent: indent))
                i += 1; continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") || line.hasPrefix("• ") {
                blocks.append(.bulletItem(content: String(line.dropFirst(2)), indent: indent))
                i += 1; continue
            }

            if let num = Self.parseNumberedItem(line) {
                blocks.append(.numberedItem(number: num.number, content: num.content, indent: indent))
                i += 1; continue
            }

            if line == "---" || line == "***" || line == "___" {
                blocks.append(.divider); i += 1; continue
            }

            if line.isEmpty {
                i += 1; continue
            }

            var paragraphLines = [line]
            while i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if next.isEmpty { break }
                if next.hasPrefix("#") || next.hasPrefix("- ") || next.hasPrefix("* ") ||
                   next.hasPrefix("+ ") || next.hasPrefix("• ") || next.hasPrefix("```") ||
                   next.hasPrefix("[[TOOL:") || next.hasPrefix(">") { break }
                if Self.startsWithNumberedMarker(next) { break }
                if next.contains("|"), i + 2 < lines.count, isTableSeparator(lines[i + 2]) { break }
                paragraphLines.append(next)
                i += 1
            }
            blocks.append(.paragraph(content: paragraphLines.joined(separator: " ")))
            i += 1
        }
        return blocks
    }

    // MARK: - Parsing manual (substitui Swift Regex no hot path do streaming)
    // Swift Regex (`firstMatch(of:/.../)`) é lento e era executado por linha a
    // cada flush (~20x/s), dominando a CPU. Estas versões escaneiam caracteres
    // diretamente — ordens de magnitude mais rápidas.

    private static func isDigit(_ s: Unicode.Scalar) -> Bool { s.value >= 48 && s.value <= 57 }
    private static func isSpace(_ s: Unicode.Scalar) -> Bool { s == " " || s == "\t" }
    private static func scalarsToString<S: Sequence>(_ s: S) -> String where S.Element == Unicode.Scalar {
        var out = ""
        out.unicodeScalars.append(contentsOf: s)
        return out
    }

    /// "- [ ] texto" / "- [x] texto" (também `*` e `+`).
    static func parseTaskItem(_ line: String) -> (checked: Bool, content: String)? {
        let chars = Array(line.unicodeScalars)
        guard chars.count >= 5 else { return nil }
        guard chars[0] == "-" || chars[0] == "*" || chars[0] == "+" else { return nil }
        var i = 1
        guard i < chars.count, isSpace(chars[i]) else { return nil }
        while i < chars.count, isSpace(chars[i]) { i += 1 }
        guard i + 2 < chars.count, chars[i] == "[", chars[i + 2] == "]" else { return nil }
        let mark = chars[i + 1]
        guard mark == " " || mark == "x" || mark == "X" else { return nil }
        i += 3
        guard i < chars.count, isSpace(chars[i]) else { return nil }
        while i < chars.count, isSpace(chars[i]) { i += 1 }
        let content = scalarsToString(chars[i...])
        return (mark == "x" || mark == "X", content)
    }

    /// "123. texto".
    static func parseNumberedItem(_ line: String) -> (number: Int, content: String)? {
        let chars = Array(line.unicodeScalars)
        var i = 0
        while i < chars.count, isDigit(chars[i]) { i += 1 }
        guard i > 0, i < chars.count, chars[i] == "." else { return nil }
        let number = Int(scalarsToString(chars[0..<i])) ?? 1
        i += 1
        guard i < chars.count, isSpace(chars[i]) else { return nil }
        while i < chars.count, isSpace(chars[i]) { i += 1 }
        guard i < chars.count else { return nil }
        let content = scalarsToString(chars[i...])
        return (number, content)
    }

    /// Detecta apenas o início "123. " (lookahead barato).
    static func startsWithNumberedMarker(_ line: String) -> Bool {
        let chars = Array(line.unicodeScalars)
        var i = 0
        while i < chars.count, isDigit(chars[i]) { i += 1 }
        guard i > 0, i < chars.count, chars[i] == "." else { return false }
        i += 1
        return i < chars.count && isSpace(chars[i])
    }

    private func formatJSON(_ json: [String: Any]) -> String {
        var parts: [String] = []
        for (key, value) in json {
            let valueStr: String
            if let strVal = value as? String {
                valueStr = strVal.count > 50 ? String(strVal.prefix(50)) + "..." : strVal
            } else if let numVal = value as? NSNumber {
                valueStr = "\(numVal)"
            } else {
                valueStr = "\(value)"
            }
            parts.append("\(key): \(valueStr)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Thinking Block

struct ThinkingBlockView: View {
    let content: String
    var isStreaming: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if isStreaming {
                        ProgressView().scaleEffect(0.5)
                    } else {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    Text(isStreaming ? "Thinking…" : "Internal reasoning")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(content)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.03),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Process Timeline (raciocínio + ferramentas, estilo Claude)

struct ProcessTimelineView: View {
    let events: [ProcessEvent]
    var isStreaming: Bool = false
    @State private var expanded = false
    @Environment(\.markdownFontScale) private var scale

    private var summary: String {
        var searches = 0, pages = 0, thoughts = 0
        for e in events {
            switch e.kind {
            case .reasoning: thoughts += 1
            case .tool(let t):
                if t.name == "web_search" { searches += 1 }
                else if t.name == "web_fetch" { pages += 1 }
            }
        }
        var parts: [String] = []
        if thoughts > 0 { parts.append(String(localized: "Reasoning")) }
        if searches > 0 { parts.append("\(searches) search\(searches > 1 ? "es" : "")") }
        if pages > 0 { parts.append("\(pages) page\(pages > 1 ? "s" : "")") }
        return parts.isEmpty ? "Processo" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(isStreaming ? "Thinking…" : summary)
                        .font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(.secondary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8 * scale, weight: .semibold)).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Identidade POSICIONAL (não `event.id`): `extractProcess` recria
                    // os eventos a cada flush com UUIDs novos; usar o UUID faria o
                    // SwiftUI reconstruir a timeline inteira ~12x/s. A ordem é
                    // append-only, então a posição é estável e só o último muda.
                    ForEach(Array(events.enumerated()), id: \.offset) { idx, event in
                        ProcessRow(event: event, isLast: idx == events.count - 1)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct ProcessRow: View {
    let event: ProcessEvent
    let isLast: Bool
    @Environment(\.markdownFontScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1).frame(width: 18, height: 18)
                    Image(systemName: icon).font(.system(size: 9)).foregroundStyle(iconColor)
                }
                if !isLast {
                    Rectangle().fill(Color.primary.opacity(0.10))
                        .frame(width: 1).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                content
            }
            .padding(.bottom, isLast ? 0 : 12)

            Spacer(minLength: 0)
        }
    }

    private var icon: String {
        switch event.kind {
        case .reasoning: return "clock"
        case .tool(let t): return ToolGroupView.timelineIcon(t.name)
        }
    }

    private var iconColor: Color {
        if case .tool(let t) = event.kind, !t.success { return .red }
        return .secondary
    }

    @ViewBuilder
    private var content: some View {
        switch event.kind {
        case .reasoning(let text):
            Text(text)
                .font(.system(size: 11 * scale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .tool(let t):
            Text(ToolGroupView.timelineLabel(t.name))
                .font(.system(size: 11.5 * scale, weight: .medium))
                .foregroundStyle(t.success ? Color.primary : Color.red)
            let detail = ToolGroupView.timelineDetail(t)
            if !detail.isEmpty {
                Text(detail).font(.system(size: 10 * scale)).foregroundStyle(.tertiary).lineLimit(1)
            }
            if t.name == "web_search" {
                let results = SearchResultParser.parse(t.output)
                if !results.isEmpty {
                    SearchResultsCard(results: results)
                }
            }
        }
    }
}

// MARK: - Search results parsing + card

enum SearchResultParser {
    struct Item: Identifiable { let id = UUID(); let title: String; let url: String }

    static func parse(_ output: String) -> [Item] {
        var items: [Item] = []
        var currentTitle = ""
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("**") {
                var title = line.replacingOccurrences(of: "**", with: "")
                // remove prefixo "N. "
                while let f = title.first, f.isNumber { title.removeFirst() }
                if title.hasPrefix(".") { title.removeFirst() }
                currentTitle = title.trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("URL:") || line.hasPrefix("Fonte:") {
                let url = line
                    .replacingOccurrences(of: "URL:", with: "")
                    .replacingOccurrences(of: "Fonte:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !url.isEmpty {
                    items.append(Item(title: currentTitle.isEmpty ? url : currentTitle, url: url))
                    currentTitle = ""
                }
            }
        }
        return items
    }
}

private struct SearchResultsCard: View {
    let results: [SearchResultParser.Item]
    @Environment(\.markdownFontScale) private var scale

    var body: some View {
        let shown = Array(results.prefix(8))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { item in
                HStack(spacing: 8) {
                    Image(systemName: "globe").font(.system(size: 9.5 * scale))
                        .foregroundStyle(.secondary).frame(width: 14)
                    Text(item.title).font(.system(size: 10.5 * scale)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(host(item.url)).font(.system(size: 9.5 * scale)).foregroundStyle(.tertiary).lineLimit(1)
                }
                .padding(.vertical, 5).padding(.horizontal, 8)
                if item.id != shown.last?.id { Divider().opacity(0.4) }
            }
        }
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        .padding(.top, 4)
    }

    private func host(_ url: String) -> String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
    }
}

// MARK: - Tool Group (caixa única recolhível para várias ferramentas)

struct ToolGroupView: View {
    let calls: [ToolCallItem]
    @State private var expanded = false

    private var summary: String {
        func count(_ names: Set<String>) -> Int { calls.filter { names.contains($0.name) }.count }
        let searches = count(["web_search"])
        let pages    = count(["web_fetch"])
        let shells   = count(["run_shell"])
        let files    = count(["read_file", "write_file", "list_directory", "create_directory"])
        var parts: [String] = []
        if searches > 0 { parts.append("\(searches) search\(searches > 1 ? "es" : "")") }
        if pages > 0    { parts.append("\(pages) page\(pages > 1 ? "s" : "")") }
        if shells > 0   { parts.append("\(shells) command\(shells > 1 ? "s" : "")") }
        if files > 0    { parts.append("\(files) file\(files > 1 ? "s" : "")") }
        return parts.isEmpty ? String(localized: "\(calls.count) actions") : parts.joined(separator: " · ")
    }

    private var icon: String {
        if calls.contains(where: { $0.name == "web_search" || $0.name == "web_fetch" }) { return "globe" }
        if calls.contains(where: { $0.name == "run_shell" }) { return "terminal" }
        return "wrench.and.screwdriver"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(summary)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                // Timeline estilo Claude: linha conectora + ícone + ação por etapa.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(calls.enumerated()), id: \.offset) { idx, call in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 0) {
                                ZStack {
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                                        .frame(width: 18, height: 18)
                                    Image(systemName: Self.timelineIcon(call.name))
                                        .font(.system(size: 9))
                                        .foregroundStyle(call.success ? Color.secondary : Color.red)
                                }
                                if idx < calls.count - 1 {
                                    Rectangle().fill(Color.primary.opacity(0.10))
                                        .frame(width: 1).frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.timelineLabel(call.name))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(call.success ? Color.primary : Color.red)
                                let detail = Self.timelineDetail(call)
                                if !detail.isEmpty {
                                    Text(detail)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.bottom, idx < calls.count - 1 ? 12 : 0)

                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Timeline helpers

    static func timelineIcon(_ name: String) -> String {
        switch name {
        case "web_search":       return "magnifyingglass"
        case "web_fetch":        return "globe"
        case "run_shell":        return "terminal"
        case "read_file":        return "doc.text"
        case "write_file":       return "square.and.pencil"
        case "list_directory":   return "folder"
        case "create_directory": return "folder.badge.plus"
        default:                 return "wrench.and.screwdriver"
        }
    }

    static func timelineLabel(_ name: String) -> String {
        switch name {
        case "web_search":       return "Pesquisou na web"
        case "web_fetch":        return String(localized: "Accessed page")
        case "run_shell":        return "Executou comando"
        case "read_file":        return String(localized: "Read file")
        case "write_file":       return String(localized: "Wrote file")
        case "list_directory":   return String(localized: "Listed directory")
        case "create_directory": return String(localized: "Created directory")
        default:                 return name
        }
    }

    /// Extrai o parâmetro mais relevante do input (query/url/path/command).
    static func timelineDetail(_ call: ToolCallItem) -> String {
        let input = call.input
        for key in ["query", "url", "path", "command"] {
            if let r = input.range(of: "\(key):") {
                let after = input[r.upperBound...]
                let val = after.prefix(while: { $0 != "," && $0 != "}" })
                    .trimmingCharacters(in: .whitespaces)
                if !val.isEmpty { return val }
            }
        }
        return input.count > 70 ? String(input.prefix(70)) + "…" : input
    }
}

// MARK: - Tool Call Block View

struct ToolCallBlockView: View {
    let name: String
    let input: String
    let output: String
    let success: Bool
    @State private var isExpanded = false

    private let errorColor = Color(red: 0.9, green: 0.3, blue: 0.3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .frame(width: 14)
                    Image(systemName: toolIcon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(success ? Color.secondary : errorColor)
                    Text(toolLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    if !success {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(errorColor)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if !input.isEmpty && input != "{}" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Input")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                            Text(input)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if !output.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Output")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                            Text(String(output.prefix(600)))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(success ? Color.secondary : errorColor)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    private var toolIcon: String {
        switch name {
        case "run_shell":        return "terminal"
        case "read_file":        return "doc.text"
        case "write_file":       return "square.and.pencil"
        case "list_directory":   return "folder"
        case "create_directory": return "folder.badge.plus"
        case "web_search":       return "magnifyingglass"
        case "web_fetch":        return "globe"
        default:                 return "wrench.and.screwdriver"
        }
    }

    private var toolLabel: String {
        switch name {
        case "run_shell":
            let cmd = input.components(separatedBy: "\"command\":\"").last?
                .components(separatedBy: "\"").first ?? input
            return "Executou `\(String(cmd.trimmingCharacters(in: .whitespaces).prefix(60)))`"
        case "read_file":
            let path = input.components(separatedBy: "\"path\":\"").last?
                .components(separatedBy: "\"").first ?? input
            return "Leu \(URL(fileURLWithPath: path).lastPathComponent)"
        case "write_file":
            let path = input.components(separatedBy: "\"path\":\"").last?
                .components(separatedBy: "\"").first ?? input
            return "Escreveu \(URL(fileURLWithPath: path).lastPathComponent)"
        case "list_directory":
            let path = input.components(separatedBy: "\"path\":\"").last?
                .components(separatedBy: "\"").first ?? input
            return "Listou \(URL(fileURLWithPath: path).lastPathComponent)"
        case "create_directory":
            return String(localized: "Created directory")
        case "web_search":
            let query = input.components(separatedBy: "\"query\":\"").last?
                .components(separatedBy: "\"").first ?? input
            return "Pesquisou \"\(String(query.prefix(50)))\""
        case "web_fetch":
            let url = input.components(separatedBy: "\"url\":\"").last?
                .components(separatedBy: "\"").first ?? input
            return "Acessou \(String(url.prefix(50)))"
        default:
            return name
        }
    }
}

// MARK: - Block enum

enum TableColumnAlignment: Equatable {
    case leading, center, trailing
}

struct ToolCallItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let input: String
    let output: String
    let success: Bool

    // Compara por CONTEÚDO (ignora o `id` aleatório), para que reparsear a mesma
    // chamada a cada flush produza um item "igual" e o SwiftUI possa pular o re-render.
    static func == (lhs: ToolCallItem, rhs: ToolCallItem) -> Bool {
        lhs.name == rhs.name && lhs.input == rhs.input &&
        lhs.output == rhs.output && lhs.success == rhs.success
    }
}

/// Evento do "processo" do modelo (raciocínio ou chamada de ferramenta), em ordem.
struct ProcessEvent: Identifiable {
    let id = UUID()
    enum Kind {
        case reasoning(String)
        case tool(ToolCallItem)
    }
    let kind: Kind
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, content: String)
    case code(language: String?, content: String)
    case inlineCode(content: String)
    case paragraph(content: String)
    case bulletItem(content: String, indent: Int)
    case numberedItem(number: Int, content: String, indent: Int)
    case taskItem(checked: Bool, content: String, indent: Int)
    case blockquote(lines: [String])
    case table(headers: [String], rows: [[String]], alignments: [TableColumnAlignment])
    case divider
    /// Várias chamadas de ferramenta consecutivas agrupadas numa única caixa.
    case toolGroup(calls: [ToolCallItem])
}

// MARK: - Block View

struct MarkdownBlockView: View, Equatable {
    let block: MarkdownBlock
    var isStreaming: Bool = false

    // Permite que o SwiftUI pule o re-render de blocos idênticos durante o
    // streaming (só o último bloco muda). Usado via `.equatable()` na ForEach.
    static func == (lhs: MarkdownBlockView, rhs: MarkdownBlockView) -> Bool {
        lhs.isStreaming == rhs.isStreaming && lhs.block == rhs.block
    }

    var body: some View {
        switch block {
        case .heading(let level, let content):
            MarkdownHeadingView(level: level, content: content)
        case .code(let language, let content):
            // Auto-expande blocos curtos (≤40 linhas); colapsa os longos.
            CodeBlockView(
                code: content,
                language: language,
                defaultExpanded: content.split(separator: "\n", omittingEmptySubsequences: false).count <= 40
            )
        case .inlineCode(let content):
            Text(content)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(4)
        case .paragraph(let content):
            MarkdownParagraphView(content: content, showCursor: isStreaming)
        case .bulletItem(let content, let indent):
            MarkdownBulletView(content: content, indent: indent, showCursor: isStreaming)
        case .numberedItem(let number, let content, let indent):
            MarkdownNumberedView(number: number, content: content, indent: indent)
        case .taskItem(let checked, let content, let indent):
            MarkdownTaskItemView(checked: checked, content: content, indent: indent)
        case .blockquote(let lines):
            MarkdownBlockquoteView(lines: lines)
        case .table(let headers, let rows, let alignments):
            MarkdownTableView(headers: headers, rows: rows, alignments: alignments)
        case .divider:
            Divider().padding(.vertical, 4)
        case .toolGroup(let calls):
            ToolGroupView(calls: calls)
        }
    }
}

// MARK: - Heading

struct MarkdownHeadingView: View {
    let level: Int
    let content: String
    @Environment(\.markdownFontScale) private var scale

    var body: some View {
        Text(renderInline(content))
            .font(.system(size: baseSize * scale, weight: .bold))
            .padding(.top, level <= 2 ? 8 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var baseSize: CGFloat {
        switch level {
        case 1: return 22
        case 2: return 18
        case 3: return 16
        default: return 14.5
        }
    }

    private func renderInline(_ text: String) -> AttributedString {
        MarkdownInlineCache.render(text)
    }
}

// MARK: - Paragraph

struct MarkdownParagraphView: View {
    let content: String
    var showCursor: Bool = false
    @Environment(\.markdownFontScale) private var scale

    var body: some View {
        Group {
            if showCursor {
                // Durante o streaming, o último bloco CRESCE a cada frame. Fazer
                // `AttributedString(markdown:)` nele 12x/s é O(n²) e satura a CPU.
                // Renderiza texto puro enquanto escreve; o parse rico acontece
                // uma única vez quando a mensagem finaliza (showCursor = false).
                Text(content + " ▋")
            } else {
                Text(renderInline(content)).textSelection(.enabled)
            }
        }
        .font(.system(size: 14 * scale))
        .lineSpacing(4 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func renderInline(_ text: String) -> AttributedString {
        MarkdownInlineCache.render(text)
    }
}

// MARK: - Bullet

struct MarkdownBulletView: View {
    let content: String
    var indent: Int = 0
    var showCursor: Bool = false
    @Environment(\.markdownFontScale) private var scale

    private var marker: String {
        switch indent { case 0: return "•"; case 1: return "◦"; default: return "▪" }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).foregroundStyle(.secondary).frame(minWidth: 12)
            Group {
                if showCursor {
                    Text(content + " ▋")   // texto puro durante o streaming (ver MarkdownParagraphView)
                } else {
                    Text(renderInline(content)).textSelection(.enabled)
                }
            }
            .font(.system(size: 14 * scale))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(indent) * 16)
    }

    func renderInline(_ text: String) -> AttributedString {
        MarkdownInlineCache.render(text)
    }
}

// MARK: - Numbered

struct MarkdownNumberedView: View {
    let number: Int
    let content: String
    var indent: Int = 0
    @Environment(\.markdownFontScale) private var scale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(.system(size: 14 * scale))
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .trailing)
            Text(renderInline(content))
                .font(.system(size: 14 * scale))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(indent) * 16)
    }

    func renderInline(_ text: String) -> AttributedString {
        MarkdownInlineCache.render(text)
    }
}

// MARK: - Task List Item

struct MarkdownTaskItemView: View {
    let checked: Bool
    let content: String
    var indent: Int = 0
    @Environment(\.markdownFontScale) private var scale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 13 * scale))
                .foregroundStyle(checked ? Color.accentColor : Color.secondary)
            Text(renderInline(content))
                .font(.system(size: 14 * scale))
                .foregroundStyle(checked ? .secondary : .primary)
                .strikethrough(checked, color: .secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(indent) * 16)
    }

    func renderInline(_ text: String) -> AttributedString {
        MarkdownInlineCache.render(text)
    }
}

// MARK: - Blockquote

struct MarkdownBlockquoteView: View {
    let lines: [String]
    @Environment(\.markdownFontScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.5))
                .frame(width: 3)
            Text(renderInline(lines.joined(separator: "\n")))
                .font(.system(size: 14 * scale))
                .foregroundStyle(.secondary)
                .italic()
                .textSelection(.enabled)
                .padding(.leading, 12)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    func renderInline(_ text: String) -> AttributedString {
        MarkdownInlineCache.render(text)
    }
}

// MARK: - Table

struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    let alignments: [TableColumnAlignment]
    @Environment(\.markdownFontScale) private var scale

    private var columnCount: Int {
        max(headers.count, rows.map { $0.count }.max() ?? 0)
    }

    private func alignment(for column: Int) -> Alignment {
        guard column < alignments.count else { return .leading }
        switch alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(for column: Int) -> TextAlignment {
        guard column < alignments.count else { return .leading }
        switch alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func cell(_ value: String, column: Int, isHeader: Bool) -> some View {
        Text(renderInline(Self.normalizeCell(value)))
            .font(.system(size: 13 * scale, weight: isHeader ? .semibold : .regular))
            .foregroundStyle(isHeader ? .primary : .secondary)
            .multilineTextAlignment(textAlignment(for: column))
            .fixedSize(horizontal: false, vertical: true)   // quebra o texto em vez de esticar
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: alignment(for: column))
    }

    /// Converte quebras de linha HTML (<br>) em quebras reais dentro da célula.
    private static func normalizeCell(_ s: String) -> String {
        s.replacingOccurrences(of: "<br>", with: "\n")
         .replacingOccurrences(of: "<br/>", with: "\n")
         .replacingOccurrences(of: "<br />", with: "\n")
    }

    var body: some View {
        // Sem ScrollView horizontal: a tabela ocupa a largura disponível (de leitura)
        // e o texto das células quebra, evitando tabelas gigantes que vazam.
        VStack(spacing: 0) {
            // Cabeçalho
            HStack(spacing: 0) {
                ForEach(0..<columnCount, id: \.self) { col in
                    cell(col < headers.count ? headers[col] : "", column: col, isHeader: true)
                    if col < columnCount - 1 { Divider() }
                }
            }
            .background(Color.primary.opacity(0.06))

            Divider()

            // Linhas
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(0..<columnCount, id: \.self) { col in
                        cell(col < row.count ? row[col] : "", column: col, isHeader: false)
                        if col < columnCount - 1 { Divider() }
                    }
                }
                .background(rowIndex % 2 == 1 ? Color.primary.opacity(0.02) : Color.clear)
                if rowIndex < rows.count - 1 { Divider().opacity(0.5) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.vertical, 4)
    }

    func renderInline(_ text: String) -> AttributedString {
        MarkdownInlineCache.render(text)
    }
}

// MARK: - Code Block

struct CodeBlockView: View {
    let code: String
    let language: String?
    var defaultExpanded: Bool = false

    @State private var copied = false
    @State private var isExpanded: Bool

    private var isDiff: Bool {
        language?.lowercased() == "diff" || language?.lowercased() == "patch" ||
        (code.contains("\n+") && code.contains("\n@@"))
    }

    init(code: String, language: String?, defaultExpanded: Bool = false) {
        self.code = code
        self.language = language
        self.defaultExpanded = defaultExpanded
        self._isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: languageIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(languageColor)
                    Text(language ?? String(localized: "code"))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(languageColor)
                    if !isExpanded {
                        Text("· \(lineCount) lines")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isDiff && !isExpanded { diffStats }
                    Button(action: copyCode) {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                            Text(copied ? "Copied" : "Copy").font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(red: 0.14, green: 0.14, blue: 0.16))

            if isExpanded {
                Divider().opacity(0.3)
                if isDiff {
                    diffView
                } else {
                    SyntaxHighlightedView(code: code, language: language ?? "")
                        .transition(.opacity)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }

    private var diffView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                    DiffLineView(line: line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
    }

    private var diffStats: some View {
        let added = diffLines.filter { $0.type == .added }.count
        let removed = diffLines.filter { $0.type == .removed }.count
        return HStack(spacing: 6) {
            if added > 0 { Text("+\(added)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.green) }
            if removed > 0 { Text("-\(removed)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.red) }
        }
    }

    private var diffLines: [DiffLine] {
        code.components(separatedBy: "\n").map { line in
            if line.hasPrefix("+") && !line.hasPrefix("+++") { return DiffLine(text: line, type: .added) }
            if line.hasPrefix("-") && !line.hasPrefix("---") { return DiffLine(text: line, type: .removed) }
            if line.hasPrefix("@@")                          { return DiffLine(text: line, type: .hunk) }
            if line.hasPrefix("+++") || line.hasPrefix("---"){ return DiffLine(text: line, type: .fileHeader) }
            return DiffLine(text: line, type: .context)
        }
    }

    private var lineCount: Int { code.components(separatedBy: "\n").count }

    private var languageIcon: String {
        switch language?.lowercased() {
        case "swift": return "swift"
        case "python", "py": return "chevron.left.forwardslash.chevron.right"
        case "javascript", "js", "typescript", "ts": return "globe"
        case "bash", "sh", "shell", "zsh": return "terminal"
        case "json": return "curlybraces"
        case "html", "xml": return "chevron.left.slash.chevron.right"
        case "css", "scss": return "paintbrush"
        case "sql": return "cylinder"
        case "diff", "patch": return "plusminus"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private var languageColor: Color {
        switch language?.lowercased() {
        case "swift": return Color(red: 0.99, green: 0.56, blue: 0.28)
        case "python", "py": return Color(red: 0.27, green: 0.58, blue: 0.78)
        case "javascript", "js": return Color(red: 0.95, green: 0.82, blue: 0.16)
        case "typescript", "ts": return Color(red: 0.18, green: 0.49, blue: 0.80)
        case "bash", "sh", "shell", "zsh": return Color(red: 0.30, green: 0.80, blue: 0.50)
        case "json": return Color(red: 0.60, green: 0.85, blue: 0.60)
        case "html", "xml": return Color(red: 0.90, green: 0.45, blue: 0.28)
        case "css", "scss": return Color(red: 0.26, green: 0.56, blue: 0.86)
        case "rust": return Color(red: 0.95, green: 0.50, blue: 0.25)
        case "go": return Color(red: 0.40, green: 0.75, blue: 0.85)
        default: return .secondary
        }
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}

// MARK: - Syntax Highlighted View

struct SyntaxHighlightedView: View {
    let code: String
    let language: String

    var body: some View {
        let lines = code.components(separatedBy: "\n")
        let baseLineHeight: CGFloat = 18
        let minLines: CGFloat = 6
        let calculatedHeight = max(CGFloat(lines.count) * baseLineHeight + 24, minLines * baseLineHeight + 24)

        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .top, spacing: 0) {
                        Text(String(format: "%3d", idx + 1))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .frame(width: 36, alignment: .trailing)
                            .padding(.trailing, 8)

                        Text(highlightLine(line))
                            .font(.system(size: 12.5, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(minHeight: calculatedHeight, maxHeight: calculatedHeight)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
    }

    private func highlightLine(_ line: String) -> AttributedString {
        let nsAttr = SyntaxHighlighter.highlight(
            line: line,
            language: language,
            baseFont: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        )
        return (try? AttributedString(nsAttr, including: \.appKit)) ?? AttributedString(line)
    }
}

// MARK: - Syntax Highlighter

enum SyntaxHighlighter {
    // Cache do realce por (linha + linguagem + tamanho de fonte). Durante o
    // streaming, blocos de código longos seriam re-realçados linha a linha a
    // cada flush; o cache evita esse retrabalho. NSCache libera sob pressão.
    private static let lineCache: NSCache<NSString, NSAttributedString> = {
        let c = NSCache<NSString, NSAttributedString>()
        c.countLimit = 3000
        return c
    }()

    static func highlight(line: String, language: String, baseFont: NSFont) -> NSAttributedString {
        let key = "\(language.lowercased())|\(Int(baseFont.pointSize))|\(line)" as NSString
        if let hit = lineCache.object(forKey: key) { return hit }
        let result = computeHighlight(line: line, language: language, baseFont: baseFont)
        lineCache.setObject(result, forKey: key)
        return result
    }

    private static func computeHighlight(line: String, language: String, baseFont: NSFont) -> NSAttributedString {
        switch language.lowercased() {
        case "swift":                return highlightSwift(line, font: baseFont)
        case "python", "py":         return highlightPython(line, font: baseFont)
        case "javascript", "js", "typescript", "ts": return highlightJavaScript(line, font: baseFont)
        case "bash", "sh", "shell", "zsh": return highlightBash(line, font: baseFont)
        case "json":                 return highlightJSON(line, font: baseFont)
        case "html", "xml":          return highlightHTML(line, font: baseFont)
        case "css", "scss":          return highlightCSS(line, font: baseFont)
        case "sql":                  return highlightSQL(line, font: baseFont)
        case "rust":                 return highlightRust(line, font: baseFont)
        default:                     return defaultLine(line, font: baseFont)
        }
    }

    private static let colorText       = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
    private static let colorKeyword    = NSColor(red: 0.98, green: 0.40, blue: 0.62, alpha: 1)
    private static let colorString     = NSColor(red: 0.98, green: 0.56, blue: 0.35, alpha: 1)
    private static let colorComment    = NSColor(red: 0.42, green: 0.54, blue: 0.41, alpha: 1)
    private static let colorNumber     = NSColor(red: 0.68, green: 0.56, blue: 0.96, alpha: 1)
    private static let colorType       = NSColor(red: 0.42, green: 0.83, blue: 0.97, alpha: 1)
    private static let colorFunction   = NSColor(red: 0.66, green: 0.83, blue: 0.48, alpha: 1)
    private static let colorAttribute  = NSColor(red: 0.95, green: 0.73, blue: 0.45, alpha: 1)
    private static let colorVariable   = NSColor(red: 0.74, green: 0.87, blue: 1.00, alpha: 1)
    private static let colorBackground = NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)

    private static func attr(_ color: NSColor, _ font: NSFont, bold: Bool = false) -> [NSAttributedString.Key: Any] {
        let f = bold ? NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold) : font
        return [.foregroundColor: color, .font: f, .backgroundColor: colorBackground]
    }

    private static func defaultLine(_ line: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: line, attributes: attr(colorText, font))
    }

    private static func highlightSwift(_ line: String, font: NSFont) -> NSAttributedString {
        let keywords: Set<String> = [
            "import","let","var","func","class","struct","enum","protocol","extension","return",
            "if","else","guard","switch","case","default","for","in","while","repeat","do","try",
            "catch","throw","throws","async","await","actor","nil","true","false","self","Self",
            "super","static","final","override","private","public","internal","fileprivate","open",
            "mutating","nonmutating","lazy","weak","unowned","where","init","deinit","subscript",
            "typealias","associatedtype","some","any","as","is","break","continue","fallthrough","defer","inout"
        ]
        let types: Set<String> = [
            "String","Int","Double","Float","Bool","Array","Dictionary","Set","Optional","Any",
            "AnyObject","Void","Never","Data","Date","URL","UUID","CGFloat","View","Text","Button"
        ]
        return tokenize(line, font: font, keywords: keywords, types: types,
                        commentPrefix: "//", stringDelimiters: ["\""], attrPrefix: "@", hashPrefix: "#")
    }

    private static func highlightPython(_ line: String, font: NSFont) -> NSAttributedString {
        let keywords: Set<String> = [
            "def","class","import","from","return","if","elif","else","for","while","try","except",
            "finally","with","as","pass","break","continue","lambda","yield","raise","del","global",
            "nonlocal","and","or","not","in","is","None","True","False","async","await"
        ]
        let types: Set<String> = ["str","int","float","bool","list","dict","set","tuple","print","len"]
        return tokenize(line, font: font, keywords: keywords, types: types,
                        commentPrefix: "#", stringDelimiters: ["\"","'"], attrPrefix: nil, hashPrefix: nil)
    }

    private static func highlightJavaScript(_ line: String, font: NSFont) -> NSAttributedString {
        let keywords: Set<String> = [
            "const","let","var","function","return","if","else","for","while","do","switch","case",
            "break","continue","class","extends","import","export","default","new","this","typeof",
            "instanceof","null","undefined","true","false","try","catch","finally","throw","async",
            "await","of","in","delete","void","yield","static","super","from","as"
        ]
        let types: Set<String> = [
            "String","Number","Boolean","Array","Object","Promise","Map","Set","Date","Error",
            "console","Math","JSON","interface","type","enum","readonly","abstract"
        ]
        return tokenize(line, font: font, keywords: keywords, types: types,
                        commentPrefix: "//", stringDelimiters: ["\"","'","`"], attrPrefix: nil, hashPrefix: nil)
    }

    private static func highlightBash(_ line: String, font: NSFont) -> NSAttributedString {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            return NSAttributedString(string: line, attributes: attr(colorComment, font))
        }
        let keywords: Set<String> = [
            "if","then","else","elif","fi","for","do","done","while","until","case","esac",
            "function","return","exit","echo","read","export","local","source","alias","unset","set","true","false"
        ]
        return tokenize(line, font: font, keywords: keywords, types: [],
                        commentPrefix: "#", stringDelimiters: ["\"","'"], attrPrefix: nil, hashPrefix: nil)
    }

    private static func highlightJSON(_ line: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                var j = line.index(after: i)
                while j < line.endIndex && line[j] != "\"" {
                    if line[j] == "\\" {
                        j = line.index(after: j)
                        guard j < line.endIndex else { break }
                    }
                    j = line.index(after: j)
                }
                if j < line.endIndex { j = line.index(after: j) }
                let str = String(line[i..<j])
                let afterJ = j < line.endIndex ? line[j...].trimmingCharacters(in: .whitespaces) : ""
                let color = afterJ.hasPrefix(":") ? colorVariable : colorString
                result.append(NSAttributedString(string: str, attributes: attr(color, font)))
                i = j
            } else if ch.isNumber || (ch == "-" && line.index(after: i) < line.endIndex && line[line.index(after: i)].isNumber) {
                var j = ch == "-" ? line.index(after: i) : i
                while j < line.endIndex && (line[j].isNumber || line[j] == "." || line[j] == "e" || line[j] == "E") {
                    j = line.index(after: j)
                }
                result.append(NSAttributedString(string: String(line[i..<j]), attributes: attr(colorNumber, font)))
                i = j
            } else if line[i...].hasPrefix("true") || line[i...].hasPrefix("false") || line[i...].hasPrefix("null") {
                let kw = line[i...].hasPrefix("true") ? "true" : line[i...].hasPrefix("false") ? "false" : "null"
                result.append(NSAttributedString(string: kw, attributes: attr(colorKeyword, font)))
                i = line.index(i, offsetBy: kw.count, limitedBy: line.endIndex) ?? line.endIndex
            } else {
                result.append(NSAttributedString(string: String(ch), attributes: attr(colorText, font)))
                i = line.index(after: i)
            }
        }
        return result
    }

    private static func highlightHTML(_ line: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var i = line.startIndex
        while i < line.endIndex {
            if line[i...].hasPrefix("<!--") {
                let end = line.range(of: "-->", range: i..<line.endIndex)?.upperBound ?? line.endIndex
                result.append(NSAttributedString(string: String(line[i..<end]), attributes: attr(colorComment, font)))
                i = end
            } else if line[i] == "<" {
                var j = line.index(after: i)
                while j < line.endIndex && line[j] != ">" { j = line.index(after: j) }
                if j < line.endIndex { j = line.index(after: j) }
                result.append(NSAttributedString(string: String(line[i..<j]), attributes: attr(colorType, font)))
                i = j
            } else if line[i] == "\"" {
                var j = line.index(after: i)
                while j < line.endIndex && line[j] != "\"" { j = line.index(after: j) }
                if j < line.endIndex { j = line.index(after: j) }
                result.append(NSAttributedString(string: String(line[i..<j]), attributes: attr(colorString, font)))
                i = j
            } else {
                result.append(NSAttributedString(string: String(line[i]), attributes: attr(colorText, font)))
                i = line.index(after: i)
            }
        }
        return result
    }

    private static func highlightCSS(_ line: String, font: NSFont) -> NSAttributedString {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("/*") ||
           line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            return NSAttributedString(string: line, attributes: attr(colorComment, font))
        }
        let properties: Set<String> = [
            "color","background","background-color","font-size","font-weight","font-family",
            "margin","padding","border","display","flex","width","height","position",
            "top","left","right","bottom","opacity","transform","transition","animation","z-index"
        ]
        return tokenize(line, font: font, keywords: properties, types: [],
                        commentPrefix: "/*", stringDelimiters: ["\"","'"], attrPrefix: nil, hashPrefix: "#")
    }

    private static func highlightSQL(_ line: String, font: NSFont) -> NSAttributedString {
        let keywords: Set<String> = [
            "SELECT","FROM","WHERE","INSERT","UPDATE","DELETE","CREATE","DROP","TABLE","INDEX",
            "VIEW","JOIN","LEFT","RIGHT","INNER","OUTER","ON","AS","AND","OR","NOT","IN","LIKE",
            "BETWEEN","IS","NULL","ORDER","BY","GROUP","HAVING","LIMIT","OFFSET","DISTINCT",
            "UNION","WITH","SET","VALUES","INTO","select","from","where","create","delete"
        ]
        return tokenize(line, font: font, keywords: keywords, types: [],
                        commentPrefix: "--", stringDelimiters: ["'","\""], attrPrefix: nil, hashPrefix: nil)
    }

    private static func highlightRust(_ line: String, font: NSFont) -> NSAttributedString {
        let keywords: Set<String> = [
            "let","mut","fn","pub","use","mod","struct","enum","impl","trait","type","const",
            "static","return","if","else","match","for","while","loop","break","continue","move",
            "async","await","unsafe","extern","crate","super","self","Self","true","false","where","ref","dyn","in","as"
        ]
        let types: Set<String> = [
            "String","str","i32","i64","u32","u64","f32","f64","bool","Vec","HashMap",
            "Option","Result","Some","None","Ok","Err","Box","Rc","Arc","Mutex","usize","isize"
        ]
        return tokenize(line, font: font, keywords: keywords, types: types,
                        commentPrefix: "//", stringDelimiters: ["\""], attrPrefix: nil, hashPrefix: nil)
    }

    // MARK: - Tokenizer (crash fix: guards on all index advances)

    private static func tokenize(
        _ line: String,
        font: NSFont,
        keywords: Set<String>,
        types: Set<String>,
        commentPrefix: String,
        stringDelimiters: [String],
        attrPrefix: String?,
        hashPrefix: String?
    ) -> NSAttributedString {
        if !commentPrefix.isEmpty && line.trimmingCharacters(in: .whitespaces).hasPrefix(commentPrefix) {
            return NSAttributedString(string: line, attributes: attr(colorComment, font))
        }

        let result = NSMutableAttributedString()
        var i = line.startIndex

        while i < line.endIndex {
            // Inline comment check
            if !commentPrefix.isEmpty && line[i...].hasPrefix(commentPrefix) {
                result.append(NSAttributedString(string: String(line[i...]), attributes: attr(colorComment, font)))
                break
            }

            // String delimiters
            var foundString = false
            for delim in stringDelimiters {
                guard line[i...].hasPrefix(delim) else { continue }
                guard let delimStart = line.index(i, offsetBy: delim.count, limitedBy: line.endIndex) else {
                    // delim longer than remaining — just emit char and move on
                    break
                }
                var j = delimStart
                while j < line.endIndex {
                    if line[j...].hasPrefix(delim) {
                        j = line.index(j, offsetBy: delim.count, limitedBy: line.endIndex) ?? line.endIndex
                        break
                    }
                    if line[j] == "\\" {
                        let next = line.index(after: j)
                        guard next < line.endIndex else { j = next; break }
                        j = line.index(after: next)
                    } else {
                        j = line.index(after: j)
                    }
                }
                result.append(NSAttributedString(string: String(line[i..<j]), attributes: attr(colorString, font)))
                i = j
                foundString = true
                break
            }
            if foundString { continue }

            // Attribute prefix (@)
            if let prefix = attrPrefix, line[i...].hasPrefix(prefix) {
                var j = line.index(after: i)
                while j < line.endIndex && (line[j].isLetter || line[j].isNumber || line[j] == "_") {
                    j = line.index(after: j)
                }
                result.append(NSAttributedString(string: String(line[i..<j]), attributes: attr(colorAttribute, font)))
                i = j
                continue
            }

            // Hash prefix (#)
            if let prefix = hashPrefix, prefix == "#", line[i...].hasPrefix(prefix) {
                var j = line.index(after: i)
                while j < line.endIndex && (line[j].isLetter || line[j].isNumber || line[j] == "_") {
                    j = line.index(after: j)
                }
                let word = String(line[i..<j])
                result.append(NSAttributedString(string: word,
                    attributes: attr(word.count > 1 ? colorKeyword : colorText, font)))
                i = j
                continue
            }

            // Numbers
            if line[i].isNumber || (line[i] == "-" && {
                let next = line.index(after: i)
                return next < line.endIndex && line[next].isNumber
            }()) {
                var j = line[i] == "-" ? line.index(after: i) : i
                while j < line.endIndex && (line[j].isNumber || line[j] == "." || line[j] == "_" ||
                      line[j] == "x" || line[j] == "X" || line[j] == "b" || line[j] == "o" ||
                      (line[j] >= "a" && line[j] <= "f") || (line[j] >= "A" && line[j] <= "F")) {
                    j = line.index(after: j)
                }
                result.append(NSAttributedString(string: String(line[i..<j]), attributes: attr(colorNumber, font)))
                i = j
                continue
            }

            // Identifiers / keywords
            if line[i].isLetter || line[i] == "_" {
                var j = line.index(after: i)
                while j < line.endIndex && (line[j].isLetter || line[j].isNumber || line[j] == "_") {
                    j = line.index(after: j)
                }
                let word = String(line[i..<j])
                let isFunc = j < line.endIndex && line[j] == "("
                let color: NSColor
                if keywords.contains(word)             { color = colorKeyword }
                else if types.contains(word)           { color = colorType }
                else if isFunc                         { color = colorFunction }
                else if word.first?.isUppercase == true { color = colorType }
                else                                   { color = colorText }
                result.append(NSAttributedString(string: word,
                    attributes: attr(color, font, bold: keywords.contains(word))))
                i = j
                continue
            }

            // Any other character
            result.append(NSAttributedString(string: String(line[i]), attributes: attr(colorText, font)))
            i = line.index(after: i)
        }
        return result
    }
}

// MARK: - Diff

struct DiffLine {
    let text: String
    let type: DiffLineType
}

enum DiffLineType { case added, removed, context, hunk, fileHeader }

struct DiffLineView: View {
    let line: DiffLine
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(gutterColor).frame(width: 3)
            Text(indicator)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(textColor).frame(width: 16, alignment: .center).padding(.vertical, 2)
            Text(lineContent)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2).padding(.trailing, 12)
        }
        .background(backgroundColor)
    }
    private var lineContent: String {
        switch line.type { case .added, .removed: return String(line.text.dropFirst()); default: return line.text }
    }
    private var indicator: String {
        switch line.type { case .added: return "+"; case .removed: return "−"; case .hunk: return "⋯"; case .fileHeader: return ""; case .context: return " " }
    }
    private var backgroundColor: Color {
        switch line.type { case .added: return .green.opacity(0.10); case .removed: return .red.opacity(0.10); case .hunk: return .accentColor.opacity(0.08); case .fileHeader: return Color.primary.opacity(0.06); case .context: return .clear }
    }
    private var gutterColor: Color {
        switch line.type { case .added: return .green; case .removed: return .red; case .hunk: return .accentColor; case .fileHeader: return Color.primary.opacity(0.3); case .context: return .clear }
    }
    private var textColor: Color {
        switch line.type { case .added: return .green.opacity(0.9); case .removed: return .red.opacity(0.9); case .hunk: return .accentColor; case .fileHeader: return .secondary; case .context: return .primary }
    }
}

// MARK: - Streaming Cursor

struct StreamingCursorView: View {
    @State private var visible = true
    var body: some View {
        Text("▋").foregroundColor(.accentColor).opacity(visible ? 1 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever()) { visible.toggle() } }
    }
}
