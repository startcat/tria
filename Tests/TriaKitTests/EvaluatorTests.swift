import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private func squash(_ text: String) -> String {
    text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
}

/// Responde perfecto salvo para el Modelo 303, al que manda a la carpeta del 111.
private func oracle() -> ScriptedProvider {
    ScriptedProvider { request in
        let text = squash(request.userText)
        for document in SyntheticArchive.documents {
            let marker = squash(document.text.components(separatedBy: "\n")[1])
            guard text.contains(marker) else { continue }
            let folder = document.filename.hasPrefix("Modelo 303")
                ? "1-Modelos Tributarios/Modelo 111 - IRPF Retenciones" : document.folder
            return ScriptedProvider.proposalJSON(destination: folder, filename: document.filename)
        }
        return ScriptedProvider.proposalJSON(action: "pending", destination: "", filename: "", confidence: "low", doubt: "?")
    }
}

@Test func similarityBasics() {
    #expect(StringSimilarity.levenshtein("kitten", "sitting") == 3)
    #expect(StringSimilarity.ratio("Factura Luz", "factura luz") == 1)
    #expect(StringSimilarity.ratio("", "") == 1)
    #expect(StringSimilarity.ratio("abcd", "abcx") == 0.75)
}

@Test func syntheticArchivePlacesEveryDocument() throws {
    let dir = try TempDir()
    let ws = try SyntheticArchive.build(at: dir.url)
    #expect(SyntheticArchive.documents.count == 12)
    for document in SyntheticArchive.documents {
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("\(document.folder)/\(document.filename)").path))
    }
    #expect(ws.rules.header.inbox == "99-Pendiente")
}

@Test func planIsDeterministicAndSkipsProtectedAndRootFiles() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    for n in 1...10 { try dir.write("7-Facturas/Recibidas/f\(n).pdf", "f\(n)") }
    try dir.write("7-Facturas/2013/1T/protegida.pdf", "p")
    try dir.write("suelto.pdf", "s")
    let evaluator = Evaluator(provider: ScriptedProvider { _ in "" })
    let a = try evaluator.plan(workspace: ws, options: EvalOptions(sampleSize: 4, seed: 7))
    let b = try evaluator.plan(workspace: ws, options: EvalOptions(sampleSize: 4, seed: 7))
    #expect(a.sample.map(\.relativePath) == b.sample.map(\.relativePath))
    #expect(a.sample.count == 4)
    let all = try evaluator.plan(workspace: ws, options: EvalOptions(sampleSize: 100))
    #expect(all.sample.count == 10)
    #expect(!all.sample.contains { $0.relativePath.contains("2013") || $0.relativePath == "suelto.pdf" })
}

@Test func runScoresAgainstTheRealPlacementWithoutTouchingOriginals() async throws {
    let dir = try TempDir()
    let ws = try SyntheticArchive.build(at: dir.url)
    let before = try ws.archiveFiles().map { ($0.relativePath, try Hashing.sha256(of: $0.url)) }
    let provider = oracle()
    let evaluator = Evaluator(provider: provider)
    let report = try await evaluator.run(try evaluator.plan(workspace: ws), workspace: ws)

    #expect(report.sampleSize == 12)
    #expect(abs(report.folderAccuracy - 11.0 / 12.0) < 0.0001)
    #expect(report.filenameExactRate == 1)
    #expect(report.byConfidence["high"]?.count == 12)
    #expect(report.unreadableCount == 0)
    let after = try ws.archiveFiles().map { ($0.relativePath, try Hashing.sha256(of: $0.url)) }
    #expect(before.map { $0.0 } == after.map { $0.0 } && before.map { $0.1 } == after.map { $0.1 })

    let requests = await provider.requests
    for document in SyntheticArchive.documents {
        #expect(!requests.contains { $0.cachedContext.contains(document.filename) }, "El árbol filtra \(document.filename)")
    }
    #expect(requests.allSatisfy { $0.userText.contains("Original file name: doc_") })
}

@Test func comparisonFlagsRegressions() {
    let base = EvalReport.build(cases: [], provider: "anthropic", model: "m", usage: .zero, date: Date())
    var better = base
    better.folderAccuracy = 0.9
    var worse = base
    worse.folderAccuracy = 0.8
    #expect(!Evaluator.compare(better, baseline: worse).regressed)
    #expect(Evaluator.compare(worse, baseline: better).regressed)
    #expect(abs(Evaluator.compare(worse, baseline: better).folderDelta + 0.1) < 0.0001)
}

@Test func documentsWithoutContentCountAsUnreadable() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("7-Facturas/Recibidas/vacio.txt", "  \n ")
    let provider = ScriptedProvider { _ in ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "vacio.txt") }
    let evaluator = Evaluator(provider: provider)
    let report = try await evaluator.run(try evaluator.plan(workspace: ws), workspace: ws)
    #expect(report.unreadableCount == 1)
    #expect(await provider.requests.isEmpty)
}

/// Cuenta las peticiones y falla a partir de la que se indique.
private final class FailAfter: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let limit: Int
    let error: LLMError
    init(_ limit: Int, _ error: LLMError) { self.limit = limit; self.error = error }
    func next() throws {
        try lock.withLock {
            calls += 1
            if calls > limit { throw error }
        }
    }
}

@Test func anInterruptedRunKeepsThePartialReport() async throws {
    let dir = try TempDir()
    let ws = try SyntheticArchive.build(at: dir.url)
    let gate = FailAfter(3, .rateLimited)
    let provider = ScriptedProvider { _ in
        try gate.next()
        return ScriptedProvider.proposalJSON(destination: "8-Nominas", filename: "x.pdf")
    }
    let evaluator = Evaluator(provider: provider)
    let options = EvalOptions(concurrency: 1)
    let report = try await evaluator.run(try evaluator.plan(workspace: ws, options: options), workspace: ws, options: options)
    #expect(report.cases.count == 3)
    #expect(report.interruption != nil)
}

@Test func aBadKeyBeforeAnyResultStillFails() async throws {
    let dir = try TempDir()
    let ws = try SyntheticArchive.build(at: dir.url)
    let evaluator = Evaluator(provider: ScriptedProvider { _ in throw LLMError.invalidKey })
    await #expect(throws: LLMError.invalidKey) {
        try await evaluator.run(try evaluator.plan(workspace: ws), workspace: ws)
    }
}

@Test func theSyntheticArchiveKnowsItsOwner() throws {
    let dir = try TempDir()
    let ws = try SyntheticArchive.build(at: dir.url)
    #expect(ws.profile?.profile.name == "EMPRESA EJEMPLO SL")
    #expect(ws.profile?.profile.taxID == "B00000000")
    #expect(try !ws.archiveFiles().contains { $0.relativePath == "PERFIL.md" })
}
