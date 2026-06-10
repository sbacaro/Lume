//
//  VoiceDictationManager.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import Speech
import AVFoundation
import Observation

@Observable
final class VoiceDictationManager {

    // MARK: - Public state

    var transcript: String = ""
    var isRecording: Bool = false
    var permissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    var error: String? = nil

    // MARK: - Private

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
        permissionStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Public API

    func toggleRecording() async {
        if isRecording {
            stopRecording()
        } else {
            await startRecording()
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        // Microfone
        let micGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else {
            await MainActor.run {
                error = "Permissão de microfone negada. Habilite em Preferências do Sistema → Segurança → Privacidade."
            }
            return false
        }

        // Speech Recognition
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        await MainActor.run {
            permissionStatus = SFSpeechRecognizer.authorizationStatus()
            if !speechGranted {
                error = "Permissão de reconhecimento de fala negada. Habilite em Preferências do Sistema → Segurança → Privacidade."
            }
        }

        return speechGranted
    }

    // MARK: - Start Recording

    private func startRecording() async {
        error = nil
        transcript = ""

        // Verifica permissões
        guard await requestPermission() else { return }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            error = "Reconhecimento de fala não disponível no momento."
            return
        }

        do {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = false
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            await MainActor.run { isRecording = true }

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, err in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        self.transcript = text
                    }
                    if result.isFinal {
                        DispatchQueue.main.async { self.stopRecording() }
                    }
                }

                if let err {
                    // Ignora erro de cancelamento (normal ao parar)
                    let nsError = err as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 1110 {
                        DispatchQueue.main.async {
                            self.error = err.localizedDescription
                            self.stopRecording()
                        }
                    }
                }
            }

            // Para automaticamente após 60 segundos de silêncio
            Task {
                try? await Task.sleep(for: .seconds(60))
                if self.isRecording { self.stopRecording() }
            }

        } catch {
            await MainActor.run {
                self.error = "Erro ao iniciar gravação: \(error.localizedDescription)"
                isRecording = false
            }
        }
    }
}
