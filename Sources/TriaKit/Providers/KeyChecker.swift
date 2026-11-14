import Foundation

/// Resultado de probar una clave de API contra su proveedor.
public enum KeyCheck: Equatable, Sendable {
    /// El proveedor la acepta.
    case valid
    /// El proveedor la rechaza (401).
    case rejected
    /// No se pudo saber: sin conexión, tiempo agotado u otro estado.
    case unknown
}

/// Prueba una clave con una petición que no envía documentos ni gasta: la lista de modelos. Una sola petición, sin
/// reintentos y con 10 s de plazo; la clave solo va en la cabecera y nunca se registra.
public enum KeyChecker {
    public static func check(_ provider: ProviderID, apiKey: String,
                             transport: any HTTPTransport = URLSessionTransport()) async -> KeyCheck {
        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        do {
            let (_, response) = try await transport.send(request)
            switch response.statusCode {
            case 200..<300: return .valid
            case 401: return .rejected
            default: return .unknown
            }
        } catch {
            return .unknown
        }
    }
}
