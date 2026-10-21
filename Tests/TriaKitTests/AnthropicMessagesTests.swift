import Foundation
import Testing
@testable import TriaKit

private let recorded = """
{"id":"msg_01","type":"message","role":"assistant","model":"claude-opus-5-5",
 "content":[{"type":"thinking","thinking":"","signature":"sig"},{"type":"text","text":"{\\"action\\":\\"file\\"}"}],
 "stop_reason":"end_turn","stop_details":null,
 "usage":{"input_tokens":1200,"output_tokens":80,"cache_creation_input_tokens":300,"cache_read_input_tokens":900}}
"""

private func request() -> LLMRequest {
    LLMRequest(system: "SYSTEM", cachedContext: "RULES+TREE", userText: "DOC",
               images: [LLMImage(jpeg: Data([0xFF, 0xD8]))],
               schemaName: "proposal", schema: ["type": "object"], maxOutputTokens: 4096)
}

@Test func bedrockBodyHasVersionAndNoModel() {
    let body = AnthropicMessages.body(for: request(), target: .bedrock)
    #expect(body["anthropic_version"] == "bedrock-2023-05-31")
    #expect(body["model"] == nil)
    #expect(body["fallbacks"] == nil)
    #expect(body["parts"] == nil)
    #expect(body["system"]?.arrayValue?[1]["cache_control"]?["type"] == "ephemeral")
    #expect(body["output_config"]?["format"]?["type"] == "json_schema")
}

@Test func apiBodyIsUnchanged() {
    let body = AnthropicMessages.body(for: request(), target: .anthropicAPI(model: "claude-sonnet-5-5"))
    let expected: JSONValue = [
        "model": "claude-sonnet-5-5",
        "max_tokens": 4096,
        "system": [
            ["type": "text", "text": "SYSTEM"],
            ["type": "text", "text": "RULES+TREE", "cache_control": ["type": "ephemeral"]],
        ],
        "messages": [["role": "user", "content": [
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                          "data": .string(Data([0xFF, 0xD8]).base64EncodedString())]],
            ["type": "text", "text": "DOC"],
        ]]],
        "output_config": ["format": ["type": "json_schema", "schema": ["type": "object"]], "effort": "low"],
        "fallbacks": "default",
    ]
    #expect(body == expected)
    #expect(AnthropicProvider(apiKey: "k", model: "claude-sonnet-5-5").body(for: request()) == expected)
}

@Test func parseReadsTextAndUsage() throws {
    let response = try AnthropicMessages.parse(Data(recorded.utf8), model: "x")
    #expect(response.text == #"{"action":"file"}"#)
    #expect(response.model == "claude-opus-5-5")
    #expect(response.usage == TokenUsage(inputTokens: 1200, outputTokens: 80, cacheReadTokens: 900, cacheWriteTokens: 300))
}

@Test func serviceLimitIsFatal() {
    #expect(LLMError.serviceLimit("balanceEmpty").isFatal)
    #expect(!LLMError.serviceLimit("balanceEmpty").isTransient)
}
