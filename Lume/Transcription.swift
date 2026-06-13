//
//  Transcription.swift
//  Lume
//
//  Abstração de transcrição de áudio. Hoje o ditado usa SFSpeechRecognizer
//  (em VoiceDictationManager). Este protocolo prepara o terreno para um motor
//  local melhor (Whisper), sem acoplar o resto do app a uma implementação.
//
//  ── Como habilitar o Whisper (precisa ser feito no Xcode) ──
//  1. File → Add Package Dependencies… → https://github.com/argmaxinc/WhisperKit
//  2. Adicione o produto "WhisperKit" ao target Lume.
//  3. O bloco `#if canImport(WhisperKit)` abaixo passa a compilar e o
//     WhisperTranscriptionProvider fica disponível. Confira a API do WhisperKit
//     na versão instalada (os nomes podem variar entre releases).
//  4. Para ditar em tempo real, grave o áudio do microfone (AVAudioEngine) em um
//     arquivo .wav/.m4a e chame `transcribe(audioFileURL:)`.
//
//  Observação: WhisperKit baixa o modelo on-device no primeiro uso. Tudo roda
//  localmente, sem custo e sem necessidade de Developer ID.
//

import Foundation

#if canImport(WhisperKit)
import WhisperKit
#endif

/// Transcreve um arquivo de áudio em texto.
protocol TranscriptionProvider {
    func transcribe(audioFileURL: URL) async throws -> String
}

enum TranscriptionError: Error {
    case engineUnavailable
}

/// Indica se um motor de transcrição local (Whisper) está disponível neste build.
enum Transcription {
    static var whisperAvailable: Bool {
        #if canImport(WhisperKit)
        return true
        #else
        return false
        #endif
    }
}

#if canImport(WhisperKit)
/// Transcrição local via WhisperKit (on-device). Disponível apenas quando o
/// pacote WhisperKit está adicionado ao projeto.
final class WhisperTranscriptionProvider: TranscriptionProvider {
    private var pipe: WhisperKit?

    func transcribe(audioFileURL: URL) async throws -> String {
        if pipe == nil {
            pipe = try await WhisperKit()
        }
        guard let pipe else { throw TranscriptionError.engineUnavailable }
        let results = try await pipe.transcribe(audioPath: audioFileURL.path)
        return results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
