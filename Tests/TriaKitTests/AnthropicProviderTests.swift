import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private let okResponse = """
{"id":"msg_01","type":"message","role":"assistant","model":"claude-opus-5-5",
 "content":[{"type":"thinking","thinking":"","signature":"sig"},{"type":"text","text":"{\\"action\\":\\"file\\"}"}],
 "stop_reason":"end_turn","stop_details":null,
 "usage":{"input_tokens":1200,"output_tokens":80,"cache_creation_input_tokens":300,"cache_read_input_tokens":900}}
"""

private func request(images: [LLMImage] = []) -> LLMRequest {
    LLMRequest(system: "SYSTEM", cachedContext: "RULES+TREE", userText: "DOC", images: images,
               schemaName: "proposal", schema: ["type": "object"], maxOutputTokens: 4096)
}

@Test func buildsTheMessagesRequest() async throws {
    let transport = StubTransport([.http(200, okResponse)])
    let provider = AnthropicProvider(apiKey: "sk-ant-test", model: "claude-opus-5-5", transport: transport, policy: .immediate)
    _ = try await provider.complete(request(images: [LLMImage(jpeg: Data([0xFF, 0xD8]))]))

    let sent = try #require(await transport.requests.first)
    #expect(sent.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(sent.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
    #expect(sent.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    #expect(sent.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")

    let body = try #require(await transport.lastBody())
    #expect(body["model"] == "claude-opus-5-5")
    #expect(body["max_tokens"] == 4096)
    #expect(body["fallbacks"] == "default")
    let system = try #require(body["system"]?.arrayValue)
    #expect(system.count == 2)
    #expect(system[0]["text"] == "SYSTEM" && system[0]["cache_control"] == nil)
    #expect(system[1]["text"] == "RULES+TREE" && system[1]["cache_control"]?["type"] == "ephemeral")
    #expect(body["output_config"]?["format"]?["type"] == "json_schema")
    #expect(body["output_config"]?["format"]?["schema"] == ["type": "object"])
    #expect(body["output_config"]?["effort"] == "low")
    let content = try #require(body["messages"]?.arrayValue?.first?["content"]?.arrayValue)
    #expect(content[0]["type"] == "image")
    #expect(content[0]["source"]?["media_type"] == "image/jpeg")
    #expect(content[0]["source"]?["data"] == .string(Data([0xFF, 0xD8]).base64EncodedString()))
    #expect(content[1]["text"] == "DOC")
}

@Test func olderModelsGetNeitherEffortNorFallbacks() async throws {
    let transport = StubTransport([.http(200, okResponse)])
    _ = try await AnthropicProvider(apiKey: "k", model: "claude-haiku-4-5", transport: transport, policy: .immediate)
        .complete(request())
    let body = try #require(await transport.lastBody())
    #expect(body["output_config"]?["effort"] == nil)
    #expect(body["fallbacks"] == nil)
    #expect(await transport.requests.first?.value(forHTTPHeaderField: "anthropic-beta") == nil)
    #expect(AnthropicProvider.supportsEffort("claude-haiku-5-5"))
    #expect(!AnthropicProvider.fallbackModels.contains("claude-haiku-5-5"))
}

@Test func parsesTextAndUsage() throws {
    let response = try AnthropicProvider.parse(Data(okResponse.utf8))
    #expect(response.text == #"{"action":"file"}"#)
    #expect(response.model == "claude-opus-5-5")
    #expect(response.usage == TokenUsage(inputTokens: 1200, outputTokens: 80, cacheReadTokens: 900, cacheWriteTokens: 300))
}

@Test func mapsStopReasons() {
    let refusal = okResponse.replacingOccurrences(of: "\"end_turn\"", with: "\"refusal\"")
    #expect(throws: LLMError.refused) { try AnthropicProvider.parse(Data(refusal.utf8)) }
    let truncated = okResponse.replacingOccurrences(of: "\"end_turn\"", with: "\"max_tokens\"")
    #expect(throws: LLMError.truncated) { try AnthropicProvider.parse(Data(truncated.utf8)) }
}

@Test func mapsErrors() async {
    func provider(_ replies: [StubTransport.Reply]) -> AnthropicProvider {
        AnthropicProvider(apiKey: "k", transport: StubTransport(replies), policy: .immediate)
    }
    let invalid = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
    await #expect(throws: LLMError.invalidKey) { try await provider([.http(401, invalid)]).complete(request()) }

    let credit = #"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low"}}"#
    await #expect(throws: LLMError.quotaExceeded("Your credit balance is too low")) {
        try await provider([.http(400, credit)]).complete(request())
    }

    let missing = #"{"type":"error","error":{"type":"not_found_error","message":"model: claude-x"}}"#
    await #expect(throws: LLMError.rejected(status: 404, message: "model: claude-x")) {
        try await provider([.http(404, missing)]).complete(request())
    }
}

/// Una clave sin workspace es un problema de la clave: error propio, y cualquier otro 400 sigue siendo un rechazo.
@Test func mapsAKeyWithoutWorkspace() async {
    func provider(_ replies: [StubTransport.Reply]) -> AnthropicProvider {
        AnthropicProvider(apiKey: "k", transport: StubTransport(replies), policy: .immediate)
    }
    let noWorkspace = #"{"type":"error","error":{"type":"invalid_request_error","message":"This API key is Not Scoped To A Workspace. Set the anthropic-workspace-id header."}}"#
    await #expect(throws: LLMError.keyWithoutWorkspace) { try await provider([.http(400, noWorkspace)]).complete(request()) }

    let other = #"{"type":"error","error":{"type":"invalid_request_error","message":"messages: bad"}}"#
    await #expect(throws: LLMError.rejected(status: 400, message: "messages: bad")) {
        try await provider([.http(400, other)]).complete(request())
    }
    #expect(LLMError.keyWithoutWorkspace.isFatal && !LLMError.keyWithoutWorkspace.isTransient)
}

@Test func retriesOverloadedThenSucceeds() async throws {
    let overloaded = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
    let transport = StubTransport([.http(529, overloaded), .http(200, okResponse)])
    let response = try await AnthropicProvider(apiKey: "k", transport: transport, policy: .immediate).complete(request())
    #expect(response.usage.cacheReadTokens == 900)
    #expect(await transport.requests.count == 2)
}
