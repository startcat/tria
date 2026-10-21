import Foundation

public enum ProviderID: String, Codable, Sendable, CaseIterable {
    case anthropic, openai

    /// Modelos por defecto; se revisan con `tria eval` (spec R4). Anthropic: Sonnet 5.5, elegido el 14 oct de 2026
    /// con el archivo real: acierta como Opus 5.5 a mitad de coste, y Haiku 5.5 queda lejos.
    public var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-5-5"
        case .openai: return "gpt-5.4-mini"
        }
    }

    public var environmentKey: String {
        switch self {
        case .anthropic: return "ANTHROPIC_API_KEY"
        case .openai: return "OPENAI_API_KEY"
        }
    }
}

public struct LLMImage: Sendable, Equatable {
    public var mediaType: String
    public var data: Data

    public init(jpeg: Data) {
        mediaType = "image/jpeg"
        data = jpeg
    }
}

public struct LLMRequest: Sendable, Equatable {
    /// Instrucciones fijas.
    public var system: String
    /// Reglas + árbol: prefijo común del lote, cacheable (spec §6.3, paso 3).
    public var cachedContext: String
    /// Documento concreto (metadatos + extracto).
    public var userText: String
    public var images: [LLMImage]
    public var schemaName: String
    public var schema: JSONValue
    public var maxOutputTokens: Int
    /// Las piezas con las que se armó, si las hay: con la IA de Tria se envían al servidor en lugar del texto.
    public var parts: TriaRequestParts?

    public init(system: String, cachedContext: String, userText: String, images: [LLMImage] = [],
                schemaName: String, schema: JSONValue, maxOutputTokens: Int = 4096, parts: TriaRequestParts? = nil) {
        self.system = system
        self.cachedContext = cachedContext
        self.userText = userText
        self.images = images
        self.schemaName = schemaName
        self.schema = schema
        self.maxOutputTokens = maxOutputTokens
        self.parts = parts
    }
}

public struct TokenUsage: Codable, Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0, cacheWriteTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }

    public static let zero = TokenUsage()

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(inputTokens: lhs.inputTokens + rhs.inputTokens, outputTokens: lhs.outputTokens + rhs.outputTokens,
                   cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
                   cacheWriteTokens: lhs.cacheWriteTokens + rhs.cacheWriteTokens)
    }
}

public struct LLMResponse: Sendable, Equatable {
    public var text: String
    public var usage: TokenUsage
    public var model: String

    public init(text: String, usage: TokenUsage, model: String) {
        self.text = text
        self.usage = usage
        self.model = model
    }
}

public enum LLMError: Error, Equatable, Sendable {
    case invalidKey
    /// La key de Anthropic no pertenece a ningún workspace (HTTP 400): es un problema de la key, no del documento.
    case keyWithoutWorkspace
    case quotaExceeded(String)
    case rateLimited
    case unavailable(String)
    case offline
    case rejected(status: Int, message: String)
    case refused
    case truncated
    case badResponse(String)
    /// Límite del servicio de la IA de Tria; el texto es `TriaAPI.ErrorCode.rawValue`. Solo lo lanza ese proveedor.
    case serviceLimit(String)

    /// Se pausa el lote sin mover nada (spec §10).
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .unavailable, .offline: return true
        default: return false
        }
    }

    /// No tiene sentido seguir: hay que arreglar la key o la cuenta.
    public var isFatal: Bool {
        switch self {
        case .invalidKey, .keyWithoutWorkspace, .quotaExceeded, .serviceLimit: return true
        default: return false
        }
    }
}

public protocol LLMProvider: Sendable {
    var id: ProviderID { get }
    var model: String { get }
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}
