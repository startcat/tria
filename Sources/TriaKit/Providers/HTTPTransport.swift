import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var baseDelay: Double
    public var maxDelay: Double
    public var sleep: @Sendable (Double) async throws -> Void

    public init(maxAttempts: Int = 4, baseDelay: Double = 1, maxDelay: Double = 30,
                sleep: @escaping @Sendable (Double) async throws -> Void = { seconds in
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                }) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.sleep = sleep
    }

    public static let immediate = RetryPolicy(sleep: { _ in })

    func delay(attempt: Int, retryAfter: String?) -> Double {
        if let retryAfter, let seconds = Double(retryAfter.trimmingCharacters(in: .whitespaces)) {
            return min(seconds, maxDelay)
        }
        return min(baseDelay * pow(2, Double(attempt - 1)), maxDelay)
    }
}

public enum RetryDecision: Sendable {
    case success
    case retry(LLMError)
    case fail(LLMError)
}

/// Envía con reintentos y espera exponencial, respetando `retry-after` (spec §10).
public func sendWithRetry(_ request: URLRequest, transport: any HTTPTransport, policy: RetryPolicy,
                          classify: @Sendable (Int, Data) -> RetryDecision) async throws -> Data {
    var lastError = LLMError.unavailable("no attempts")
    for attempt in 1...policy.maxAttempts {
        var retryAfter: String?
        do {
            let (data, response) = try await transport.send(request)
            switch classify(response.statusCode, data) {
            case .success: return data
            case .fail(let error): throw error
            case .retry(let error):
                lastError = error
                retryAfter = response.value(forHTTPHeaderField: "retry-after")
            }
        } catch let error as URLError {
            lastError = [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff].contains(error.code)
                ? .offline : .unavailable(error.localizedDescription)
        }
        if attempt < policy.maxAttempts {
            try await policy.sleep(policy.delay(attempt: attempt, retryAfter: retryAfter))
        }
    }
    throw lastError
}
