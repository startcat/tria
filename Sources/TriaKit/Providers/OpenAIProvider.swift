import Foundation

/// Cliente propio de la Responses API. `store: false`: OpenAI no guarda los documentos.
public struct OpenAIProvider: LLMProvider {
    public let id = ProviderID.openai
    public let model: String
    private let apiKey: String
    private let transport: any HTTPTransport
    private let policy: RetryPolicy
    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    public init(apiKey: String, model: String = ProviderID.openai.defaultModel,
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
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try body(for: request).encodedData()
        let data = try await sendWithRetry(urlRequest, transport: transport, policy: policy, classify: Self.classify)
        return try Self.parse(data)
    }

    public func body(for request: LLMRequest) -> JSONValue {
        var content: [JSONValue] = [["type": "input_text", "text": .string(request.userText)]]
        content += request.images.map { image in
            ["type": "input_image", "image_url": .string("data:\(image.mediaType);base64,\(image.data.base64EncodedString())")]
        }
        return [
            "model": .string(model),
            "instructions": .string(request.system + "\n\n" + request.cachedContext),
            "input": [["role": "user", "content": .array(content)]],
            "text": ["format": ["type": "json_schema", "name": .string(request.schemaName),
                                "schema": request.schema, "strict": true]],
            "max_output_tokens": .int(request.maxOutputTokens),
            "store": false,
        ]
    }

    public static func classify(status: Int, data: Data) -> RetryDecision {
        let error = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]
        let message = error?["message"]?.stringValue ?? String(decoding: data.prefix(300), as: UTF8.self)
        switch status {
        case 200..<300: return .success
        case 401: return .fail(.invalidKey)
        case 429 where error?["code"]?.stringValue == "insufficient_quota": return .fail(.quotaExceeded(message))
        case 429: return .retry(.rateLimited)
        case 500...599: return .retry(.unavailable(message))
        default: return .fail(.rejected(status: status, message: message))
        }
    }

    public static func parse(_ data: Data) throws -> LLMResponse {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw LLMError.badResponse(String(decoding: data.prefix(300), as: UTF8.self))
        }
        if json["status"]?.stringValue == "incomplete",
           json["incomplete_details"]?["reason"]?.stringValue == "max_output_tokens" {
            throw LLMError.truncated
        }
        var text = ""
        for item in json["output"]?.arrayValue ?? [] where item["type"]?.stringValue == "message" {
            for part in item["content"]?.arrayValue ?? [] {
                switch part["type"]?.stringValue {
                case "output_text": text += part["text"]?.stringValue ?? ""
                case "refusal": throw LLMError.refused
                default: break
                }
            }
        }
        guard !text.isEmpty else { throw LLMError.badResponse("no output_text") }
        let usage = json["usage"]
        let input = usage?["input_tokens"]?.intValue ?? 0
        let cached = usage?["input_tokens_details"]?["cached_tokens"]?.intValue ?? 0
        return LLMResponse(
            text: text,
            usage: TokenUsage(inputTokens: input - cached, outputTokens: usage?["output_tokens"]?.intValue ?? 0,
                              cacheReadTokens: cached, cacheWriteTokens: 0),
            model: json["model"]?.stringValue ?? "")
    }
}
