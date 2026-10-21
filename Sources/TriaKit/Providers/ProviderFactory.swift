public enum ProviderFactory {
    public static func make(_ provider: ProviderID, model: String, apiKey: String,
                            transport: any HTTPTransport = URLSessionTransport()) -> any LLMProvider {
        switch provider {
        case .anthropic: return AnthropicProvider(apiKey: apiKey, model: model, transport: transport)
        case .openai: return OpenAIProvider(apiKey: apiKey, model: model, transport: transport)
        }
    }
}
