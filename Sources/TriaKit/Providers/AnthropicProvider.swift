import Foundation

/// Cliente propio de la Messages API (no hay SDK oficial en Swift).
public struct AnthropicProvider: LLMProvider {
    public let id = ProviderID.anthropic
    public let model: String
    private let apiKey: String
    private let transport: any HTTPTransport
    private let policy: RetryPolicy
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Modelos con fallback de servidor ante rechazos de los clasificadores de seguridad.
    public static let fallbackModels = AnthropicMessages.fallbackModels

    public static func supportsEffort(_ model: String) -> Bool {
        AnthropicMessages.supportsEffort(model)
    }

    public init(apiKey: String, model: String = ProviderID.anthropic.defaultModel,
                transport: any HTTPTransport = URLSessionTransport(), policy: RetryPolicy = .init()) {
        self.apiKey = apiKey
        self.model = model
        self.transport = transport
        self.policy = policy
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        if Self.fallbackModels.contains(model) {
            urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = try body(for: request).encodedData()
        let data = try await sendWithRetry(urlRequest, transport: transport, policy: policy, classify: Self.classify)
        return try Self.parse(data)
    }

    public func body(for request: LLMRequest) -> JSONValue {
        AnthropicMessages.body(for: request, target: .anthropicAPI(model: model))
    }

    public static func classify(status: Int, data: Data) -> RetryDecision {
        let message = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]?["message"]?.stringValue
            ?? String(decoding: data.prefix(300), as: UTF8.self)
        switch status {
        case 200..<300: return .success
        case 401: return .fail(.invalidKey)
        case 429: return .retry(.rateLimited)
        case 500, 502, 503, 504, 529: return .retry(.unavailable(message))
        case 400 where message.lowercased().contains("not scoped to a workspace"): return .fail(.keyWithoutWorkspace)
        case 400 where message.lowercased().contains("credit balance"): return .fail(.quotaExceeded(message))
        default: return .fail(.rejected(status: status, message: message))
        }
    }

    public static func parse(_ data: Data) throws -> LLMResponse {
        try AnthropicMessages.parse(data, model: "")
    }
}
