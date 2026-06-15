//
//  SSEParser.swift
//  Lume
//
//  Server-Sent Events parser para streaming de tokens de LLMs.
//  Suporta OpenAI, Anthropic, vLLM, TGI e qualquer provider compatível.
//

import Foundation

// MARK: - SSE Event

struct SSEEvent {
    let id: String?
    let event: String?
    let data: String
    let retry: Int?
}

// MARK: - SSE Parser

final class SSEParser: NSObject, URLSessionDataDelegate {

    // Callbacks
    var onEvent: ((SSEEvent) -> Void)?
    var onError: ((Error) -> Void)?
    var onComplete: (() -> Void)?

    private var buffer = ""
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation?

    deinit {
        cancel()
    }

    // MARK: - Async Stream API

    func stream(request: URLRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.dataTask(with: request)
            self.task = task
            task.resume()

            continuation.onTermination = { [weak self] _ in
                self?.task?.cancel()
                self?.session?.invalidateAndCancel()
            }
        }
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.finish()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text
        parseBuffer()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            // Ignora cancelamento como erro
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                continuation?.finish()
            } else {
                continuation?.finish(throwing: error)
            }
        } else {
            continuation?.finish()
        }
        onComplete?()
    }

    // MARK: - Buffer Parsing

    private func parseBuffer() {
        // SSE usa \n\n para separar eventos
        while let range = buffer.range(of: "\n\n") {
            let eventText = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])

            if let event = parseEvent(eventText) {
                continuation?.yield(event)
                onEvent?(event)
            }
        }
    }

    private func parseEvent(_ text: String) -> SSEEvent? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        var id: String?
        var event: String?
        var dataLines: [String] = []
        var retry: Int?

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("id:") {
                id = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("event:") {
                event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("retry:") {
                retry = Int(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix(":") {
                // Comentário SSE — ignora
                continue
            }
        }

        let data = dataLines.joined(separator: "\n")
        guard !data.isEmpty else { return nil }
        return SSEEvent(id: id, event: event, data: data, retry: retry)
    }
}
