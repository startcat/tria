import Foundation
import TriaKit

/// Proveedor de prueba: el handler decide la respuesta según la petición (normalmente por el nombre del fichero).
public actor ScriptedProvider: LLMProvider {
    public nonisolated let id: ProviderID
    public nonisolated let model: String
    private let handler: @Sendable (LLMRequest) throws -> String
    public private(set) var requests: [LLMRequest] = []

    public init(id: ProviderID = .anthropic, model: String = "claude-haiku-5-5",
                handler: @escaping @Sendable (LLMRequest) throws -> String) {
        self.id = id
        self.model = model
        self.handler = handler
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        requests.append(request)
        return LLMResponse(text: try handler(request), usage: TokenUsage(inputTokens: 100, outputTokens: 10), model: model)
    }

    public static func proposalJSON(action: String = "file", destination: String, filename: String,
                                    confidence: String = "high", reason: String = "razón",
                                    doubt: String? = nil, date: String? = "2025-01-10") -> String {
        let value: JSONValue = [
            "action": .string(action), "destination": .string(destination), "filename": .string(filename),
            "document_type": "Documento", "document_date": date.map(JSONValue.string) ?? .null,
            "confidence": .string(confidence), "reason": .string(reason), "doubt": doubt.map(JSONValue.string) ?? .null,
        ]
        return String(decoding: try! value.encodedData(), as: UTF8.self)
    }
}
