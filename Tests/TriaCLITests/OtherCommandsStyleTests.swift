import Foundation
import Testing
import TriaTestSupport
@testable import TriaCLI
@testable import TriaKit

private let filler = String(repeating: "Contenido suficiente para no necesitar OCR en este documento. ", count: 3)
private let modelo = ScriptedProvider.proposalJSON(destination: "1-Modelos Tributarios/Modelo 303 - IVA",
                                                   filename: "Modelo 303 - 2023 - 1T.pdf")

private func inboxPDF(_ dir: TempDir, _ name: String) throws {
    let url = dir.url.appendingPathComponent("99-Pendiente/\(name)")
    try FixtureFactory.textPDF(at: url, pages: ["Documento \(name). " + filler])
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: url.path)
}

private func squash(_ text: String) -> String {
    text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
}

/// Perfecto salvo el Modelo 303 (11/12 = 91,7 %), como en `EvalCommandTests`.
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

struct OtherCommandsStyleTests {
    @Test func statusAlignsTheStatesAndPaintsThem() throws {
        let env = try CLIHarness().env
        let items = [StatusItem(file: URL(fileURLWithPath: "/tmp/a.pdf"), relativePath: "99-Pendiente/a.pdf",
                                state: .unprocessed),
                     StatusItem(file: URL(fileURLWithPath: "/tmp/bb.pdf"), relativePath: "99-Pendiente/bb.pdf",
                                state: .duplicate(original: "5-Bancos/b.pdf"))]
        #expect(Presenter.status(items, env, style: .plain) == ["a.pdf:  sin procesar",
                                                                "bb.pdf: duplicado de 5-Bancos/b.pdf"])
        let painted = Presenter.status(items, env, style: Style(.palette256))
        #expect(painted[0] == "a.pdf:  \u{1B}[38;5;244msin procesar\u{1B}[39m")
        #expect(painted[1] == "bb.pdf: \u{1B}[38;5;136mduplicado de 5-Bancos/b.pdf\u{1B}[39m")
    }

    @Test func logAlignsTheCountsAndPaintsTheDate() throws {
        let env = try CLIHarness().env
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let batches = [BatchSummary(id: "b_1", startedAt: date, done: 12, failed: 0, undone: 0, interrupted: 0),
                       BatchSummary(id: "b_2", startedAt: date, done: 3, failed: 1, undone: 10, interrupted: 0)]
        let rows = Presenter.batches(batches, env, style: .plain)
        #expect(rows[0].hasSuffix("· 12 movidos ·  0 deshechos · 0 fallidos"))
        #expect(rows[1].hasSuffix("·  3 movidos · 10 deshechos · 1 fallidos"))
        #expect(Presenter.batches(batches, env, style: Style(.palette256))[0].contains("\u{1B}[38;5;166m"))
    }

    @Test func logShowsEachOperationWithItsSymbol() async throws {
        let cli = try CLIHarness(provider: ScriptedProvider { _ in modelo })
        let ws = try WorkspaceFixture.make(in: cli.dir)
        try inboxPDF(cli.dir, "alta.pdf")
        try await cli.run(["sort", "--auto"])
        let batch = try #require(try Journal(workspace: ws).batches().first?.id)
        #expect(try await cli.run(["log", batch]) == 0)
        #expect(cli.terminal.output.contains(
            "  ✓ 99-Pendiente/alta.pdf → 1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf"))
    }

    @Test func evalShowsItsProgressOnStandardError() async throws {
        let cli = try CLIHarness(provider: oracle())
        #expect(try await cli.run(["eval", "--synthetic", "--yes"]) == 0)
        #expect(cli.terminal.transcript.contains("Evaluando la muestra (12) con claude-haiku-5-5…"))
        #expect(cli.terminal.transcript.contains("✓ 12 documentos evaluados en 0 s"))
        #expect(!cli.terminal.output.contains("evaluados"))
        #expect(!cli.terminal.transcript.contains("  10/12"))
    }

    @Test func evalPaintsTheAccuracyGreenOrRedOnARegression() async throws {
        let cli = try CLIHarness(provider: oracle(), capabilities: .colored)
        #expect(try await cli.run(["eval", "--synthetic", "--yes", "--out", "informe.json"]) == 0)
        #expect(cli.terminal.output.contains("\u{1B}[38;5;65mAcierto de carpeta: 91,7 %\u{1B}[39m"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var baseline = try decoder.decode(EvalReport.self,
                                          from: Data(contentsOf: cli.dir.url.appendingPathComponent("informe.json")))
        baseline.folderAccuracy = 1.0
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(baseline).write(to: cli.dir.url.appendingPathComponent("referencia.json"))
        #expect(try await cli.run(["eval", "--synthetic", "--yes", "--baseline", "referencia.json"]) == 1)
        #expect(cli.terminal.output.contains("\u{1B}[38;5;131mAcierto de carpeta: 91,7 %\u{1B}[39m"))
        #expect(cli.terminal.output.contains("\u{1B}[38;5;131mREGRESIÓN"))
    }

    @Test func learningShowsTheActivityOnStandardError() async throws {
        let cli = try CLIHarness(provider: ScriptedProvider { _ in draftJSON })
        _ = try WorkspaceFixture.make(in: cli.dir)
        try cli.dir.write("7-Facturas/Recibidas/Factura Luz - 2025-01-10.txt", "Factura de luz")
        #expect(try await cli.run(["rules", "learn", "--yes"]) == 0)
        #expect(cli.terminal.transcript.contains("Leyendo la muestra ("))
        #expect(cli.terminal.transcript.contains("✓ Borrador listo en 0 s"))
        #expect(!cli.terminal.output.contains("Borrador listo"))
    }

    @Test func rulesCheckWarningsAreAmberAndTheVerdictGreen() async throws {
        let cli = try CLIHarness(capabilities: .colored)
        let rules = WorkspaceFixture.defaultRules.replacingOccurrences(of: "  - \"7-Facturas/20*/\"",
                                                                       with: "  - \"7-Facturas/20*/\"\n  - \"Archivo Viejo/*\"")
        _ = try WorkspaceFixture.make(in: cli.dir, rules: rules)
        #expect(try await cli.run(["rules", "check"]) == 0)
        #expect(cli.terminal.output.contains(
            "\u{1B}[38;5;136mAviso: el patrón protegido «Archivo Viejo/*» no coincide con ninguna carpeta.\u{1B}[39m"))
        #expect(cli.terminal.output.contains("\u{1B}[38;5;65mTRIA.md es válido.\u{1B}[39m"))
    }
}
