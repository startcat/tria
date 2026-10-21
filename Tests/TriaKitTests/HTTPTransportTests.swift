import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private actor SleepLog {
    var delays: [Double] = []
    func record(_ delay: Double) { delays.append(delay) }
}

private func policy(_ log: SleepLog) -> RetryPolicy {
    RetryPolicy(sleep: { await log.record($0) })
}

private let request = URLRequest(url: URL(string: "https://example.test/v1")!)

private let classify: @Sendable (Int, Data) -> RetryDecision = { status, _ in
    switch status {
    case 200..<300: return .success
    case 429: return .retry(.rateLimited)
    case 500...599: return .retry(.unavailable("server"))
    default: return .fail(.rejected(status: status, message: "no"))
    }
}

@Test func retriesHonouringRetryAfterThenSucceeds() async throws {
    let log = SleepLog()
    let transport = StubTransport([.http(429, "", ["retry-after": "3"]), .http(200, "ok")])
    let data = try await sendWithRetry(request, transport: transport, policy: policy(log), classify: classify)
    #expect(String(decoding: data, as: UTF8.self) == "ok")
    #expect(await log.delays == [3])
}

@Test func givesUpAfterFourAttemptsWithExponentialBackoff() async {
    let log = SleepLog()
    let transport = StubTransport(Array(repeating: .http(503, ""), count: 4))
    await #expect(throws: LLMError.unavailable("server")) {
        try await sendWithRetry(request, transport: transport, policy: policy(log), classify: classify)
    }
    #expect(await log.delays == [1, 2, 4])
    #expect(await transport.requests.count == 4)
}

@Test func noConnectionEndsAsOffline() async {
    let transport = StubTransport(Array(repeating: .network(.notConnectedToInternet), count: 4))
    await #expect(throws: LLMError.offline) {
        try await sendWithRetry(request, transport: transport, policy: .immediate, classify: classify)
    }
}

@Test func finalErrorsAreNotRetried() async {
    let transport = StubTransport([.http(400, "bad"), .http(200, "ok")])
    await #expect(throws: LLMError.rejected(status: 400, message: "no")) {
        try await sendWithRetry(request, transport: transport, policy: .immediate, classify: classify)
    }
    #expect(await transport.requests.count == 1)
}

@Test func usageAddsUp() {
    let a = TokenUsage(inputTokens: 10, outputTokens: 2, cacheReadTokens: 100, cacheWriteTokens: 5)
    #expect(a + a == TokenUsage(inputTokens: 20, outputTokens: 4, cacheReadTokens: 200, cacheWriteTokens: 10))
    #expect(a + .zero == a)
}

@Test func errorFamilies() {
    #expect(LLMError.rateLimited.isTransient && LLMError.offline.isTransient)
    #expect(LLMError.invalidKey.isFatal && LLMError.quotaExceeded("x").isFatal)
    #expect(!LLMError.refused.isTransient && !LLMError.refused.isFatal)
    #expect(ProviderID.anthropic.defaultModel == "claude-sonnet-5-5")
    #expect(ProviderID.openai.environmentKey == "OPENAI_API_KEY")
}
