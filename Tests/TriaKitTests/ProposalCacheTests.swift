import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private func entry(_ key: String, sha: String = "abc", at date: Date) -> CacheEntry {
    CacheEntry(key: key, sha256: sha, rulesHash: nil, fileName: "doc.pdf", outcome: .pending(nil, .encrypted),
               method: nil, usage: .zero, provider: "anthropic", model: "claude-haiku-5-5", createdAt: date)
}

@Test func keyDependsOnFileRulesProviderAndModel() {
    let base = ProposalCache.key(sha256: "a", rulesHash: "r", provider: .anthropic, model: "m")
    #expect(base == ProposalCache.key(sha256: "a", rulesHash: "r", provider: .anthropic, model: "m"))
    #expect(base != ProposalCache.key(sha256: "a", rulesHash: "r2", provider: .anthropic, model: "m"))
    #expect(base != ProposalCache.key(sha256: "a", rulesHash: "r", provider: .openai, model: "m"))
    #expect(base != ProposalCache.key(sha256: "a", rulesHash: "r", provider: .anthropic, model: "m2"))
}

@Test func savesLoadsAndFindsTheLatest() throws {
    let dir = try TempDir()
    let cache = ProposalCache(workspace: try WorkspaceFixture.make(in: dir))
    try cache.save(entry("k1", at: Date(timeIntervalSince1970: 1_000)))
    try cache.save(entry("k2", at: Date(timeIntervalSince1970: 2_000)))
    try cache.save(entry("k3", sha: "otro", at: Date(timeIntervalSince1970: 3_000)))
    #expect(cache.load(sha256: "abc", key: "k1")?.key == "k1")
    #expect(cache.load(sha256: "abc", key: "nada") == nil)
    #expect(cache.latest(sha256: "abc")?.key == "k2")
}

private func read(_ model: String, provider: ProviderID = .anthropic, rules: String?, sha: String = "abc",
                  outcome: ClassificationOutcome = .pending(nil, .encrypted), at seconds: TimeInterval) -> CacheEntry {
    let key = ProposalCache.key(sha256: sha, rulesHash: rules ?? "viejas", provider: provider, model: model)
    return CacheEntry(key: key, sha256: sha, rulesHash: rules, fileName: "doc.pdf", outcome: outcome,
                      method: nil, usage: .zero, provider: provider.rawValue, model: model,
                      createdAt: Date(timeIntervalSince1970: seconds))
}

@Test func reusableFindsTheExactEntryFirst() throws {
    let dir = try TempDir()
    let cache = ProposalCache(workspace: try WorkspaceFixture.make(in: dir))
    try cache.save(read("claude-haiku-5-5", rules: "r", at: 1_000))
    try cache.save(read("claude-sonnet-5-5", rules: "r", at: 2_000))

    let found = cache.reusable(sha256: "abc", rulesHash: "r", provider: .anthropic, model: "claude-haiku-5-5")

    #expect(found?.model == "claude-haiku-5-5")
}

/// Sin la suya, la más reciente leída con las mismas reglas, de cualquier proveedor o modelo.
@Test func reusableFallsBackToTheLatestReadWithTheSameRules() throws {
    let dir = try TempDir()
    let cache = ProposalCache(workspace: try WorkspaceFixture.make(in: dir))
    try cache.save(read("claude-haiku-5-5", rules: "r", at: 1_000))
    try cache.save(read("gpt-5.4-mini", provider: .openai, rules: "r", at: 2_000))
    try cache.save(read("claude-opus-5-5", rules: "otras", at: 3_000))
    try cache.save(read("claude-haiku-5-5", rules: "r", sha: "otro", at: 4_000))

    let found = cache.reusable(sha256: "abc", rulesHash: "r", provider: .anthropic, model: "claude-sonnet-5-5")

    #expect(found?.provider == "openai")
    #expect(found?.model == "gpt-5.4-mini")
    #expect(cache.reusable(sha256: "abc", rulesHash: "nuevas", provider: .anthropic, model: "claude-sonnet-5-5") == nil)
}

/// Una entrada de antes de guardar las reglas solo vale por su clave: no se sabe con qué reglas se leyó.
@Test func anEntryWithoutRulesHashIsOnlyFoundByItsOwnKey() throws {
    let dir = try TempDir()
    let cache = ProposalCache(workspace: try WorkspaceFixture.make(in: dir))
    let key = ProposalCache.key(sha256: "abc", rulesHash: "r", provider: .anthropic, model: "claude-haiku-5-5")
    try cache.save(CacheEntry(key: key, sha256: "abc", rulesHash: nil, fileName: "doc.pdf",
                              outcome: .pending(nil, .encrypted), method: nil, usage: .zero, provider: "anthropic",
                              model: "claude-haiku-5-5", createdAt: Date(timeIntervalSince1970: 1_000)))

    #expect(cache.reusable(sha256: "abc", rulesHash: "r", provider: .anthropic, model: "claude-haiku-5-5")?.key == key)
    #expect(cache.reusable(sha256: "abc", rulesHash: "r", provider: .anthropic, model: "claude-sonnet-5-5") == nil)
}

/// Las entradas de antes no tienen `rulesHash`: se leen igual, con `nil`.
@Test func anOldEntryWithoutRulesHashDecodes() throws {
    let dir = try TempDir()
    let cache = ProposalCache(workspace: try WorkspaceFixture.make(in: dir))
    let old = """
    {
      "createdAt" : "2026-10-01T09:30:00Z",
      "fileName" : "Scan_0042.pdf",
      "key" : "k1",
      "model" : "claude-haiku-5-5",
      "outcome" : { "pending" : { "_1" : { "encrypted" : {} } } },
      "provider" : "anthropic",
      "sha256" : "abc",
      "usage" : { "cacheReadTokens" : 0, "cacheWriteTokens" : 0, "inputTokens" : 100, "outputTokens" : 10 }
    }
    """
    try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
    try Data(old.utf8).write(to: cache.directory.appendingPathComponent("abc_k1.json"))

    let entry = try #require(cache.load(sha256: "abc", key: "k1"))

    #expect(entry.rulesHash == nil)
    #expect(entry.model == "claude-haiku-5-5")
    #expect(entry.outcome == .pending(nil, .encrypted))
    #expect(entry.usage == TokenUsage(inputTokens: 100, outputTokens: 10))
}

// MARK: - La primera que se reutilizaría

private let rejected = ClassificationOutcome.pending(nil, .providerError("HTTP 400"))
private let refused = ClassificationOutcome.pending(nil, .refused)

private func found(_ cache: ProposalCache, _ model: String = "claude-sonnet-5-5") -> CacheEntry? {
    cache.reusable(sha256: "abc", rulesHash: "r", provider: .anthropic, model: model)
}

/// Sonda A: un rechazo del proveedor con la clave exacta no tapa lo que otro modelo leyó bien.
@Test func anExactRejectionDoesNotHideAGoodReadByAnotherModel() throws {
    let dir = try TempDir()
    let cache = ProposalCache(workspace: try WorkspaceFixture.make(in: dir))
    try cache.save(read("claude-haiku-5-5", rules: "r", at: 1_000))
    try cache.save(read("claude-sonnet-5-5", rules: "r", outcome: rejected, at: 2_000))

    #expect(found(cache)?.model == "claude-haiku-5-5")
}

/// Sonda B: la más reciente de otro modelo que se vuelve a leer tampoco tapa una lectura buena más antigua.
@Test func aNewerFailureByAnotherModelDoesNotHideAnOlderGoodRead() throws {
    let dir = try TempDir()
    let cache = ProposalCache(workspace: try WorkspaceFixture.make(in: dir))
    try cache.save(read("claude-haiku-5-5", rules: "r", at: 1_000))
    try cache.save(read("claude-opus-5-5", rules: "r", outcome: rejected, at: 2_000))
    try cache.save(read("gpt-5.4-mini", provider: .openai, rules: "r", outcome: .pending(nil, .paused("rate limited")),
                        at: 3_000))

    #expect(found(cache)?.model == "claude-haiku-5-5")
}

/// Si no hay nada que se reutilice, la exacta aunque se vuelva a leer: la app enseña su estado y ofrece «Reintentar».
@Test func withNothingReusableTheExactFailureIsStillFound() throws {
    let dir = try TempDir()
    let cache = ProposalCache(workspace: try WorkspaceFixture.make(in: dir))
    try cache.save(read("claude-sonnet-5-5", rules: "r", outcome: rejected, at: 1_000))
    try cache.save(read("claude-haiku-5-5", rules: "r", outcome: rejected, at: 2_000))

    #expect(found(cache)?.model == "claude-sonnet-5-5")
    #expect(found(cache, "claude-opus-5-5") == nil)
}

/// Decisión de Daniel: el modelo se negó (`.refused`). Con la clave exacta se respeta; de otro modelo se vuelve a leer.
@Test func aRefusalIsKeptForItsModelButNotForAnother() throws {
    let dir = try TempDir()
    let cache = ProposalCache(workspace: try WorkspaceFixture.make(in: dir))
    try cache.save(read("claude-haiku-5-5", rules: "r", outcome: refused, at: 2_000))
    // Sin otra lectura buena, la negativa del propio modelo se respeta: no se vuelve a pedir.
    #expect(found(cache, "claude-haiku-5-5")?.outcome == refused)

    try cache.save(read("gpt-5.4-mini", provider: .openai, rules: "r", at: 1_000))
    // Con una lectura buena de otro modelo, gana esa: el documento ya está leído y no cuesta nada.
    #expect(found(cache, "claude-haiku-5-5")?.model == "gpt-5.4-mini")
    #expect(found(cache)?.model == "gpt-5.4-mini")
    #expect(PendingReason.refused.readsAgain(fromAnotherModel: true))
    #expect(!PendingReason.refused.readsAgain(fromAnotherModel: false))
    #expect(PendingReason.providerError("x").readsAgain(fromAnotherModel: false))
    #expect(PendingReason.held.readsAgain(fromAnotherModel: false))
    #expect(!PendingReason.encrypted.readsAgain(fromAnotherModel: true))
}

// MARK: - Una sola mirada a la carpeta

/// Cuenta las veces que se lista la carpeta de la caché.
final class ListingCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

/// Con un índice, la búsqueda usa lo que se listó al hacerlo y no vuelve a mirar la carpeta.
@Test func aSearchWithAnIndexDoesNotListTheFolderAgain() throws {
    let dir = try TempDir()
    let cache = ProposalCache(workspace: try WorkspaceFixture.make(in: dir))
    try cache.save(read("claude-haiku-5-5", rules: "r", at: 1_000))
    let listings = ListingCounter()

    try ProposalCache.$onListing.withValue({ listings.increment() }) {
        let index = cache.index()
        try cache.save(read("gpt-5.4-mini", provider: .openai, rules: "r", at: 2_000))    // después del índice
        #expect(cache.reusable(sha256: "abc", rulesHash: "r", provider: .anthropic, model: "claude-sonnet-5-5",
                               in: index)?.model == "claude-haiku-5-5")
        #expect(cache.reusable(sha256: "otro", rulesHash: "r", provider: .anthropic, model: "claude-sonnet-5-5",
                               in: index) == nil)
    }

    #expect(listings.value == 1)
    #expect(found(cache)?.model == "gpt-5.4-mini")                  // sin índice, mira la carpeta de ahora
}
