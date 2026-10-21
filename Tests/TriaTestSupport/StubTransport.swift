import Foundation
import TriaKit

/// Transporte con respuestas grabadas: la CI no necesita red ni keys (spec §9.1).
public actor StubTransport: HTTPTransport {
    public enum Reply: Sendable {
        case http(Int, String, [String: String] = [:])
        case network(URLError.Code)
    }

    private var replies: [Reply]
    public private(set) var requests: [URLRequest] = []

    public init(_ replies: [Reply]) { self.replies = replies }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.cannotConnectToHost) }
        switch replies.removeFirst() {
        case .network(let code):
            throw URLError(code)
        case .http(let status, let body, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (Data(body.utf8), response)
        }
    }

    public func lastBody() -> JSONValue? {
        guard let data = requests.last?.httpBody else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}
