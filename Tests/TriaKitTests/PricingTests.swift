import Testing
@testable import TriaKit

@Test func computesCostIncludingCache() throws {
    let usage = TokenUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadTokens: 1_000_000, cacheWriteTokens: 1_000_000)
    let cost = try #require(Pricing.cost(usage, model: "claude-haiku-5-5"))
    #expect(abs(cost - (0.10 + 0.50 + 0.01 + 0.125)) < 0.000_001)
    #expect(Pricing.cost(usage, model: "modelo-inventado") == nil)
}

@Test func estimatesTokensFromCharacters() throws {
    #expect(Pricing.estimatedTokens(characters: 4_000) == 1_000)
    let estimate = try #require(Pricing.estimateCost(inputTokens: 1_000_000, outputTokens: 0, model: "claude-opus-5-5"))
    #expect(abs(estimate - 4.0) < 0.000_001)
}

@Test func everyDefaultModelHasAPrice() {
    for provider in ProviderID.allCases { #expect(Pricing.price(for: provider.defaultModel) != nil) }
}

@Test func factoryBuildsTheRightProvider() {
    let anthropic = ProviderFactory.make(.anthropic, model: "claude-haiku-5-5", apiKey: "k")
    #expect(anthropic.id == .anthropic && anthropic.model == "claude-haiku-5-5")
    let openai = ProviderFactory.make(.openai, model: "gpt-5.4-nano", apiKey: "k")
    #expect(openai.id == .openai && openai.model == "gpt-5.4-nano")
}

@Test func sonnet46HasItsPrice() throws {
    let usage = TokenUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadTokens: 1_000_000,
                           cacheWriteTokens: 1_000_000)
    let cost = try #require(Pricing.cost(usage, model: "claude-sonnet-4-6"))
    #expect(abs(cost - (3.00 + 15.00 + 0.30 + 3.75)) < 0.000_001)
}
