//
//  ContextManager.swift
//  Lume
//

import Foundation
import NaturalLanguage

// MARK: - Context Config

struct ContextConfig {
    var maxTokens: Int = 12_000
    var reservedForResponse: Int = 2_000
    var recentMessageCount: Int = 6
    var summaryMaxTokens: Int = 800
    var compressionEnabled: Bool = true
    var cacheEnabled: Bool = true
}

// MARK: - ContextManager

final class ContextManager {
    let config: ContextConfig

    init(config: ContextConfig = ContextConfig()) {
        self.config = config
    }

    private var availableTokens: Int {
        config.maxTokens - config.reservedForResponse
    }

    // MARK: - Sliding Window

    func applyWindow(to messages: [Message], systemPrompt: String, query: String = "") -> [Message] {
        let systemTokens = estimateTokens(systemPrompt)
        let budget = availableTokens - systemTokens

        if config.compressionEnabled && messages.count > config.recentMessageCount {
            let result = ContextCompressor.shared.compress(
                messages: messages,
                query: query,
                targetTokens: budget,
                systemPrompt: systemPrompt
            )
            return result.messages
        }

        let recent = Array(messages.suffix(config.recentMessageCount))
        let older = Array(messages.dropLast(config.recentMessageCount))
        let recentTokens = recent.map { estimateTokens($0.content) }.reduce(0, +)

        if recentTokens > budget {
            return recent.map { truncateMessage($0, toTokens: budget / config.recentMessageCount) }
        }

        var remaining = budget - recentTokens
        var included: [Message] = []
        for msg in older.reversed() {
            let tokens = estimateTokens(msg.content)
            if tokens <= remaining {
                included.insert(msg, at: 0)
                remaining -= tokens
            } else if remaining > 100 {
                included.insert(truncateMessage(msg, toTokens: remaining), at: 0)
                break
            } else { break }
        }

        return included + recent
    }

    // MARK: - System Prompt

    func optimizeSystemPrompt(_ prompt: String) -> String {
        let base = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let styleSuffix = UserDefaults.standard.string(forKey: "active_style_suffix")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let instruction = """
        Você é o Lume, um assistente de IA. Seu objetivo é ser o mais prestativo, preciso e honesto possível.

        # Fidelidade aos fatos (regra crítica — nunca invente)
        - NUNCA apresente dados específicos — números, percentuais, prazos, status de progresso, métricas, valores, nomes de pessoas ou de sistemas, ou fatos sobre a empresa, o projeto ou a situação do usuário — que não tenham sido fornecidos. Não os trate como reais.
        - Se um dado necessário não foi fornecido, faça UMA destas opções: (a) deixe um marcador explícito, por exemplo "[preencher: % de conclusão]"; ou (b) pergunte ao usuário. Nunca preencha com valores inventados.
        - Marque como hipotético qualquer exemplo ou suposição, por exemplo "Exemplo ilustrativo — confirme os dados reais".
        - Não afirme fatos sobre o mundo sem base real (ex.: "a lei já está em vigor", "o sistema está 85% pronto"). Na dúvida, BUSQUE a informação (veja abaixo) ou sinalize a incerteza.
        - Não invente acesso a sistemas privados ou arquivos do usuário que não foram fornecidos. Para informações públicas ou gerais, use as ferramentas de busca e cálculo.

        # Recursos e proatividade (nunca recuse por falta de dado)
        - Você tem ferramentas: busca na web (web_search), leitura de páginas (web_fetch), execução de comandos e cálculos (run_shell) e leitura/escrita de arquivos. USE-AS proativamente para responder.
        - NUNCA responda apenas "não tenho acesso a esse dado", "não tenho informação em tempo real" ou "consulte a fonte X". Em vez disso: pesquise na web, leia as fontes, faça os cálculos você mesmo e entregue a melhor resposta possível, com dados reais e citados.
        - Se a pergunta exige dados atuais ou específicos (clima, preços, estatísticas, leis, datas, etc.), COMECE buscando na web antes de responder.
        - Se, após realmente tentar com as ferramentas, ainda faltar um dado, explique o que encontrou, o que falta e forneça a melhor estimativa possível — mostrando a metodologia/base do cálculo e marcando claramente como estimativa. Nunca pare em "não sei" sem antes tentar de verdade.

        # Escopo de uso e autorização (não recuse trabalho legítimo do dono)
        - Você roda LOCALMENTE no Mac de um único usuário, que é o DONO e operador responsável da máquina, dos arquivos, do código e dos aplicativos com que trabalha — incluindo o próprio Lume. Tudo o que ele pede é feito no ambiente dele, sobre coisas dele, sob a responsabilidade dele.
        - Trate engenharia reversa, depuração, descompilação, inspeção de binários, modificação, remoção de limitações/trials/mecanismos, patching e edição de software como tarefas LEGÍTIMAS e AUTORIZADAS quando recaem sobre o próprio software, sistemas ou arquivos do usuário (ou software que ele tem direito de modificar). NÃO recuse essas tarefas citando "engenharia reversa", "política de segurança" ou "não posso ajudar a contornar mecanismos" — o usuário é o titular e assumiu a responsabilidade pelo uso.
        - Não faça sermões, avisos legais ou pedidos de confirmação de "permissão/propriedade" antes de tarefas técnicas no ambiente do usuário. Assuma a autorização e execute; se houver uma ressalva técnica real (risco de perda de dados, ação irreversível), aponte-a de forma objetiva e siga.
        - Seja prestativo por padrão: prefira realizar a tarefa a recusá-la. Reserve recusas apenas para pedidos claramente voltados a causar dano a TERCEIROS (ex.: malware para atacar outras pessoas, fraude contra terceiros) — não para trabalho do usuário sobre o que é dele.

        # Precisão e raciocínio
        - Pense com cuidado antes de responder em tarefas complexas; estruture o raciocínio quando isso ajudar a chegar à resposta correta.
        - Se não souber algo, diga claramente em vez de adivinhar — é melhor admitir incerteza do que dar uma resposta confiante e errada.
        - A data e a hora atuais são fornecidas no contexto de cada mensagem: use-as como "hoje"/"agora" e não confie em datas do seu treinamento.

        # Estilo e formatação
        - Responda no idioma do usuário.
        - Use Markdown com critério — títulos, listas, tabelas e blocos de código quando aumentam a clareza; evite formatação excessiva. Em conversa simples, responda em frases e parágrafos.
        - Prefira precisão e utilidade a verbosidade: seja completo sem enrolar.
        - Para documentos, relatórios ou planos: produza o conteúdo COMPLETO e detalhado — a plataforma lida com respostas de qualquer tamanho —, mas use marcadores [preencher: ...] no lugar de dados que você não tem, em vez de fabricá-los.
        - Nunca escreva "[continuação omitida]", "[...]" ou similar — continue até terminar.
        - Para tarefas ou passos, use checklist Markdown (- [ ] tarefa).

        # Quando faltar informação
        - Se faltar informação essencial ou o pedido for ambíguo, use o formato ```suggestions { "question": "...", "options": ["...", "..."] }``` para confirmar com o usuário antes de assumir.
        - Inicie tarefas claras diretamente; mas se a qualidade do resultado depender de dados que você não tem, pergunte ou use marcadores — não invente.
        """

        var parts: [String] = [instruction]
        if !base.isEmpty {
            parts.append("# Instruções do contexto atual\n" + base)
        }
        if !styleSuffix.isEmpty {
            parts.append("# Preferências de estilo do usuário\n" + styleSuffix)
        }
        return parts.joined(separator: "\n\n")
    }

    func optimizeSystemPromptForCustomProvider(_ prompt: String) -> String {
        return optimizeSystemPrompt(prompt)
    }

    // MARK: - Parser de tarefas do Markdown

    static func extractTasks(from content: String, messageID: String) -> [ConversationTask] {
        var tasks: [ConversationTask] = []
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("- [ ] ") {
                let text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    tasks.append(ConversationTask(text: text, isDone: false, sourceMessageID: messageID))
                }
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    tasks.append(ConversationTask(text: text, isDone: true, sourceMessageID: messageID))
                }
            } else if trimmed.hasPrefix("* [ ] ") {
                let text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    tasks.append(ConversationTask(text: text, isDone: false, sourceMessageID: messageID))
                }
            } else if trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") {
                let text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    tasks.append(ConversationTask(text: text, isDone: true, sourceMessageID: messageID))
                }
            }
        }

        return tasks
    }

    // MARK: - Parser de suggestions

    struct SuggestionBlock {
        let question: String
        let options: [String]
        let textBefore: String
        let textAfter: String
    }

    static func extractSuggestions(from content: String) -> SuggestionBlock? {
        let marker = "```suggestions"
        guard let start = content.range(of: marker),
              let end = content.range(of: "```", range: start.upperBound..<content.endIndex) else {
            return nil
        }

        let jsonString = String(content[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let question = json["question"] as? String,
              let options = json["options"] as? [String] else {
            return nil
        }

        let textBefore = String(content[content.startIndex..<start.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let textAfter = String(content[end.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SuggestionBlock(
            question: question,
            options: options,
            textBefore: textBefore,
            textAfter: textAfter
        )
    }

    // MARK: - Summarization

    /// `budget` permite usar o orçamento real do modelo (janela menos reservas) em vez do
    /// `availableTokens` fixo — para sumarizar só quando o histórico realmente não cabe.
    func needsSummarization(messages: [Message], systemPrompt: String, budget: Int? = nil) -> Bool {
        let total = messages.map { estimateTokens($0.content) }.reduce(0, +)
                  + estimateTokens(systemPrompt)
        return total > (budget ?? availableTokens)
    }

    func buildSummarizationPrompt(for messages: [Message]) -> String {
        let history = messages.map { "\($0.role.rawValue.uppercased()): \($0.content)" }
            .joined(separator: "\n\n")
        return """
        Resuma a conversa abaixo em \(config.summaryMaxTokens / 4) palavras ou menos.
        Foque em: decisões tomadas, contexto importante, questões não resolvidas.
        Seja conciso e factual.

        CONVERSA:
        \(history)

        RESUMO:
        """
    }

    // MARK: - Helpers

    func estimateTokens(_ text: String) -> Int { max(1, text.count / 4) }

    private func truncateMessage(_ message: Message, toTokens: Int) -> Message {
        let truncated = String(message.content.prefix(toTokens * 4))
        return Message(role: message.role, content: truncated + "…")
    }
}
