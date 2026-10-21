import Foundation

/// A dónde va el cuerpo: la API de Anthropic (lleva el modelo y el fallback) o Bedrock (el modelo va en la URL).
public enum AnthropicMessagesTarget: Sendable {
    case anthropicAPI(model: String)
    case bedrock
}

/// Cuerpo y respuesta de la Messages API, compartidos por el motor y por el servidor de la IA de Tria.
public enum AnthropicMessages {
    /// Modelos con fallback de servidor ante rechazos de los clasificadores de seguridad.
    public static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1"]

    public static func supportsEffort(_ model: String) -> Bool {
        ["claude-opus-5", "claude-sonnet-5", "claude-haiku-5", "claude-fable-5"].contains { model.hasPrefix($0) }
    }

    public static func body(for request: LLMRequest, target: AnthropicMessagesTarget) -> JSONValue {
        var content: [JSONValue] = request.images.map { image in
            ["type": "image", "source": ["type": "base64", "media_type": .string(image.mediaType),
                                         "data": .string(image.data.base64EncodedString())]]
        }
        content.append(["type": "text", "text": .string(request.userText)])

        var outputConfig: [String: JSONValue] = ["format": ["type": "json_schema", "schema": request.schema]]
        var body: [String: JSONValue] = [
            "max_tokens": .int(request.maxOutputTokens),
            "system": [
                ["type": "text", "text": .string(request.system)],
                ["type": "text", "text": .string(request.cachedContext), "cache_control": ["type": "ephemeral"]],
            ],
            "messages": [["role": "user", "content": .array(content)]],
        ]
        switch target {
        case .anthropicAPI(let model):
            body["model"] = .string(model)
            if supportsEffort(model) { outputConfig["effort"] = "low" }
            if fallbackModels.contains(model) { body["fallbacks"] = "default" }
        case .bedrock:
            body["anthropic_version"] = "bedrock-2023-05-31"
            outputConfig["effort"] = "low"
        }
        body["output_config"] = .object(outputConfig)
        return .object(body)
    }

    /// `model` es el de reserva cuando la respuesta no lo trae.
    public static func parse(_ data: Data, model: String) throws -> LLMResponse {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw LLMError.badResponse(String(decoding: data.prefix(300), as: UTF8.self))
        }
        switch json["stop_reason"]?.stringValue {
        case "refusal": throw LLMError.refused
        case "max_tokens": throw LLMError.truncated
        default: break
        }
        let text = (json["content"]?.arrayValue ?? [])
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined()
        guard !text.isEmpty else { throw LLMError.badResponse("no text content") }
        let usage = json["usage"]
        return LLMResponse(
            text: text,
            usage: TokenUsage(inputTokens: usage?["input_tokens"]?.intValue ?? 0,
                              outputTokens: usage?["output_tokens"]?.intValue ?? 0,
                              cacheReadTokens: usage?["cache_read_input_tokens"]?.intValue ?? 0,
                              cacheWriteTokens: usage?["cache_creation_input_tokens"]?.intValue ?? 0),
            model: json["model"]?.stringValue ?? model)
    }
}
