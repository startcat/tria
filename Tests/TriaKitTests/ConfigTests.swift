import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

@Test func configRoundTripsAndDefaults() throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("tria/config.toml")
    #expect(try UserConfig.load(from: url) == UserConfig())
    #expect(UserConfig().resolvedModel == "claude-sonnet-5-5")

    let config = UserConfig(provider: .openai, model: "gpt-5.4-nano")
    try config.save(to: url)
    #expect(try UserConfig.load(from: url) == config)
    #expect(!(try String(contentsOf: url, encoding: .utf8)).contains("sk-"))
}

@Test func parsesCommentsAndIgnoresUnknownKeys() throws {
    let config = try UserConfig.parse("# comentario\n\nprovider = \"openai\"\nfuturo = 1\n")
    #expect(config == UserConfig(provider: .openai, model: nil))
    #expect(config.resolvedModel == "gpt-5.4-mini")
}

@Test func rejectsBadConfig() {
    #expect(throws: ConfigError.unknownProvider("gemini")) { try UserConfig.parse("provider = \"gemini\"") }
    #expect(throws: ConfigError.invalidLine(1, "esto no vale")) { try UserConfig.parse("esto no vale") }
}

@Test func configPathFollowsXDG() {
    #expect(UserConfig.defaultURL(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"]).path == "/tmp/xdg/tria/config.toml")
    #expect(UserConfig.defaultURL(environment: ["HOME": "/Users/ana"]).path == "/Users/ana/.config/tria/config.toml")
}

@Test func environmentKeyWinsOverTheStore() throws {
    let store = InMemorySecretStore([.anthropic: "sk-ant-store"])
    #expect(try APIKeyResolver.resolve(.anthropic, environment: ["ANTHROPIC_API_KEY": "sk-ant-env"], store: store) == "sk-ant-env")
    #expect(try APIKeyResolver.resolve(.anthropic, environment: ["ANTHROPIC_API_KEY": "  "], store: store) == "sk-ant-store")
    #expect(try APIKeyResolver.resolve(.openai, environment: [:], store: store) == nil)
}

@Test func inMemoryStoreSetsAndDeletes() throws {
    let store = InMemorySecretStore()
    try store.setAPIKey("sk-x", for: .openai)
    #expect(try store.apiKey(for: .openai) == "sk-x")
    try store.deleteAPIKey(for: .openai)
    #expect(try store.apiKey(for: .openai) == nil)
}

@Test func masksKeys() {
    #expect(APIKeyResolver.masked("sk-ant-api03-abcdefghijkl1234") == "sk-ant…1234")
    #expect(APIKeyResolver.masked("corta") == "••••")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TRIA_KEYCHAIN_TESTS"] == "1"))
func keychainRoundTripUsesATestService() throws {
    let store = KeychainSecretStore(service: "cat.start.tria.tests")
    try store.setAPIKey("sk-test-123456789", for: .anthropic)
    #expect(try store.apiKey(for: .anthropic) == "sk-test-123456789")
    try store.deleteAPIKey(for: .anthropic)
    #expect(try store.apiKey(for: .anthropic) == nil)
}
