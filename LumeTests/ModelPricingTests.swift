//
//  ModelPricingTests.swift
//  LumeTests
//
//  Cobre a tabela de preços e os utilitários de custo/formatação.
//

import Testing
@testable import Lume

struct ModelPricingTests {

    // MARK: - price

    @Test func priceExactMatch() {
        let p = ModelPricing.price(for: "gpt-4o")
        #expect(p?.input == 2.50)
        #expect(p?.output == 10.00)
    }

    @Test func pricePrefixMatchForVersionedModel() {
        // "claude-haiku-4-5-20251001" casa exatamente; valida correspondência por prefixo
        // num modelo que só existe na tabela como base.
        let p = ModelPricing.price(for: "claude-sonnet-4-6-20260101")
        #expect(p?.input == 3.00)
        #expect(p?.output == 15.00)
    }

    @Test func priceFamilyHeuristicForUnknown() {
        #expect(ModelPricing.price(for: "acme-haiku-custom")?.input == 0.20)
        #expect(ModelPricing.price(for: "acme-opus-custom")?.output == 75.00)
        #expect(ModelPricing.price(for: "acme-sonnet-custom")?.input == 3.00)
    }

    @Test func priceUnknownReturnsNil() {
        #expect(ModelPricing.price(for: "totally-unknown-xyz") == nil)
    }

    // MARK: - blendedPer1M

    @Test func blendedPriceWeighting() {
        let p = ModelPrice(input: 10, output: 20)
        // 10*0.65 + 20*0.35 = 6.5 + 7 = 13.5
        #expect(abs(p.blendedPer1M - 13.5) < 0.0001)
    }

    // MARK: - estimatedCost

    @Test func estimatedCostScalesWithTokens() {
        let cost = ModelPricing.estimatedCost(model: "gpt-4o", tokens: 1_000_000)
        // blended = 2.50*0.65 + 10*0.35 = 1.625 + 3.5 = 5.125 por 1M
        #expect(cost != nil)
        #expect(abs(cost! - 5.125) < 0.0001)
    }

    @Test func estimatedCostZeroTokensReturnsNil() {
        #expect(ModelPricing.estimatedCost(model: "gpt-4o", tokens: 0) == nil)
    }

    @Test func estimatedCostUnknownModelReturnsNil() {
        #expect(ModelPricing.estimatedCost(model: "unknown-xyz", tokens: 1000) == nil)
    }

    // MARK: - formatCost

    @Test func formatCostBuckets() {
        #expect(ModelPricing.formatCost(0.0023) == "$0.0023")
        #expect(ModelPricing.formatCost(0.42) == "$0.420")
        #expect(ModelPricing.formatCost(1.42) == "$1.42")
    }

    // MARK: - formatTokens

    @Test func formatTokensBuckets() {
        #expect(ModelPricing.formatTokens(500) == "500")
        #expect(ModelPricing.formatTokens(1_200) == "1.2k")
        #expect(ModelPricing.formatTokens(3_400_000) == "3.4M")
    }
}
