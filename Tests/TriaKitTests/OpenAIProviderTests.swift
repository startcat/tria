import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private let okResponse = """
{"id":"resp_1","object":"response","status":"completed","model":"gpt-5.4-mini",
 "output":[{"type":"reasoning","summary":[]},
           {"type":"message","role":"assistant","content":[{"type":"output_text","text":"{\\"action\\":\\"pending\\"}"}]}],
 "usage":{"input_tokens":2000,"input_tokens_details":{"cached_tokens":1500},"output_tokens":60}}
"""

private func request(images: [LLMImage] = []) -> LLMRequest {
    LLMRequest(system: "SYSTEM", cachedContext: "RULES+TREE", userText: "DOC", images: images,
               schemaName: "proposal", schema: ["type": "object"], maxOutputTokens: 4096)
}

@Test func buildsTheResponsesRequest() async throws {
    let transport = StubTransport([.http(200, okResponse)])
    _ = try await OpenAIProvider(apiKey: "sk-test", transport: transport, policy: .immediate)
        .complete(request(images: [LLMImage(jpeg: Data([0xFF, 0xD8]))]))

    let sent = try #require(await transport.requests.first)
    #expect(sent.url?.absoluteString == "https://api.openai.com/v1/responses")
    #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    let body = try #require(await transport.lastBody())
    #expect(body["model"] == "gpt-5.4-mini")
    #expect(body["store"] == false)
    #expect(body["instructions"] == "SYSTEM\n\nRULES+TREE")
    #expect(body["max_output_tokens"] == 4096)
    #expect(body["text"]?["format"] == ["type": "json_schema", "name": "proposal", "schema": ["type": "object"], "strict": true])
    let content = try #require(body["input"]?.arrayValue?.first?["content"]?.arrayValue)
    #expect(content[0] == ["type": "input_text", "text": "DOC"])
    #expect(content[1]["type"] == "input_image")
    #expect(content[1]["image_url"] == .string("data:image/jpeg;base64," + Data([0xFF, 0xD8]).base64EncodedString()))
}

@Test func parsesOutputTextAndCachedUsage() throws {
    let response = try OpenAIProvider.parse(Data(okResponse.utf8))
    #expect(response.text == #"{"action":"pending"}"#)
    #expect(response.usage == TokenUsage(inputTokens: 500, outputTokens: 60, cacheReadTokens: 1500, cacheWriteTokens: 0))
    #expect(response.model == "gpt-5.4-mini")
}

@Test func mapsRefusalAndIncompleteResponses() {
    let refusal = okResponse.replacingOccurrences(
        of: #"{"type":"output_text","text":"{\"action\":\"pending\"}"}"#, with: #"{"type":"refusal","refusal":"No"}"#)
    #expect(throws: LLMError.refused) { try OpenAIProvider.parse(Data(refusal.utf8)) }
    let incomplete = #"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#
    #expect(throws: LLMError.truncated) { try OpenAIProvider.parse(Data(incomplete.utf8)) }
}

@Test func quotaIsFinalButRateLimitsAreRetried() async throws {
    let quota = #"{"error":{"message":"You exceeded your current quota","type":"insufficient_quota","code":"insufficient_quota"}}"#
    await #expect(throws: LLMError.quotaExceeded("You exceeded your current quota")) {
        try await OpenAIProvider(apiKey: "k", transport: StubTransport([.http(429, quota)]), policy: .immediate).complete(request())
    }
    let limited = #"{"error":{"message":"Rate limit reached","type":"requests","code":"rate_limit_exceeded"}}"#
    let transport = StubTransport([.http(429, limited), .http(200, okResponse)])
    _ = try await OpenAIProvider(apiKey: "k", transport: transport, policy: .immediate).complete(request())
    #expect(await transport.requests.count == 2)

    let invalid = #"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error","code":"invalid_api_key"}}"#
    await #expect(throws: LLMError.invalidKey) {
        try await OpenAIProvider(apiKey: "k", transport: StubTransport([.http(401, invalid)]), policy: .immediate).complete(request())
    }
}
