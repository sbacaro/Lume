//
//  LLMRouterTests.swift
//  LumeTests
//
//  Cobre o roteador de modelos: heurísticas puras e decisões de rota.
//

import Testing
@testable import Lume

@MainActor
struct LLMRouterTests {

    // MARK: - estimateTokens

    @Test func estimateTokensIsAtLeastOne() {
        #expect(LLMRouter.estimateTokens("") == 1)
        #expect(LLMRouter.estimateTokens("a") == 1)
    }

    @Test func estimateTokensApproximatesFourCharsPerToken() {
        // 40 chars / 4 = 10
        let text = String(repeating: "x", count: 40)
        #expect(LLMRouter.estimateTokens(text) == 10)
    }

    // MARK: - bareModelName

    @Test func bareModelNameStripsProviderPrefix() {
        #expect(LLMRouter.bareModelName("anthropic/claude-opus-4-8") == "claude-opus-4-8")
        #expect(LLMRouter.bareModelName("vertex_ai/gemini-2.5-flash") == "gemini-2.5-flash")
    }

    @Test func bareModelNameKeepsBareNames() {
        #expect(LLMRouter.bareModelName("claude-opus-4-8") == "claude-opus-4-8")
    }

    @Test func bareModelNameFallsBackOnTrailingSlash() {
        // Sem nome após a barra → retorna original
        #expect(LLMRouter.bareModelName("anthropic/") == "anthropic/")
    }

    // MARK: - inferProvider

    @Test(arguments: [
        ("anthropic/claude-opus-4-8", "anthropic"),
        ("openai/gpt-4o", "openai"),
        ("vertex_ai/gemini-2.5-flash", "google"),
        ("gpt-4o", "openai"),
        ("claude-haiku-4-5-20251001", "anthropic"),
        ("gemini-2.5-pro", "google"),
        ("mistral-large", "mistral"),
        ("deepseek-chat", "deepseek"),
        ("something-weird", "unknown"),
    ])
    func inferProviderDetectsFamily(model: String, expected: String) {
        #expect(LLMRouter.inferProvider(from: model) == expected)
    }

    // MARK: - costTier

    @Test func costTierClassifiesCheapModels() {
        #expect(LLMRouter.costTier(for: "gpt-4o-mini") == .cheap)
        #expect(LLMRouter.costTier(for: "claude-haiku-4-5-20251001") == .cheap)
        #expect(LLMRouter.costTier(for: "gemini-2.5-flash") == .cheap)
    }

    @Test func costTierClassifiesExpensiveModels() {
        #expect(LLMRouter.costTier(for: "claude-opus-4-8") == .expensive)
        #expect(LLMRouter.costTier(for: "gpt-4o") == .expensive)
        #expect(LLMRouter.costTier(for: "claude-sonnet-4-6") == .expensive)
    }

    @Test func costTierDefaultsToMedium() {
        #expect(LLMRouter.costTier(for: "totally-unknown-model") == .medium)
    }

    // MARK: - maxContextWindow

    @Test func maxContextWindowKnownModels() {
        #expect(LLMRouter.maxContextWindow(for: "gpt-4o") == 128_000)
        #expect(LLMRouter.maxContextWindow(for: "claude-opus-4-8") == 200_000)
        #expect(LLMRouter.maxContextWindow(for: "gpt-3.5-turbo") == 16_385)
    }

    @Test func maxContextWindowStripsPrefixBeforeLookup() {
        #expect(LLMRouter.maxContextWindow(for: "anthropic/claude-opus-4-8") == 200_000)
    }

    @Test func maxContextWindowInfersForUnknown() {
        #expect(LLMRouter.maxContextWindow(for: "gemini-9-ultra") == 200_000)
        #expect(LLMRouter.maxContextWindow(for: "gpt-4-something") == 128_000)
        #expect(LLMRouter.maxContextWindow(for: "obscure-model") == 32_000)
    }

    // MARK: - multimodalModel

    @Test func multimodalModelPerProvider() {
        #expect(LLMRouter.multimodalModel(for: "openai") == "gpt-4o")
        #expect(LLMRouter.multimodalModel(for: "anthropic") == "claude-opus-4-8")
        #expect(LLMRouter.multimodalModel(for: "google") == "vertex_ai/gemini-2.5-flash")
        #expect(LLMRouter.multimodalModel(for: "unknown") == nil)
    }

    // MARK: - isCodeRelated / containsMath

    @Test func isCodeRelatedDetectsCodeSignals() {
        #expect(LLMRouter.isCodeRelated("```swift\nlet x = 1\n```"))
        #expect(LLMRouter.isCodeRelated("escreva uma função em python"))
        #expect(LLMRouter.isCodeRelated("olá, tudo bem?") == false)
    }

    @Test func containsMathDetectsMathSignals() {
        #expect(LLMRouter.containsMath("calcule a derivada"))
        #expect(LLMRouter.containsMath("resolva a equação"))
        #expect(LLMRouter.containsMath("conte uma piada") == false)
    }

    // MARK: - analyzeComplexity

    @Test func analyzeComplexityLowForGreeting() {
        let result = LLMRouter.analyzeComplexity(prompt: "oi", history: [])
        #expect(result == .low)
    }

    @Test func analyzeComplexityHighForLongAnalyticalPrompt() {
        let prompt = "Analise em detalhes e compare passo a passo a arquitetura "
            + String(repeating: "palavra ", count: 110)
        let result = LLMRouter.analyzeComplexity(prompt: prompt, history: [])
        #expect(result == .high)
    }

    // MARK: - route

    @Test func routePreferredModeAlwaysKeepsModel() {
        let decision = LLMRouter.route(
            prompt: "qualquer coisa",
            history: [],
            provider: "anthropic",
            preferredModel: "claude-sonnet-4-6",
            forceMode: .preferred
        )
        #expect(decision.model == "claude-sonnet-4-6")
        #expect(decision.reason == .preferredModel)
        #expect(decision.confidence == 1.0)
    }

    @Test func routeWithImagesPicksMultimodal() {
        let decision = LLMRouter.route(
            prompt: "o que tem nesta imagem?",
            history: [],
            provider: "openai",
            preferredModel: "gpt-4o-mini",
            hasImages: true
        )
        #expect(decision.reason == .multimodal)
        #expect(decision.model == "gpt-4o")
    }

    @Test func routeCheapModeUsesCheapModel() {
        let decision = LLMRouter.route(
            prompt: "oi",
            history: [],
            provider: "anthropic",
            preferredModel: "claude-opus-4-8",
            forceMode: .cheap
        )
        #expect(decision.model == "claude-haiku-4-5-20251001")
        #expect(decision.estimatedCost == .cheap)
    }

    @Test func routeEmptyPreferredModelReturnsPreferredReason() {
        let decision = LLMRouter.route(
            prompt: "oi",
            history: [],
            provider: "openai",
            preferredModel: ""
        )
        #expect(decision.reason == .preferredModel)
    }
}
