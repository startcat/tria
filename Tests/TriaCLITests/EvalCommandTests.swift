import Foundation
import Testing
import TriaKit
import TriaTestSupport
@testable import TriaCLI

private func squash(_ text: String) -> String {
    text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
}

/// Perfecto salvo el Modelo 303 (11/12 = 91,7 %).
private func oracle() -> ScriptedProvider {
    ScriptedProvider { request in
        let text = squash(request.userText)
        for document in SyntheticArchive.documents where text.contains(squash(document.text.components(separatedBy: "\n")[1])) {
            let folder = document.filename.hasPrefix("Modelo 303")
                ? "1-Modelos Tributarios/Modelo 111 - IRPF Retenciones" : document.folder
            return ScriptedProvider.proposalJSON(destination: folder, filename: document.filename)
        }
        return ScriptedProvider.proposalJSON(action: "pending", destination: "", filename: "", confidence: "low", doubt: "?")
    }
}

@Test func syntheticEvalPrintsTheAccuracy() async throws {
    let cli = try CLIHarness(provider: oracle())
    #expect(try await cli.run(["eval", "--synthetic", "--yes"]) == 0)
    #expect(cli.terminal.transcript.contains("Acierto de carpeta: 91,7 %"))
    #expect(cli.terminal.transcript.contains("Nombre exacto: 100,0 %"))
    #expect(cli.terminal.transcript.contains("Confianza alta: 12 documentos"))
}

@Test func savesTheReportAndFlagsRegressions() async throws {
    let cli = try CLIHarness(provider: oracle())
    #expect(try await cli.run(["eval", "--synthetic", "--yes", "--out", "informe.json"]) == 0)
    let reportURL = cli.dir.url.appendingPathComponent("informe.json")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var baseline = try decoder.decode(EvalReport.self, from: Data(contentsOf: reportURL))
    baseline.folderAccuracy = 1.0
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(baseline).write(to: cli.dir.url.appendingPathComponent("referencia.json"))

    #expect(try await cli.run(["eval", "--synthetic", "--yes", "--baseline", "referencia.json"]) == 1)
    #expect(cli.terminal.transcript.contains("REGRESIÓN: el acierto de carpeta baja 8,3 puntos"))
}

@Test func evaluatesARealFolderWithExternalRules() async throws {
    let cli = try CLIHarness(provider: ScriptedProvider { _ in
        ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "Factura.txt")
    })
    let archive = try TempDir("tria-archivo")
    for n in 1...3 { try archive.write("7-Facturas/Recibidas/Factura \(n).txt", "Factura número \(n) de luz") }
    let rules = try cli.dir.write("reglas.md", WorkspaceFixture.defaultRules)
    #expect(try await cli.run(["eval", archive.url.path, "--rules", rules.path, "--yes"]) == 0)
    #expect(cli.terminal.transcript.contains("Acierto de carpeta: 100,0 %"))
    #expect(!FileManager.default.fileExists(atPath: archive.url.appendingPathComponent("TRIA.md").path))
}

@Test func evalNeedsAnArchiveAndConfirmation() async throws {
    let cli = try CLIHarness(interactive: false)
    #expect(try await cli.run(["eval"]) == 2)
    #expect(cli.terminal.transcript.contains("Indica la carpeta ya ordenada"))
    #expect(try await cli.run(["eval", "--synthetic"]) == 2)
    #expect(cli.terminal.transcript.contains("Sin terminal interactiva"))
}

@Test func anInterruptedEvalSaysSoAndSkipsTheBaseline() async throws {
    let calls = Counter()
    let cli = try CLIHarness(provider: ScriptedProvider { _ in
        if calls.increment() % 3 == 0 { throw LLMError.rateLimited }
        return ScriptedProvider.proposalJSON(destination: "8-Nominas", filename: "x.pdf")
    })
    #expect(try await cli.run(["eval", "--synthetic", "--yes", "--out", "parcial.json"]) == 0)
    #expect(cli.terminal.transcript.contains("Evaluación incompleta"))
    #expect(try await cli.run(["eval", "--synthetic", "--yes", "--baseline", "parcial.json"]) == 2)
}

/// Un `--baseline` que no se puede leer falla antes de pedir confirmación y de gastar nada en la IA.
@Test func aBadBaselineFailsBeforeSpendingAnything() async throws {
    let calls = Counter()
    let cli = try CLIHarness(provider: ScriptedProvider { _ in
        _ = calls.increment()
        return ScriptedProvider.proposalJSON(destination: "8-Nominas", filename: "x.pdf")
    })
    #expect(try await cli.run(["eval", "--synthetic", "--yes", "--baseline", "no-existe.json"]) == 2)
    #expect(cli.terminal.transcript.contains("No se puede leer el informe de referencia no-existe.json."))
    try cli.dir.write("roto.json", "{ esto no es un informe")
    #expect(try await cli.run(["eval", "--synthetic", "--baseline", "roto.json"]) == 2)
    #expect(cli.terminal.transcript.contains("roto.json no es un informe de `tria eval --out`."))
    #expect(!cli.terminal.transcript.contains("Coste estimado"))
    #expect(!cli.terminal.transcript.contains("Acierto de carpeta"))
    #expect(calls.value == 0)
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() -> Int { lock.withLock { count += 1; return count } }
    var value: Int { lock.withLock { count } }
}
