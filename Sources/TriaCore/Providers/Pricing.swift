public struct ModelPrice: Sendable, Equatable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheWrite: Double

    public init(input: Double, output: Double, cacheRead: Double, cacheWrite: Double) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
}

/// Precios en USD por millón de tokens, a 2026-10-22.
/// Anthropic: precios publicados por Anthropic (Haiku 5.5 hasta 100K tokens de prompt; la escritura de la caché es la
/// de 5 minutos).
/// OpenAI: agregadores de precios; contrastar con openai.com/api/pricing antes de publicar.
public enum Pricing {
    public static let table: [String: ModelPrice] = [
        "claude-haiku-5-5": ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite: 0.125),
        "claude-sonnet-5-5": ModelPrice(input: 2.00, output: 10.00, cacheRead: 0.20, cacheWrite: 2.50),
        "claude-sonnet-4-6": ModelPrice(input: 3.00, output: 15.00, cacheRead: 0.30, cacheWrite: 3.75),
        "claude-opus-5-5": ModelPrice(input: 4.00, output: 20.00, cacheRead: 0.20, cacheWrite: 5.00),
        "gpt-5.4-mini": ModelPrice(input: 0.75, output: 4.50, cacheRead: 0.075, cacheWrite: 0.75),
        "gpt-5.4-nano": ModelPrice(input: 0.20, output: 1.25, cacheRead: 0.02, cacheWrite: 0.20),
    ]

    public static func price(for model: String) -> ModelPrice? { table[model] }

    public static func cost(_ usage: TokenUsage, model: String) -> Double? {
        guard let price = price(for: model) else { return nil }
        return (Double(usage.inputTokens) * price.input + Double(usage.outputTokens) * price.output
                + Double(usage.cacheReadTokens) * price.cacheRead + Double(usage.cacheWriteTokens) * price.cacheWrite)
            / 1_000_000
    }

    /// Aproximación de unos 4 caracteres por token. Solo para estimaciones previas.
    public static func estimatedTokens(characters: Int) -> Int { (characters + 3) / 4 }

    public static func estimateCost(inputTokens: Int, outputTokens: Int, model: String) -> Double? {
        cost(TokenUsage(inputTokens: inputTokens, outputTokens: outputTokens), model: model)
    }
}
