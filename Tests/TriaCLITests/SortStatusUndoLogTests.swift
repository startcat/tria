import Foundation
import Testing
import TriaKit
import TriaTestSupport
@testable import TriaCLI

private let filler = String(repeating: "Contenido suficiente para no necesitar OCR en este documento. ", count: 3)
private let modelo = ScriptedProvider.proposalJSON(destination: "1-Modelos Tributarios/Modelo 303 - IVA",
                                                   filename: "Modelo 303 - 2023 - 1T.pdf")
private let medium = ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "Factura Dudosa.pdf",
                                                   confidence: "medium", doubt: "Proveedor poco legible")

private func inboxPDF(_ dir: TempDir, _ name: String) throws {
    let url = dir.url.appendingPathComponent("99-Pendiente/\(name)")
    try FixtureFactory.textPDF(at: url, pages: ["Documento \(name). " + filler])
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: url.path)
}

private func answering(_ answers: [String: String], suggestion: String? = nil,
                       model: String = "claude-haiku-5-5") -> ScriptedProvider {
    ScriptedProvider(model: model) { request in
        if request.schemaName == "tria_rule_suggestion", let suggestion { return suggestion }
        for (name, answer) in answers where request.userText.contains("Original file name: \(name)\n") { return answer }
        return ScriptedProvider.proposalJSON(action: "pending", destination: "", filename: "", confidence: "low", doubt: "?")
    }
}

private func exists(_ cli: CLIHarness, _ path: String) -> Bool {
    FileManager.default.fileExists(atPath: cli.dir.url.appendingPathComponent(path).path)
}

@Test func autoAppliesHighConfidenceAndReportsWhatIsLeft() async throws {
    let cli = try CLIHarness(provider: answering(["alta.pdf": modelo, "media.pdf": medium]))
    _ = try WorkspaceFixture.make(in: cli.dir)
    try inboxPDF(cli.dir, "alta.pdf")
    try inboxPDF(cli.dir, "media.pdf")
    #expect(try await cli.run(["sort", "--auto"]) == 1)
    #expect(exists(cli, "1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf"))
    #expect(exists(cli, "99-Pendiente/media.pdf"))
    #expect(cli.terminal.transcript.contains("Movidos: 1"))
    #expect(cli.terminal.transcript.contains("Queda 1 pendiente en la bandeja."))
    #expect(cli.terminal.transcript.contains("Duda: Proveedor poco legible"))
}

@Test func dryRunOnlyProposes() async throws {
    let cli = try CLIHarness(provider: answering(["alta.pdf": modelo]))
    _ = try WorkspaceFixture.make(in: cli.dir)
    try inboxPDF(cli.dir, "alta.pdf")
    #expect(try await cli.run(["sort", "--dry-run"]) == 0)
    #expect(exists(cli, "99-Pendiente/alta.pdf"))
    #expect(cli.terminal.transcript.contains("→ 1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf"))
    #expect(cli.terminal.transcript.contains("Confianza alta"))
}

@Test func showPromptPrintsWhatIsSent() async throws {
    let cli = try CLIHarness(provider: answering(["alta.pdf": modelo]))
    _ = try WorkspaceFixture.make(in: cli.dir)
    try inboxPDF(cli.dir, "alta.pdf")
    #expect(try await cli.run(["sort", "--dry-run", "--show-prompt"]) == 0)
    #expect(cli.terminal.transcript.contains("=== context (cached) ==="))
    #expect(cli.terminal.transcript.contains("<<<DOCUMENT"))
}

/// La línea «Analizando…» cita la bandeja de TRIA.md y se limpia; lo que se envía se enseña tal cual.
@Test func showPromptCleansTheAnalysingLineButNotWhatIsSent() async throws {
    let cli = try CLIHarness(provider: answering(["alta.pdf": modelo]))
    let rules = WorkspaceFixture.defaultRules.replacingOccurrences(of: "inbox: 99-Pendiente",
                                                                   with: "inbox: \"99\\tPendiente\"")
    _ = try WorkspaceFixture.make(in: cli.dir, rules: rules)
    let url = cli.dir.url.appendingPathComponent("99\tPendiente/alta.pdf")
    try FixtureFactory.textPDF(at: url, pages: ["Documento alta.pdf. " + filler])
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: url.path)
    #expect(try await cli.run(["sort", "--dry-run", "--show-prompt"]) == 0)
    #expect(cli.terminal.output.contains("Analizando 1 documentos de 99 Pendiente…"))
    #expect(!cli.terminal.output.contains("99\tPendiente…"))
    #expect(cli.terminal.output.contains("<<<DOCUMENT"))
}

/// Un error del proveedor al pensar la regla sale por la salida de errores en una línea y sin órdenes para el terminal.
@Test func anErrorThatQuotesTheProviderShowsNoControlCharacters() async throws {
    let wrong = ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "Factura AutoRent.pdf",
                                              confidence: "medium", doubt: "¿Factura o contrato?")
    let provider = ScriptedProvider { request in
        if request.schemaName == "tria_rule_suggestion" { throw LLMError.quotaExceeded("Sin saldo\n\u{1B}[2J") }
        return wrong
    }
    let cli = try CLIHarness(provider: provider,
                             answers: ["r", "e", "2-Contratos/Renting", "Contrato Renting AutoRent - 2024-09.pdf"])
    _ = try WorkspaceFixture.make(in: cli.dir, folders: WorkspaceFixture.defaultFolders + ["2-Contratos"])
    try inboxPDF(cli.dir, "scan.pdf")
    #expect(try await cli.run(["sort"]) == 0)
    #expect(exists(cli, "2-Contratos/Renting/Contrato Renting AutoRent - 2024-09.pdf"))
    #expect(cli.terminal.transcript.contains("Tu cuenta del proveedor no tiene saldo o cuota: Sin saldo  [2J"))
    #expect(!cli.terminal.transcript.contains("\u{1B}"))
}

/// Una key sin workspace para la lectura y el aviso sale una vez, con lo que hay que hacer.
@Test func aKeyWithoutWorkspaceExplainsWhatToDo() async throws {
    let cli = try CLIHarness(provider: ScriptedProvider { _ in throw LLMError.keyWithoutWorkspace })
    _ = try WorkspaceFixture.make(in: cli.dir)
    try inboxPDF(cli.dir, "a.pdf")
    try inboxPDF(cli.dir, "b.pdf")
    _ = try? await cli.run(["sort", "--auto"])
    let aviso = "Esta clave de Anthropic no pertenece a ningún workspace."
    #expect(cli.terminal.transcript.contains(aviso))
    #expect(cli.terminal.transcript.contains("tria config --set-key"))
    #expect(cli.terminal.transcript.components(separatedBy: aviso).count == 2)
}

@Test func reviewingWithAnEditAppliesItAndOffersARule() async throws {
    let wrong = ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "Factura AutoRent.pdf",
                                              confidence: "medium", doubt: "¿Factura o contrato?")
    let rule = #"{"section":"Casos especiales","rule":"Los contratos de renting van a 2-Contratos/Renting."}"#
    let cli = try CLIHarness(provider: answering(["scan.pdf": wrong], suggestion: rule),
                             answers: ["r", "e", "2-Contratos/Renting", "Contrato Renting AutoRent - 2024-09.pdf", "a"])
    let ws = try WorkspaceFixture.make(in: cli.dir, folders: WorkspaceFixture.defaultFolders + ["2-Contratos"])
    try inboxPDF(cli.dir, "scan.pdf")
    #expect(try await cli.run(["sort"]) == 0)
    #expect(exists(cli, "2-Contratos/Renting/Contrato Renting AutoRent - 2024-09.pdf"))
    #expect(cli.terminal.transcript.contains("+ - Los contratos de renting van a 2-Contratos/Renting."))
    #expect(try ws.reloaded().rules.body.contains("## Casos especiales\n\n- Los contratos de renting van a 2-Contratos/Renting."))
}

@Test func jsonOutputIsMachineReadable() async throws {
    let cli = try CLIHarness(provider: answering(["alta.pdf": modelo]))
    _ = try WorkspaceFixture.make(in: cli.dir)
    try inboxPDF(cli.dir, "alta.pdf")
    #expect(try await cli.run(["sort", "--auto", "--json"]) == 0)
    let object = try JSONSerialization.jsonObject(with: Data(cli.terminal.transcript.utf8)) as? [String: Any]
    #expect((object?["applied"] as? [Any])?.count == 1)
    #expect((object?["items"] as? [[String: Any]])?.first?["status"] as? String == "proposal")
}

@Test func refusesToPromptWithoutATerminal() async throws {
    let cli = try CLIHarness(interactive: false)
    _ = try WorkspaceFixture.make(in: cli.dir)
    #expect(try await cli.run(["sort"]) == 2)
    #expect(cli.terminal.transcript.contains("Sin terminal interactiva"))
}

@Test func emptyInboxIsFineAndLockedWorkspaceIsNot() async throws {
    let cli = try CLIHarness()
    let ws = try WorkspaceFixture.make(in: cli.dir)
    #expect(try await cli.run(["sort", "--auto"]) == 0)
    #expect(cli.terminal.transcript.contains("La bandeja está vacía."))
    let lock = try WorkspaceLock.acquire(ws)
    #expect(try await cli.run(["sort", "--auto"]) == 2)
    #expect(cli.terminal.transcript.contains("Otro proceso está ordenando"))
    lock.release()
}

@Test func statusLogAndUndoFollowASort() async throws {
    let cli = try CLIHarness(provider: answering(["alta.pdf": modelo, "media.pdf": medium]))
    _ = try WorkspaceFixture.make(in: cli.dir)
    try inboxPDF(cli.dir, "alta.pdf")
    try inboxPDF(cli.dir, "media.pdf")
    try await cli.run(["sort", "--auto"])

    #expect(try await cli.run(["status"]) == 0)
    #expect(cli.terminal.transcript.contains("media.pdf: propuesta: 7-Facturas/Recibidas/Factura Dudosa.pdf (confianza media)"))
    #expect(try await cli.run(["log"]) == 0)
    #expect(cli.terminal.transcript.contains("1 movidos · 0 deshechos · 0 fallidos"))
    #expect(try await cli.run(["undo"]) == 0)
    #expect(exists(cli, "99-Pendiente/alta.pdf"))
    #expect(cli.terminal.transcript.contains("Restaurados: 1 · omitidos: 0."))
    #expect(try await cli.run(["undo"]) == 0)
    #expect(cli.terminal.transcript.contains("No hay nada que deshacer."))
}

@Test func undoExplainsSkippedUntrustworthyEntries() async throws {
    let cli = try CLIHarness()
    let ws = try WorkspaceFixture.make(in: cli.dir)
    try cli.dir.write("7-Facturas/Recibidas/plantado.pdf", "x")
    for state in [JournalEvent.State.intent, .done] {
        try Journal(workspace: ws).append(JournalEvent(id: "op_x", batch: "b_x", op: .move, state: state,
                                                       from: "../fuera.pdf", to: "7-Facturas/Recibidas/plantado.pdf",
                                                       sha256: Hashing.sha256("x")))
    }
    #expect(try await cli.run(["undo"]) == 0)
    #expect(cli.terminal.transcript.contains("7-Facturas/Recibidas/plantado.pdf: el registro no es fiable"))
}

@Test func autoSaysWhyAnUndoneDocumentIsLeftAlone() async throws {
    let cli = try CLIHarness(provider: answering(["alta.pdf": modelo]))
    _ = try WorkspaceFixture.make(in: cli.dir)
    try inboxPDF(cli.dir, "alta.pdf")
    try await cli.run(["sort", "--auto"])
    try await cli.run(["undo"])
    #expect(try await cli.run(["sort", "--auto"]) == 1)
    #expect(cli.terminal.transcript.contains("Ya lo deshiciste una vez"))
    #expect(exists(cli, "99-Pendiente/alta.pdf"))
}

@Test func pressingEnterOnASuggestedRuleKeepsItForLater() async throws {   // spec §7.3
    let wrong = ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "Factura AutoRent.pdf",
                                              confidence: "medium", doubt: "¿Factura o contrato?")
    let rule = #"{"section":"Casos especiales","rule":"Los contratos de renting van a 2-Contratos/Renting."}"#
    let cli = try CLIHarness(provider: answering(["scan.pdf": wrong], suggestion: rule),
                             answers: ["r", "e", "2-Contratos/Renting", "Contrato Renting AutoRent - 2024-09.pdf", ""])
    let ws = try WorkspaceFixture.make(in: cli.dir, folders: WorkspaceFixture.defaultFolders + ["2-Contratos"])
    try inboxPDF(cli.dir, "scan.pdf")
    #expect(try await cli.run(["sort"]) == 0)
    #expect(try SuggestionStore(workspace: ws).list().map(\.rule) == ["Los contratos de renting van a 2-Contratos/Renting."])
}

@Test func jsonWithShowPromptKeepsStdoutParseable() async throws {
    let cli = try CLIHarness(provider: answering(["alta.pdf": modelo]))
    _ = try WorkspaceFixture.make(in: cli.dir)
    try inboxPDF(cli.dir, "alta.pdf")
    #expect(try await cli.run(["sort", "--dry-run", "--json", "--show-prompt"]) == 0)
    #expect(try JSONSerialization.jsonObject(with: Data(cli.terminal.output.utf8)) is [String: Any])
    #expect(cli.terminal.transcript.contains("<<<DOCUMENT"))
}

@Test func noCacheAsksTheModelAgain() async throws {
    let provider = answering(["alta.pdf": modelo])
    let cli = try CLIHarness(provider: provider)
    _ = try WorkspaceFixture.make(in: cli.dir)
    try inboxPDF(cli.dir, "alta.pdf")
    try await cli.run(["sort", "--dry-run"])
    try await cli.run(["sort", "--dry-run"])
    #expect(await provider.requests.count == 1)
    try await cli.run(["sort", "--dry-run", "--no-cache"])
    #expect(await provider.requests.count == 2)
}

@Test func anEditIsJournaledAsACorrection() async throws {   // spec de la app, §9, pieza 5
    let wrong = ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "Factura Ejemplo.pdf",
                                              confidence: "medium", doubt: "¿Factura o contrato?")
    let rule = #"{"section":"Casos especiales","rule":"Los contratos de renting van a 2-Contratos/Renting."}"#
    let cli = try CLIHarness(provider: answering(["scan.pdf": wrong], suggestion: rule),
                             answers: ["r", "e", "2-Contratos/Renting", "Contrato Renting Ejemplo - 2024-09.pdf", "d"])
    let ws = try WorkspaceFixture.make(in: cli.dir, folders: WorkspaceFixture.defaultFolders + ["2-Contratos"])
    try inboxPDF(cli.dir, "scan.pdf")

    #expect(try await cli.run(["sort"]) == 0)

    let operation = try #require(try Journal(workspace: ws).operations().first)
    #expect(operation.to == "2-Contratos/Renting/Contrato Renting Ejemplo - 2024-09.pdf")
    #expect(operation.corrected)
    #expect(operation.usage == TokenUsage(inputTokens: 100, outputTokens: 10))
    #expect(operation.model == "claude-haiku-5-5")
}

@Test func acceptingAsProposedIsNotACorrection() async throws {
    let cli = try CLIHarness(provider: answering(["alta.pdf": modelo]), answers: ["r", "s"])
    let ws = try WorkspaceFixture.make(in: cli.dir)
    try inboxPDF(cli.dir, "alta.pdf")

    #expect(try await cli.run(["sort"]) == 0)

    let operation = try #require(try Journal(workspace: ws).operations().first)
    #expect(!operation.corrected)
    #expect(operation.usage == TokenUsage(inputTokens: 100, outputTokens: 10))
}

// MARK: - Lo leído con otro modelo

/// Un espacio con `alta.pdf` ya leído con Haiku; el CLI tiene puesto Sonnet.
private func readWithHaiku(_ cli: CLIHarness, _ answers: [String: String]) async throws -> Workspace {
    let ws = try WorkspaceFixture.make(in: cli.dir, folders: WorkspaceFixture.defaultFolders + ["2-Contratos"])
    for name in answers.keys { try inboxPDF(cli.dir, name) }
    _ = try await SortPipeline(workspace: ws, provider: answering(answers)).plan()
    return ws
}

@Test func autoRecordsTheModelThatReadIt() async throws {
    let sonnet = answering([:], model: "claude-sonnet-5-5")
    let cli = try CLIHarness(provider: sonnet)
    let ws = try await readWithHaiku(cli, ["alta.pdf": modelo])

    #expect(try await cli.run(["sort", "--auto"]) == 0)

    #expect(await sonnet.requests.isEmpty)
    #expect(exists(cli, "1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf"))
    #expect(try Journal(workspace: ws).operations().first?.model == "claude-haiku-5-5")
}

@Test func reviewRecordsTheModelThatReadIt() async throws {
    let sonnet = answering([:], model: "claude-sonnet-5-5")
    let cli = try CLIHarness(provider: sonnet, answers: ["r", "s"])
    let ws = try await readWithHaiku(cli, ["alta.pdf": modelo])

    #expect(try await cli.run(["sort"]) == 0)

    #expect(await sonnet.requests.isEmpty)
    #expect(try Journal(workspace: ws).operations().first?.model == "claude-haiku-5-5")
}

@Test func anEditRecordsTheModelThatReadIt() async throws {
    let wrong = ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "Factura Ejemplo.pdf",
                                              confidence: "medium", doubt: "¿Factura o contrato?")
    let rule = #"{"section":"Casos especiales","rule":"Los contratos de renting van a 2-Contratos/Renting."}"#
    let cli = try CLIHarness(provider: answering([:], suggestion: rule, model: "claude-sonnet-5-5"),
                             answers: ["r", "e", "2-Contratos/Renting", "Contrato Renting Ejemplo - 2024-09.pdf", "d"])
    let ws = try await readWithHaiku(cli, ["scan.pdf": wrong])

    #expect(try await cli.run(["sort"]) == 0)

    let operation = try #require(try Journal(workspace: ws).operations().first)
    #expect(operation.corrected)
    #expect(operation.model == "claude-haiku-5-5")
}

@Test func statusCountsWhatAnotherModelRead() async throws {
    let cli = try CLIHarness(provider: answering([:], model: "claude-sonnet-5-5"))
    _ = try await readWithHaiku(cli, ["alta.pdf": modelo])

    #expect(try await cli.run(["status"]) == 0)

    #expect(cli.terminal.transcript.contains(
        "alta.pdf: propuesta: 1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf"))
}
