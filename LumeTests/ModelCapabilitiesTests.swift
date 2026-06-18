//
//  ModelCapabilitiesTests.swift
//  LumeTests
//
//  Cobre a detecção de suporte a visão (multimodal).
//

import Testing
@testable import Lume

struct ModelCapabilitiesTests {

    @Test(arguments: [
        "gpt-4o", "gpt-4-turbo", "claude-opus-4-8", "claude-sonnet-4-6",
        "gemini-2.5-pro", "pixtral-12b", "qwen2.5-vl", "llama-3.2-90b",
    ])
    func supportsVisionForVisionModels(model: String) {
        #expect(ModelCapabilities.supportsVision(model))
    }

    @Test(arguments: [
        "gpt-3.5-turbo", "o1-mini", "o3-mini", "text-embedding-3-large",
        "whisper-1", "deepseek-coder", "codestral",
    ])
    func noVisionForKnownTextModels(model: String) {
        #expect(ModelCapabilities.supportsVision(model) == false)
    }

    @Test func unknownModelDefaultsToNoVision() {
        #expect(ModelCapabilities.supportsVision("some-random-model-2030") == false)
    }

    @Test func noVisionListTakesPriority() {
        // "deepseek-coder" contém "deepseek" mas está na lista sem visão.
        #expect(ModelCapabilities.supportsVision("deepseek-coder-v2") == false)
    }
}
