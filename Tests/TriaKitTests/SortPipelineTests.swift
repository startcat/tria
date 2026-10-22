import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private let filler = String(repeating: "Contenido suficiente para no necesitar OCR en este documento. ", count: 3)

@discardableResult
private func inboxPDF(_ dir: TempDir, _ name: String, _ text: String) throws -> URL {
    let url = dir.url.appendingPathComponent("99-Pendiente/\(name)")
    try FixtureFactory.textPDF(at: url, pages: [text + " " + filler])
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: url.path)
    return url
}

private func scripted(_ answers: [String: String], id: ProviderID = .anthropic,
                      model: String = "claude-haiku-5-5") -> ScriptedProvider {
    ScriptedProvider(id: id, model: model) { request in
        for (name, answer) in answers where request.userText.contains("Original file name: \(name)\n") { return answer }
        return ScriptedProvider.proposalJSON(action: "pending", destination: "", filename: "", confidence: "low", doubt: "?")
    }
}

private let modelo = ScriptedProvider.proposalJSON(destination: "1-Modelos Tributarios/Modelo 303 - IVA",
                                                   filename: "Modelo 303 - 2023 - 1T.pdf")

@Test func planMixesProposalsDuplicatesAndPendings() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303 primer trimestre 2023")
    try inboxPDF(dir, "b.pdf", "Documento ambiguo")
    let archived = dir.url.appendingPathComponent("7-Facturas/Recibidas/Factura Luz.pdf")
    try FixtureFactory.textPDF(at: archived, pages: ["Factura luz " + filler])
    let dup = dir.url.appendingPathComponent("99-Pendiente/dup.pdf")
    try FileManager.default.copyItem(at: archived, to: dup)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: dup.path)
    let broken = try dir.write("99-Pendiente/roto.pdf", "no es un pdf")
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: broken.path)

    let plan = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    let byName = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.file.lastPathComponent, $0.kind) })

    guard case .proposal(_, let action)? = byName["a.pdf"] else { Issue.record("a.pdf"); return }
    #expect(action == FilingAction(kind: .file, source: "99-Pendiente/a.pdf",
                                   destination: "1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf"))
    guard case .pending(_, .modelDoubt)? = byName["b.pdf"] else { Issue.record("b.pdf"); return }
    guard case .duplicate(let original, let dupAction)? = byName["dup.pdf"] else { Issue.record("dup.pdf"); return }
    #expect(original == "7-Facturas/Recibidas/Factura Luz.pdf")
    #expect(dupAction.destination == "98-Duplicados/dup.pdf")
    guard case .pending(nil, .unreadable)? = byName["roto.pdf"] else { Issue.record("roto.pdf"); return }
    #expect(plan.usage.inputTokens == 200)
    #expect(plan.model == "claude-haiku-5-5")
}

@Test func sameDestinationInOnePlanGetsASuffix() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "c.pdf", "Modelo 303 copia uno")
    try inboxPDF(dir, "d.pdf", "Modelo 303 copia dos")
    let plan = try await SortPipeline(workspace: ws, provider: scripted(["c.pdf": modelo, "d.pdf": modelo])).plan()
    let destinations = plan.items.compactMap { item -> String? in
        if case .proposal(_, let action) = item.kind { return action.destination }
        return nil
    }
    #expect(destinations.sorted() == ["1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T (2).pdf",
                                      "1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf"])
}

@Test func cacheAvoidsRepeatedCallsUntilRulesChange() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    let provider = scripted(["a.pdf": modelo])
    _ = try await SortPipeline(workspace: ws, provider: provider).plan()
    _ = try await SortPipeline(workspace: ws, provider: provider).plan()
    #expect(await provider.requests.count == 1)

    try (WorkspaceFixture.defaultRules + "\n- Regla nueva.\n").write(to: ws.rulesURL, atomically: true, encoding: .utf8)
    _ = try await SortPipeline(workspace: try ws.reloaded(), provider: provider).plan()
    #expect(await provider.requests.count == 2)
}

@Test func transientErrorPausesTheRestOfTheBatch() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    for name in ["a.pdf", "b.pdf", "c.pdf"] { try inboxPDF(dir, name, "Documento \(name)") }
    let provider = ScriptedProvider { _ in throw LLMError.rateLimited }
    let plan = try await SortPipeline(workspace: ws, provider: provider, concurrency: 1).plan()
    #expect(plan.interruption == .rateLimited)
    #expect(await provider.requests.count == 1)
    #expect(plan.items.allSatisfy { if case .pending(nil, .paused) = $0.kind { return true }; return false })
}

@Test func fatalErrorsAbortThePlan() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    await #expect(throws: LLMError.invalidKey) {
        try await SortPipeline(workspace: ws, provider: ScriptedProvider { _ in throw LLMError.invalidKey }).plan()
    }
}

/// Una key sin workspace también para la lectura, y no se guarda como resultado del documento.
@Test func aKeyWithoutWorkspaceAbortsThePlan() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    await #expect(throws: LLMError.keyWithoutWorkspace) {
        try await SortPipeline(workspace: ws, provider: ScriptedProvider { _ in throw LLMError.keyWithoutWorkspace }).plan()
    }
}

@Test func automaticModeAppliesOnlyHighConfidenceAndDuplicates() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "alta.pdf", "Modelo 303")
    try inboxPDF(dir, "media.pdf", "Factura dudosa")
    let medium = ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "Factura.pdf",
                                               confidence: "medium", doubt: "Proveedor poco legible")
    let pipeline = SortPipeline(workspace: ws, provider: scripted(["alta.pdf": modelo, "media.pdf": medium]))
    let plan = try await pipeline.plan()
    let automatic = SortPipeline.automaticItems(plan)
    #expect(automatic.map(\.action.source) == ["99-Pendiente/alta.pdf"])
    #expect(automatic.first?.provider == "anthropic")

    let report = pipeline.apply(automatic)
    #expect(report.applied.count == 1)
    let status = try SortPipeline.status(workspace: ws)
    #expect(status.map(\.relativePath) == ["99-Pendiente/media.pdf"])
    guard case .proposed(let proposal, _) = status.first?.state else { Issue.record("status"); return }
    #expect(proposal.confidence == .medium)
}

@Test func reportsFilesInUseAndReconcilesInterruptedOperations() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/copiandose.pdf", "x")
    try dir.write("7-Facturas/Recibidas/llegado.pdf", "y")
    try Journal(workspace: ws).append(JournalEvent(id: "op_1", batch: "b_0", op: .move, state: .intent,
                                                   from: "99-Pendiente/llegado.pdf", to: "7-Facturas/Recibidas/llegado.pdf"))
    let plan = try await SortPipeline(workspace: ws, provider: scripted([:])).plan()
    #expect(plan.inUse.map(\.lastPathComponent) == ["copiandose.pdf"])
    #expect(plan.reconciled == [ReconcileResult(id: "op_1", state: .done)])
    #expect(plan.items.isEmpty)
}

private func kinds(_ plan: SortPlan) -> [String: SortItem.Kind] {
    Dictionary(uniqueKeysWithValues: plan.items.map { ($0.file.lastPathComponent, $0.kind) })
}

@Test func unreadableInboxFileStaysPendingAndTheBatchGoesOn() async throws {   // spec §10
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    let locked = try inboxPDF(dir, "bloqueado.pdf", "Secreto")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path); _ = dir }
    let plan = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    guard case .proposal? = kinds(plan)["a.pdf"] else { Issue.record("a.pdf"); return }
    guard case .pending(nil, .unreadable)? = kinds(plan)["bloqueado.pdf"] else { Issue.record("bloqueado.pdf"); return }
}

@Test func unreadableArchiveFolderDoesNotBlockSorting() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    try dir.write("Privado/nota.pdf", "nota")
    let locked = dir.url.appendingPathComponent("Privado")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path); _ = dir }
    let plan = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    guard case .proposal? = kinds(plan)["a.pdf"] else { Issue.record("\(plan.items)"); return }
}

@Test func aDocumentRejectedByTheProviderStaysPending() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    try inboxPDF(dir, "grande.pdf", "Documento rechazado")
    let provider = ScriptedProvider { request in
        if request.userText.contains("Original file name: grande.pdf\n") {
            throw LLMError.rejected(status: 400, message: "image too large")
        }
        return modelo
    }
    let plan = try await SortPipeline(workspace: ws, provider: provider).plan()
    guard case .proposal? = kinds(plan)["a.pdf"] else { Issue.record("a.pdf"); return }
    guard case .pending(nil, .providerError(let message))? = kinds(plan)["grande.pdf"] else { Issue.record("grande.pdf"); return }
    #expect(message.contains("image too large"))
}

@Test func documentsWithoutReadableContentAreNotSentToTheModel() async throws {   // spec §3, principio 1
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let blank = try dir.write("99-Pendiente/vacio.txt", "   \n\t  \n")
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: blank.path)
    let provider = scripted([:])
    let plan = try await SortPipeline(workspace: ws, provider: provider).plan()
    guard case .pending(nil, .unreadable)? = plan.items.first?.kind else { Issue.record("\(plan.items)"); return }
    #expect(await provider.requests.isEmpty)
}

@Test func automaticModeRespectsAnUndo() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "alta.pdf", "Modelo 303")
    let pipeline = SortPipeline(workspace: ws, provider: scripted(["alta.pdf": modelo]))
    _ = pipeline.apply(SortPipeline.automaticItems(try await pipeline.plan()))
    _ = try Undoer(workspace: ws).undoLast()
    let again = try await pipeline.plan()
    #expect(again.items.count == 1)
    #expect(SortPipeline.automaticItems(again).isEmpty)
}

@Test func statusShowsOnlyWhatTheNextSortWouldReuse() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "alta.pdf", "Modelo 303")
    let provider = scripted(["alta.pdf": modelo])
    _ = try await SortPipeline(workspace: ws, provider: provider).plan()
    try (WorkspaceFixture.defaultRules + "\n- Regla nueva.\n").write(to: ws.rulesURL, atomically: true, encoding: .utf8)
    let changed = try ws.reloaded()
    let status = try SortPipeline.status(workspace: changed, provider: provider.id, model: provider.model)
    #expect(status.first?.state == .unprocessed)
}

@Test func statusCarriesTheHashItWasReadWithAndWhetherItWasUndone() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let alta = try inboxPDF(dir, "alta.pdf", "Modelo 303")
    let otro = try inboxPDF(dir, "otro.pdf", "Otro documento")
    let pipeline = SortPipeline(workspace: ws, provider: scripted(["alta.pdf": modelo]))
    _ = pipeline.apply(SortPipeline.automaticItems(try await pipeline.plan()))
    _ = try Undoer(workspace: ws).undoLast()
    try dir.write("99-Pendiente/copiandose.pdf", "x")

    let status = Dictionary(uniqueKeysWithValues: try SortPipeline.status(workspace: ws)
        .map { ($0.file.lastPathComponent, $0) })

    #expect(status["alta.pdf"]?.sha256 == (try Hashing.sha256(of: alta)))
    #expect(status["alta.pdf"]?.undoneBefore == true)
    #expect(status["otro.pdf"]?.sha256 == (try Hashing.sha256(of: otro)))
    #expect(status["otro.pdf"]?.undoneBefore == false)
    #expect(status["copiandose.pdf"]?.state == .inUse)
    #expect(status["copiandose.pdf"]?.sha256 == nil)
    #expect(status["copiandose.pdf"]?.undoneBefore == false)
}

@Test func theProfileTravelsWithEachRequestAndKeysTheCache() async throws {
    let dir = try TempDir()
    var ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303 primer trimestre 2023")
    let provider = scripted(["a.pdf": modelo])
    func state() throws -> StatusItem.State? {
        try SortPipeline.status(workspace: ws, provider: .anthropic, model: "claude-haiku-5-5").first?.state
    }

    _ = try await SortPipeline(workspace: ws, provider: provider).plan()
    guard case .proposed? = try state() else { Issue.record("sin perfil, propuesta en caché"); return }

    ws = try ws.saveProfile(Profile(kind: .sl, name: "EMPRESA EJEMPLO SL", taxID: "B00000000"), language: .es)
    guard case .unprocessed? = try state() else { Issue.record("con perfil, la clave cambia"); return }
    _ = try await SortPipeline(workspace: ws, provider: provider).plan()
    let requests = await provider.requests
    #expect(requests.first?.cachedContext.contains("Owner profile") == false)
    #expect(requests.last?.cachedContext.contains("EMPRESA EJEMPLO SL") == true)

    try FileManager.default.removeItem(at: ws.profileURL)
    ws = try ws.reloaded()
    guard case .proposed? = try state() else { Issue.record("sin perfil, la clave de siempre"); return }
}

@Test func aFreshReadCarriesWhatItCostAndCountsAsSent() async throws {   // spec de la app, §9, pieza 5
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303 primer trimestre 2023")
    try inboxPDF(dir, "b.pdf", "Documento ambiguo")
    let blank = try dir.write("99-Pendiente/vacio.txt", "   \n\t  \n")
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: blank.path)

    let plan = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    let byName = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.file.lastPathComponent, $0) })

    let oneRead = TokenUsage(inputTokens: 100, outputTokens: 10)
    #expect(byName["a.pdf"]?.readUsage == oneRead)
    #expect(byName["a.pdf"]?.fromCache == false)
    #expect(byName["b.pdf"]?.readUsage == oneRead)          // la duda también se envió y se pagó
    #expect(byName["vacio.txt"]?.readUsage == nil)       // no llegó al proveedor
    #expect(plan.sentDocuments == 2)
    #expect(SortPipeline.automaticItems(plan).first?.usage == oneRead)
}

@Test func aCachedProposalCarriesItsOldCostButSendsNothing() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    let provider = scripted(["a.pdf": modelo])
    _ = try await SortPipeline(workspace: ws, provider: provider).plan()

    let again = try await SortPipeline(workspace: ws, provider: provider).plan()

    let item = try #require(again.items.first)
    #expect(item.fromCache)
    #expect(item.readUsage == TokenUsage(inputTokens: 100, outputTokens: 10))
    #expect(again.sentDocuments == 0)
    #expect(again.usage == .zero)
    #expect(SortPipeline.approvedItem(for: item)?.usage == item.readUsage)
    #expect(await provider.requests.count == 1)
}

@Test func whatAPauseLeftUnreadWasNotSent() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    for name in ["a.pdf", "b.pdf"] { try inboxPDF(dir, name, "Documento \(name)") }
    let plan = try await SortPipeline(workspace: ws, provider: ScriptedProvider { _ in throw LLMError.rateLimited },
                                      concurrency: 1).plan()
    #expect(plan.interruption == .rateLimited)
    #expect(plan.items.allSatisfy { $0.readUsage == nil && !$0.fromCache })
    #expect(plan.sentDocuments == 0)
}

@Test func statusCarriesTheCachedCost() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    _ = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    try inboxPDF(dir, "nuevo.pdf", "Otro documento")

    let status = Dictionary(uniqueKeysWithValues: try SortPipeline.status(workspace: ws, provider: .anthropic,
                                                                          model: "claude-haiku-5-5")
        .map { ($0.file.lastPathComponent, $0) })

    #expect(status["a.pdf"]?.readUsage == TokenUsage(inputTokens: 100, outputTokens: 10))
    #expect(status["nuevo.pdf"]?.state == .unprocessed)
    #expect(status["nuevo.pdf"]?.readUsage == nil)
}

// MARK: - Lo leído con otro proveedor o modelo

private let sonnet = "claude-sonnet-5-5"

/// Lo leído con un modelo no se vuelve a leer con otro: sale de la caché, con quien lo leyó.
@Test func whatOneModelReadIsNotReadAgainWithAnother() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    let haiku = scripted(["a.pdf": modelo])
    let first = try await SortPipeline(workspace: ws, provider: haiku).plan()
    let other = scripted(["a.pdf": modelo], model: sonnet)

    let again = try await SortPipeline(workspace: ws, provider: other).plan()

    #expect(await other.requests.isEmpty)
    #expect(kinds(again)["a.pdf"] == kinds(first)["a.pdf"])
    let item = try #require(again.items.first)
    #expect(item.fromCache)
    #expect(item.readUsage == TokenUsage(inputTokens: 100, outputTokens: 10))
    #expect(item.readProvider == "anthropic")
    #expect(item.readModel == "claude-haiku-5-5")
    #expect(again.sentDocuments == 0)
}

/// Tampoco al cambiar de proveedor.
@Test func whatOneProviderReadIsNotReadAgainWithAnother() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    _ = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    let openai = scripted(["a.pdf": modelo], id: .openai, model: "gpt-5.4-mini")

    let again = try await SortPipeline(workspace: ws, provider: openai).plan()

    #expect(await openai.requests.isEmpty)
    #expect(again.items.first?.readProvider == "anthropic")
    #expect(again.items.first?.readModel == "claude-haiku-5-5")
}

@Test func aFreshReadCarriesTheProviderAndModelThatReadIt() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    let blank = try dir.write("99-Pendiente/vacio.txt", "   \n\t  \n")
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: blank.path)

    let plan = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo], model: sonnet)).plan()
    let byName = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.file.lastPathComponent, $0) })

    #expect(byName["a.pdf"]?.readProvider == "anthropic")
    #expect(byName["a.pdf"]?.readModel == sonnet)
    #expect(byName["vacio.txt"]?.readProvider == nil)      // no llegó al proveedor
    #expect(byName["vacio.txt"]?.readModel == nil)
}

@Test func statusWithAnotherModelCountsWhatWasRead() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    _ = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()

    let status = try #require(try SortPipeline.status(workspace: ws, provider: .anthropic, model: sonnet).first)
    let openai = try #require(try SortPipeline.status(workspace: ws, provider: .openai, model: "gpt-5.4-mini").first)

    guard case .proposed = status.state else { Issue.record("\(status.state)"); return }
    #expect(status.readUsage == TokenUsage(inputTokens: 100, outputTokens: 10))
    #expect(status.readProvider == "anthropic")
    #expect(status.readModel == "claude-haiku-5-5")
    guard case .proposed = openai.state else { Issue.record("\(openai.state)"); return }
}

/// Con `TRIA.md` o `PERFIL.md` cambiados, lo leído antes no vale con ningún modelo: se lee otra vez con el actual.
@Test func changedRulesOrProfileAreReadAgainWithTheCurrentModel() async throws {
    let dir = try TempDir()
    var ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    _ = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    let other = scripted(["a.pdf": modelo], model: sonnet)

    try (WorkspaceFixture.defaultRules + "\n- Regla nueva.\n").write(to: ws.rulesURL, atomically: true, encoding: .utf8)
    ws = try ws.reloaded()
    #expect(try SortPipeline.status(workspace: ws, provider: .anthropic, model: sonnet).first?.state == .unprocessed)
    let afterRules = try await SortPipeline(workspace: ws, provider: other).plan()
    #expect(await other.requests.count == 1)
    #expect(afterRules.items.first?.readModel == sonnet)

    ws = try ws.saveProfile(Profile(kind: .sl, name: "EMPRESA EJEMPLO SL", taxID: "B00000000"), language: .es)
    let haiku = scripted(["a.pdf": modelo])
    #expect(try SortPipeline.status(workspace: ws, provider: .anthropic, model: "claude-haiku-5-5").first?.state
            == .unprocessed)
    _ = try await SortPipeline(workspace: ws, provider: haiku).plan()
    #expect(await haiku.requests.count == 1)
}

/// Una entrada de antes de guardar las reglas solo vale para su mismo proveedor y modelo.
@Test func anOldEntryWithoutRulesHashIsNotReusedByAnotherModel() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    let haiku = scripted(["a.pdf": modelo])
    let first = try await SortPipeline(workspace: ws, provider: haiku).plan()
    let cache = ProposalCache(workspace: ws)
    let sha = try #require(first.items.first?.sha256)
    var old = try #require(cache.latest(sha256: sha))
    old.rulesHash = nil                                  // como la guardaba la versión anterior
    try cache.save(old)

    _ = try await SortPipeline(workspace: ws, provider: haiku).plan()
    #expect(await haiku.requests.count == 1)            // la de su misma clave, sí
    guard case .proposed? = try SortPipeline.status(workspace: ws, provider: .anthropic,
                                                    model: "claude-haiku-5-5").first?.state
    else { Issue.record("con su clave, leído"); return }

    #expect(try SortPipeline.status(workspace: ws, provider: .anthropic, model: sonnet).first?.state == .unprocessed)
    let other = scripted(["a.pdf": modelo], model: sonnet)
    _ = try await SortPipeline(workspace: ws, provider: other).plan()
    #expect(await other.requests.count == 1)
}

/// `--no-cache` vuelve a leerlo con el modelo actual.
@Test func withoutTheCacheItIsReadAgainWithTheCurrentModel() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    _ = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    let other = scripted(["a.pdf": modelo], model: sonnet)

    let plan = try await SortPipeline(workspace: ws, provider: other, useCache: false).plan()

    #expect(await other.requests.count == 1)
    #expect(plan.items.first?.fromCache == false)
    #expect(plan.items.first?.readModel == sonnet)
}

/// Lo que el proveedor rechazó con otro modelo no se reutiliza: se vuelve a leer con el actual, como antes. Con su
/// mismo modelo, el estado lo sigue enseñando como rechazado.
@Test func aRejectionByAnotherModelIsReadAgainWithTheCurrentOne() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    _ = try await SortPipeline(workspace: ws, provider: ScriptedProvider { _ in
        throw LLMError.rejected(status: 400, message: "image too large")
    }).plan()

    guard case .pending(nil, .providerError)? = try SortPipeline.status(workspace: ws, provider: .anthropic,
                                                                        model: "claude-haiku-5-5").first?.state
    else { Issue.record("con su modelo, rechazado"); return }
    #expect(try SortPipeline.status(workspace: ws, provider: .anthropic, model: sonnet).first?.state == .unprocessed)

    let other = scripted(["a.pdf": modelo], model: sonnet)
    let plan = try await SortPipeline(workspace: ws, provider: other).plan()
    #expect(await other.requests.count == 1)
    guard case .proposal? = kinds(plan)["a.pdf"] else { Issue.record("\(plan.items)"); return }
}

/// Al archivar lo que leyó un modelo con otro puesto, el registro anota el que lo leyó.
@Test func theJournalRecordsTheModelThatReadIt() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    _ = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    try inboxPDF(dir, "b.pdf", "Modelo 303 segundo trimestre")
    let segundo = ScriptedProvider.proposalJSON(destination: "1-Modelos Tributarios/Modelo 303 - IVA",
                                                filename: "Modelo 303 - 2023 - 2T.pdf")
    let pipeline = SortPipeline(workspace: ws, provider: scripted(["b.pdf": segundo], id: .openai, model: "gpt-5.4-mini"))

    let plan = try await pipeline.plan()
    let automatic = SortPipeline.automaticItems(plan)
    _ = pipeline.apply(automatic)

    let models = Dictionary(uniqueKeysWithValues: try Journal(workspace: ws).operations().map { ($0.from, $0.model) })
    #expect(models["99-Pendiente/a.pdf"] == "claude-haiku-5-5")
    #expect(models["99-Pendiente/b.pdf"] == "gpt-5.4-mini")
    let providers = Dictionary(try Journal(workspace: ws).events().map { ($0.from, $0.provider) },
                               uniquingKeysWith: { first, _ in first })
    #expect(providers["99-Pendiente/a.pdf"] == "anthropic")
    #expect(providers["99-Pendiente/b.pdf"] == "openai")
}

/// Las entradas nuevas guardan con qué reglas se leyó el documento.
@Test func newCacheEntriesKeepTheRulesTheyWereReadWith() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    let plan = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()

    let sha = try #require(plan.items.first?.sha256)
    let entry = try #require(ProposalCache(workspace: ws).latest(sha256: sha))

    #expect(entry.rulesHash == ws.contextHash)
}

// MARK: - La primera que se reutilizaría (sondas de la revisión)

private func rejecting(model: String) -> ScriptedProvider {
    ScriptedProvider(model: model) { _ in throw LLMError.rejected(status: 400, message: "image too large") }
}

private func refusing(model: String = "claude-haiku-5-5") -> ScriptedProvider {
    ScriptedProvider(model: model) { _ in throw LLMError.refused }
}

/// Sonda A: Sonnet lo rechaza, Haiku lo lee bien y se vuelve a Sonnet. El rechazo de Sonnet no tapa lo que leyó Haiku.
@Test func anExactRejectionDoesNotHideWhatAnotherModelReadWell() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    _ = try await SortPipeline(workspace: ws, provider: rejecting(model: sonnet)).plan()
    _ = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()

    let status = try #require(try SortPipeline.status(workspace: ws, provider: .anthropic, model: sonnet).first)
    guard case .proposed = status.state else { Issue.record("\(status.state)"); return }
    #expect(status.readModel == "claude-haiku-5-5")
    let back = scripted(["a.pdf": modelo], model: sonnet)
    let plan = try await SortPipeline(workspace: ws, provider: back).plan()
    #expect(await back.requests.isEmpty)
    #expect(plan.items.first?.readModel == "claude-haiku-5-5")
}

/// Sonda B: un rechazo más reciente de otro modelo (tras un `--no-cache` con Opus) no tapa la lectura buena de Haiku.
@Test func aNewerRejectionByAnotherModelDoesNotHideAnOlderGoodRead() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    let first = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    // La caché guarda la fecha al segundo: la lectura de Haiku, un minuto antes, para que la de Opus sea la más reciente.
    let cache = ProposalCache(workspace: ws)
    let sha = try #require(first.items.first?.sha256)
    var haiku = try #require(cache.latest(sha256: sha))
    haiku.createdAt.addTimeInterval(-60)
    try cache.save(haiku)
    _ = try await SortPipeline(workspace: ws, provider: rejecting(model: "claude-opus-5-5"), useCache: false).plan()
    #expect(cache.latest(sha256: haiku.sha256)?.model == "claude-opus-5-5")

    let status = try #require(try SortPipeline.status(workspace: ws, provider: .anthropic, model: sonnet).first)
    guard case .proposed = status.state else { Issue.record("\(status.state)"); return }
    let other = scripted(["a.pdf": modelo], model: sonnet)
    let plan = try await SortPipeline(workspace: ws, provider: other).plan()
    #expect(await other.requests.isEmpty)
    #expect(plan.items.first?.readModel == "claude-haiku-5-5")
}

/// Decisión de Daniel: si otro modelo se negó a clasificarlo, el actual lo intenta una vez.
@Test func aRefusalByAnotherModelIsReadOnceWithTheCurrentOne() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    _ = try await SortPipeline(workspace: ws, provider: refusing()).plan()
    #expect(try SortPipeline.status(workspace: ws, provider: .anthropic, model: sonnet).first?.state == .unprocessed)

    let other = scripted(["a.pdf": modelo], model: sonnet)
    let plan = try await SortPipeline(workspace: ws, provider: other).plan()
    _ = try await SortPipeline(workspace: ws, provider: other).plan()

    #expect(await other.requests.count == 1)
    guard case .proposal? = kinds(plan)["a.pdf"] else { Issue.record("\(plan.items)"); return }
    #expect(plan.items.first?.readModel == sonnet)
}

/// La negativa del mismo modelo se respeta: no se vuelve a pedir en cada `sort` ni en cada refresco.
@Test func aRefusalByTheSameModelIsNotReadAgain() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    let haiku = refusing()
    _ = try await SortPipeline(workspace: ws, provider: haiku).plan()

    let again = try await SortPipeline(workspace: ws, provider: haiku).plan()

    #expect(await haiku.requests.count == 1)
    guard case .pending(nil, .refused)? = kinds(again)["a.pdf"] else { Issue.record("\(again.items)"); return }
    guard case .pending(nil, .refused)? = try SortPipeline.status(workspace: ws, provider: .anthropic,
                                                                  model: "claude-haiku-5-5").first?.state
    else { Issue.record("estado"); return }
}

/// Sonda D: lo que leyó otro modelo con un destino que ya no vale se vuelve a leer con el actual.
@Test func anotherModelsProposalThatNoLongerValidatesIsReadAgain() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303")
    _ = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    try FileManager.default.removeItem(at: dir.url.appendingPathComponent("1-Modelos Tributarios"))  // carpeta nueva

    #expect(try SortPipeline.status(workspace: ws, provider: .anthropic, model: sonnet).first?.state == .unprocessed)
    let factura = ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "Factura.pdf")
    let other = scripted(["a.pdf": factura], model: sonnet)
    let plan = try await SortPipeline(workspace: ws, provider: other).plan()
    #expect(await other.requests.count == 1)
    #expect(plan.items.first?.readModel == sonnet)
}

// MARK: - Una sola mirada a la caché

/// `status` y `plan` listan la carpeta de la caché una vez por llamada, no una por documento.
@Test func statusAndPlanListTheCacheOnce() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    for name in ["a.pdf", "b.pdf", "c.pdf"] { try inboxPDF(dir, name, "Documento \(name)") }
    _ = try await SortPipeline(workspace: ws, provider: scripted([:])).plan()
    try inboxPDF(dir, "nuevo.pdf", "Documento nuevo")
    let listings = ListingCounter()

    try ProposalCache.$onListing.withValue({ listings.increment() }) {
        _ = try SortPipeline.status(workspace: ws, provider: .anthropic, model: sonnet)
    }
    #expect(listings.value == 1)

    let other = scripted([:], model: sonnet)
    try await ProposalCache.$onListing.withValue({ listings.increment() }) {
        _ = try await SortPipeline(workspace: ws, provider: other).plan()
    }
    #expect(listings.value == 2)
    #expect(await other.requests.count == 1)                 // solo el nuevo
}

/// La fecha de la lectura sale de la misma entrada que `status` ha elegido.
@Test func statusCarriesWhenItWasRead() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let a = try inboxPDF(dir, "a.pdf", "Modelo 303")
    _ = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    try inboxPDF(dir, "nuevo.pdf", "Documento nuevo")
    let entry = try #require(ProposalCache(workspace: ws).latest(sha256: try Hashing.sha256(of: a)))

    let status = Dictionary(uniqueKeysWithValues: try SortPipeline.status(workspace: ws, provider: .anthropic,
                                                                          model: sonnet)
        .map { ($0.file.lastPathComponent, $0) })

    #expect(status["a.pdf"]?.readAt == entry.createdAt)
    #expect(status["nuevo.pdf"]?.readAt == nil)
}

// MARK: - Gancho admit (documentos en espera)

private actor AdmitLog {
    private(set) var asked: [String] = []
    func record(_ sha: String) { asked.append(sha) }
}

private func sha(of url: URL, in ws: Workspace) throws -> String {
    // Lo mismo que calcula el motor: la huella del escaneo de duplicados.
    let hash = try DuplicateFinder(workspace: ws).scan([url]).hashes[url]
    return try #require(hash)
}

@Test func theGateIsAskedOnlyForDocumentsThatWouldBeSent() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let nuevos = [try inboxPDF(dir, "a.pdf", "Modelo 303 uno"), try inboxPDF(dir, "b.pdf", "Modelo 303 dos"),
                  try inboxPDF(dir, "c.pdf", "Modelo 303 tres")]
    let archived = dir.url.appendingPathComponent("7-Facturas/Recibidas/Factura Luz.pdf")
    try FixtureFactory.textPDF(at: archived, pages: ["Factura luz " + filler])
    let dup = dir.url.appendingPathComponent("99-Pendiente/dup.pdf")
    try FileManager.default.copyItem(at: archived, to: dup)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: dup.path)
    let blank = try dir.write("99-Pendiente/vacio.txt", "   \n\t  \n")
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: blank.path)
    let log = AdmitLog()
    let plan = try await SortPipeline(workspace: ws, provider: scripted([:]), admit: { await log.record($0); return true })
        .plan()
    let asked = await log.asked
    #expect(asked.count == 3)
    #expect(Set(asked) == Set(try nuevos.map { try sha(of: $0, in: ws) }))
    #expect(plan.heldDocuments == 0)
}

@Test func aHeldDocumentIsNotSentNorCached() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303 uno")
    let b = try inboxPDF(dir, "b.pdf", "Modelo 303 dos")
    let heldSha = try sha(of: b, in: ws)
    let provider = scripted(["a.pdf": modelo, "b.pdf": modelo])
    let plan = try await SortPipeline(workspace: ws, provider: provider, admit: { $0 != heldSha }).plan()
    let held = try #require(plan.items.first { $0.file.lastPathComponent == "b.pdf" })
    guard case .pending(nil, .held) = held.kind else { Issue.record("\(held.kind)"); return }
    #expect(held.readUsage == nil)
    #expect(!held.fromCache)
    #expect(plan.heldDocuments == 1)
    #expect(await provider.requests.allSatisfy { !$0.userText.contains("Original file name: b.pdf\n") })
    #expect(await provider.requests.count == 1)

    let again = try await SortPipeline(workspace: ws, provider: provider).plan()
    let b2 = try #require(again.items.first { $0.file.lastPathComponent == "b.pdf" })
    guard case .proposal = b2.kind else { Issue.record("\(b2.kind)"); return }
    #expect(!b2.fromCache)
    #expect(again.heldDocuments == 0)
}

@Test func withoutAGateEverythingIsSentAsBefore() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303 uno")
    try inboxPDF(dir, "b.pdf", "Modelo 303 dos")
    let provider = scripted(["a.pdf": modelo, "b.pdf": modelo])
    let plan = try await SortPipeline(workspace: ws, provider: provider).plan()
    #expect(plan.heldDocuments == 0)
    #expect(await provider.requests.count == 2)
}

@Test func aCachedDocumentDoesNotAskTheGate() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303 uno")
    try inboxPDF(dir, "b.pdf", "Modelo 303 dos")
    let provider = scripted(["a.pdf": modelo, "b.pdf": modelo])
    _ = try await SortPipeline(workspace: ws, provider: provider).plan()
    let log = AdmitLog()
    let plan = try await SortPipeline(workspace: ws, provider: provider, admit: { await log.record($0); return false }).plan()
    #expect(plan.items.allSatisfy { $0.fromCache })
    #expect(await log.asked.isEmpty)
    #expect(plan.heldDocuments == 0)
}

// MARK: - Un límite del servicio a mitad de lote

/// Proveedor de prueba asíncrono: el handler puede esperar (una lectura lenta) o lanzar.
private actor SlowProvider: LLMProvider {
    nonisolated let id = ProviderID.anthropic
    nonisolated let model = "claude-haiku-5-5"
    private let handler: @Sendable (LLMRequest) async throws -> String
    private(set) var requests: [LLMRequest] = []

    init(handler: @escaping @Sendable (LLMRequest) async throws -> String) {
        self.handler = handler
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        requests.append(request)
        return LLMResponse(text: try await handler(request), usage: TokenUsage(inputTokens: 100, outputTokens: 10),
                           model: model)
    }
}

/// Una señal que se abre tras `needed` avisos (`notify`). Esperarla se corta con una cancelación (`Task.sleep` lanza), como se
/// cortaría una petición de red; si no se abre, deja de esperar a los 5 segundos para que la prueba no se cuelgue.
private actor Signal {
    private let needed: Int
    private var count = 0
    var isOpen: Bool { count >= needed }
    init(after needed: Int = 1) { self.needed = needed }
    func notify() { count += 1 }
}

private func wait(for signal: Signal) async throws {
    var waited = 0
    while !(await signal.isOpen), waited < 500 {
        try await Task.sleep(nanoseconds: 10_000_000)
        waited += 1
    }
}

private func names(_ request: LLMRequest, _ name: String) -> Bool {
    request.userText.contains("Original file name: \(name)\n")
}

/// C1 de la revisión final: el saldo se acaba en un documento mientras otros dos se leen. Las dos lecturas en vuelo
/// acaban y se guardan, el limitado queda pendiente sin guardarse, no empieza ninguna lectura más y el plan dice por qué
/// se paró.
@Test func aServiceLimitMidBatchLetsTheReadsInFlightFinish() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let urls = try ["0.pdf", "a.pdf", "b.pdf", "c.pdf", "d.pdf"].map { try inboxPDF(dir, $0, "Modelo 303 \($0)") }
    let limit = LLMError.serviceLimit(TriaAPI.ErrorCode.balanceEmpty.rawValue)
    // 0 es la primera lectura, que calienta la caché de prompts sola; las demás van en paralelo a partir de ahí.
    // El límite llega cuando b y c ya están en el proveedor, y estas lecturas lentas acaban cuando el lote ya tiene el
    // resultado de a: después del límite.
    let inFlight = Signal(after: 2), limited = Signal()
    let provider = SlowProvider { request in
        if names(request, "a.pdf") {
            try await wait(for: inFlight)
            throw limit
        }
        await inFlight.notify()
        try await wait(for: limited)
        return modelo
    }

    let plan = try await SortPipeline(workspace: ws, provider: provider, concurrency: 3).plan { progress in
        if case .document(_, _, "a.pdf") = progress { Task { await limited.notify() } }
    }

    #expect(plan.interruption == limit)
    let byName = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.file.lastPathComponent, $0) })
    let oneRead = TokenUsage(inputTokens: 100, outputTokens: 10)
    for name in ["0.pdf", "b.pdf", "c.pdf"] {
        guard case .proposal? = byName[name]?.kind else { Issue.record("\(name): \(String(describing: byName[name]))"); continue }
        #expect(byName[name]?.readUsage == oneRead)
    }
    for name in ["a.pdf", "d.pdf"] {
        #expect(byName[name]?.kind == .pending(nil, .paused(TriaAPI.ErrorCode.balanceEmpty.rawValue)))
        #expect(byName[name]?.readUsage == nil)
    }
    #expect(plan.sentDocuments == 3)
    #expect(plan.usage == oneRead + oneRead + oneRead)
    // d no se ha enviado: tras el límite no empieza ninguna lectura.
    let requests = await provider.requests
    #expect(requests.count == 4)
    #expect(!requests.contains { names($0, "d.pdf") })

    let cache = ProposalCache(workspace: ws)
    #expect(cache.latest(sha256: try sha(of: urls[0], in: ws)) != nil)
    #expect(cache.latest(sha256: try sha(of: urls[1], in: ws)) == nil)
    #expect(cache.latest(sha256: try sha(of: urls[2], in: ws)) != nil)
    #expect(cache.latest(sha256: try sha(of: urls[3], in: ws)) != nil)
    #expect(cache.latest(sha256: try sha(of: urls[4], in: ws)) == nil)

    // Al reanudar se leen a y d; 0, b y c salen de la caché y no se pagan otra vez.
    let again = try await SortPipeline(workspace: ws, provider: scripted([:])).plan()
    #expect(again.interruption == nil)
    #expect(again.items.filter(\.fromCache).map(\.file.lastPathComponent) == ["0.pdf", "b.pdf", "c.pdf"])
    #expect(again.sentDocuments == 2)
}

/// Un documento que ya se estaba preparando (aquí, esperando en `admit`) cuando el lote se para tampoco se envía.
@Test func aDocumentBeingPreparedWhenTheBatchStopsIsNotSent() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let a = try inboxPDF(dir, "a.pdf", "Modelo 303 uno")
    let b = try inboxPDF(dir, "b.pdf", "Modelo 303 dos")
    let bSha = try sha(of: b, in: ws)
    let limit = LLMError.serviceLimit(TriaAPI.ErrorCode.dailyLimit.rawValue)
    // El límite llega con b ya en `admit`, y b sale de `admit` cuando el lote ya tiene el resultado de a.
    let bWaiting = Signal(), stopped = Signal()
    let provider = SlowProvider { request in
        if names(request, "a.pdf") {
            try await wait(for: bWaiting)
            throw limit
        }
        return modelo
    }
    let admit: @Sendable (String) async -> Bool = { sha in
        if sha == bSha {
            await bWaiting.notify()
            try? await wait(for: stopped)
        }
        return true
    }

    let plan = try await SortPipeline(workspace: ws, provider: provider, admit: admit).plan { progress in
        if case .document(_, _, "a.pdf") = progress { Task { await stopped.notify() } }
    }

    #expect(plan.interruption == limit)
    #expect(kinds(plan)["b.pdf"] == .pending(nil, .paused(TriaAPI.ErrorCode.dailyLimit.rawValue)))
    #expect(plan.sentDocuments == 0)
    #expect(await provider.requests.count == 1)
    let cache = ProposalCache(workspace: ws)
    #expect(cache.latest(sha256: try sha(of: a, in: ws)) == nil)
    #expect(cache.latest(sha256: bSha) == nil)
}

/// Una lectura que se cancela (aquí, porque otro documento da una clave no válida) no es un rechazo del documento: no
/// se guarda como `providerError` y se volverá a leer.
@Test func aCancelledReadIsNotCached() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303 uno")
    let slow = try inboxPDF(dir, "b.pdf", "Modelo 303 dos")
    let never = Signal()
    let provider = SlowProvider { request in
        if names(request, "a.pdf") { throw LLMError.invalidKey }
        try await wait(for: never)
        return modelo
    }

    await #expect(throws: LLMError.invalidKey) { try await SortPipeline(workspace: ws, provider: provider).plan() }

    #expect(ProposalCache(workspace: ws).latest(sha256: try sha(of: slow, in: ws)) == nil)
}

// MARK: - Calentar la caché de prompts antes de leer en paralelo

/// Proveedor que cuenta las llamadas simultáneas. La primera tarda más, para que se vea quién más está en vuelo
/// mientras dura; guarda el máximo de simultáneas durante ella y el máximo de todo el lote.
private actor ConcurrencyProvider: LLMProvider {
    nonisolated let id = ProviderID.anthropic
    nonisolated let model = "claude-haiku-5-5"
    private var current = 0
    private var calls = 0
    private var firstInFlight = false
    private(set) var peakDuringFirst = 0
    private(set) var peak = 0

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        calls += 1
        let isFirst = calls == 1
        current += 1
        peak = max(peak, current)
        if isFirst { firstInFlight = true }
        if firstInFlight { peakDuringFirst = max(peakDuringFirst, current) }
        try await Task.sleep(nanoseconds: isFirst ? 300_000_000 : 60_000_000)
        if isFirst { firstInFlight = false }
        current -= 1
        return LLMResponse(text: modelo, usage: TokenUsage(inputTokens: 100, outputTokens: 10), model: model)
    }
}

@Test func theFirstModelCallRunsAloneToWarmThePromptCache() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    for name in ["a", "b", "c", "d", "e"] { try inboxPDF(dir, "\(name).pdf", "Modelo 303 \(name)") }
    let provider = ConcurrencyProvider()

    let plan = try await SortPipeline(workspace: ws, provider: provider, concurrency: 4, useCache: false).plan()

    #expect(plan.sentDocuments == 5)
    #expect(await provider.peakDuringFirst == 1)
    #expect(await provider.peak > 1)
}

@Test func aProposalFromTheLocalCacheDoesNotCountAsWarmUp() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try inboxPDF(dir, "a.pdf", "Modelo 303 a")
    _ = try await SortPipeline(workspace: ws, provider: scripted(["a.pdf": modelo])).plan()
    for name in ["b", "c", "d", "e"] { try inboxPDF(dir, "\(name).pdf", "Modelo 303 \(name)") }
    let provider = ConcurrencyProvider()

    let plan = try await SortPipeline(workspace: ws, provider: provider, concurrency: 4).plan()

    // a sale de la caché local: la primera llamada de verdad al modelo es la de b, y va sola.
    #expect(plan.items.filter(\.fromCache).count == 1)
    #expect(plan.sentDocuments == 4)
    #expect(await provider.peakDuringFirst == 1)
    #expect(await provider.peak > 1)
}
