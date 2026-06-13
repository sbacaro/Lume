//
//  SpeechManager.swift
//  Lume
//
//  Leitura em voz alta das respostas (TTS) via AVSpeechSynthesizer — nativo,
//  offline e sem custo. Não requer Developer ID.
//

import Foundation
import AVFoundation
import Observation

@Observable
final class SpeechManager {
    static let shared = SpeechManager()

    /// ID da mensagem sendo lida no momento (nil quando em silêncio).
    var speakingID: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var delegateProxy: SpeechDelegateProxy!

    init() {
        delegateProxy = SpeechDelegateProxy { [weak self] in
            Task { @MainActor in self?.speakingID = nil }
        }
        synthesizer.delegate = delegateProxy
    }

    /// Alterna entre ler e parar uma mensagem específica.
    func toggle(id: String, text: String, language: String = "pt-BR") {
        if speakingID == id {
            stop()
            return
        }
        stop()
        let clean = Self.cleanForSpeech(text)
        guard !clean.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        speakingID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakingID = nil
    }

    // MARK: - Limpeza de Markdown para fala

    /// Remove marcações que não soam bem quando lidas (code fences, símbolos, links).
    static func cleanForSpeech(_ text: String) -> String {
        var t = text

        func replace(_ pattern: String, with template: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            let range = NSRange(t.startIndex..., in: t)
            t = regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: template)
        }

        replace("```[\\s\\S]*?```", with: " (bloco de código) ")  // blocos cercados
        replace("\\[IMAGE:[^\\]]*\\]", with: "")                   // blobs de imagem
        t = t.replacingOccurrences(of: "<think>", with: " ")
            .replacingOccurrences(of: "</think>", with: " ")
        replace("\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1")          // links markdown → texto

        // Remove caracteres de marcação inline.
        let strip: Set<Character> = ["#", "*", "_", "`", ">", "|"]
        t = String(t.map { strip.contains($0) ? " " : $0 })

        replace("[ \\t]{2,}", with: " ")                           // colapsa espaços

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Delegate Proxy (isola o NSObject do tipo @Observable)

private final class SpeechDelegateProxy: NSObject, AVSpeechSynthesizerDelegate {
    let onEnd: () -> Void
    init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onEnd()
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onEnd()
    }
}
