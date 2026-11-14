import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

@Test func aKeyThatTheProviderAcceptsIsValid() async {
    let transport = StubTransport([.http(200, "{}")])
    #expect(await KeyChecker.check(.anthropic, apiKey: "clave-de-prueba", transport: transport) == .valid)
}

@Test func aKeyThatTheProviderRefusesIsRejected() async {
    let transport = StubTransport([.http(401, "{}")])
    #expect(await KeyChecker.check(.openai, apiKey: "clave-de-prueba", transport: transport) == .rejected)
}

@Test func anyOtherStatusLeavesTheKeyUnknown() async {
    let transport = StubTransport([.http(500, "{}")])
    #expect(await KeyChecker.check(.anthropic, apiKey: "clave-de-prueba", transport: transport) == .unknown)
}

@Test func aTransportErrorLeavesTheKeyUnknown() async {
    let transport = StubTransport([.network(.notConnectedToInternet)])
    #expect(await KeyChecker.check(.openai, apiKey: "clave-de-prueba", transport: transport) == .unknown)
}

@Test func theAnthropicCheckListsModelsWithItsHeaders() async throws {
    let transport = StubTransport([.http(200, "{}")])
    _ = await KeyChecker.check(.anthropic, apiKey: "clave-de-prueba", transport: transport)
    let sent = try #require(await transport.requests.first)
    #expect(sent.httpMethod == "GET")
    #expect(sent.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=1")
    #expect(sent.value(forHTTPHeaderField: "x-api-key") == "clave-de-prueba")
    #expect(sent.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    #expect(sent.timeoutInterval == 10)
    #expect(sent.httpBody == nil)
}

@Test func theOpenAICheckListsModelsWithABearerKey() async throws {
    let transport = StubTransport([.http(200, "{}")])
    _ = await KeyChecker.check(.openai, apiKey: "clave-de-prueba", transport: transport)
    let sent = try #require(await transport.requests.first)
    #expect(sent.httpMethod == "GET")
    #expect(sent.url?.absoluteString == "https://api.openai.com/v1/models")
    #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer clave-de-prueba")
    #expect(sent.timeoutInterval == 10)
}

@Test func theCheckDoesNotRetry() async {
    let transport = StubTransport([.http(500, "{}"), .http(200, "{}")])
    #expect(await KeyChecker.check(.anthropic, apiKey: "clave-de-prueba", transport: transport) == .unknown)
    #expect(await transport.requests.count == 1)
}
