//
//  ModelCapabilities.swift
//  Lume
//
//  Detecção de capacidades do modelo. Hoje: suporte a visão (imagens nativas).
//  Modelos com visão recebem a imagem em base64; modelos sem visão recebem uma
//  descrição local (OCR + classificação) gerada pelo framework Vision.
//

import Foundation

enum ModelCapabilities {

    /// Indica se o modelo aceita imagens nativamente (multimodal/visão).
    static func supportsVision(_ model: String) -> Bool {
        let m = model.lowercased()

        // Conhecidos SEM visão (têm prioridade sobre a lista de visão).
        let noVision = [
            "gpt-3.5", "o1-mini", "o3-mini", "text-embedding", "embed", "whisper", "tts",
            "glm-3", "glm-4-flash", "glm-4-air", "deepseek-coder", "codestral"
        ]
        if noVision.contains(where: { m.contains($0) }) { return false }

        // Conhecidos COM visão.
        let vision = [
            "gpt-4o", "gpt-4-turbo", "gpt-4.1", "gpt-4-vision", "gpt-5", "chatgpt-4o",
            "o1", "o3", "o4",
            "claude",                       // Claude 3+ (opus/sonnet/haiku) têm visão
            "gemini",
            "llava", "moondream", "pixtral",
            "qwen-vl", "qwen2-vl", "qwen2.5-vl",
            "llama-3.2", "llama-4",         // variantes com visão
            "minicpm-v", "internvl",
            "glm-4v", "glm-4.5v",           // variantes de visão do GLM
            "vision", "-vl"
        ]
        if vision.contains(where: { m.contains($0) }) { return true }

        // Desconhecido: assume SEM visão (mais seguro — usa descrição local em vez de
        // enviar um blob base64 inútil). Adicione o modelo à lista acima se ele tiver visão.
        return false
    }
}
