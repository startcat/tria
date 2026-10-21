#if DEBUG
import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

/// Un documento de texto con su marca, como lo prepara la extracción.
private func document(_ text: String, name: String = "escaneo.txt") -> DocumentContext {
    DocumentContext(originalFilename: name, created: nil, modified: nil,
                    extracted: ExtractedDocument(text: text, pageCount: 1, method: .plainText))
}

/// El proveedor falso con su estado en `<dir>/estado/`, como la app y el CLI.
private func qa(_ dir: TempDir, model: String = "claude-sonnet-5-5", id: ProviderID = .anthropic) -> QAProvider {
    QAProvider(id: id, model: model, log: dir.url.appendingPathComponent("estado/peticiones.jsonl"),
               offlineFlag: dir.url.appendingPathComponent("estado/sin-red"))
}

/// El espacio de prueba de `dir`: la primera vez se crea y luego se abre.
private func workspace(_ dir: TempDir) throws -> Workspace {
    let rules = dir.url.appendingPathComponent(Workspace.rulesFileName)
    if FileManager.default.fileExists(atPath: rules.path) { return try Workspace.open(at: dir.url) }
    return try WorkspaceFixture.make(in: dir)
}

/// Lo que deja el `Classifier` de verdad con el proveedor falso.
private func classify(_ text: String, _ dir: TempDir, name: String = "escaneo.txt",
                      provider: QAProvider? = nil) async throws -> (ClassificationOutcome, TokenUsage) {
    try await Classifier(provider: provider ?? qa(dir), workspace: try workspace(dir), tree: "")
        .classify(document(text, name: name))
}

private func logLines(_ dir: TempDir) throws -> [[String: String]] {
    let url = dir.url.appendingPathComponent("estado/peticiones.jsonl")
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
        try JSONDecoder().decode([String: String].self, from: Data($0.utf8))
    }
}

/// `QAProvider` contesta como un proveedor de verdad: cada marca acaba como acabaría con la IA (spec QA §4).
struct QAProviderTests {
    @Test func aProposalMarkerIsAValidatedProposalWithTheDocumentExtension() async throws {
        let dir = try TempDir()
        let marker = QAMarker.proposal(folder: "7-Facturas/Recibidas", name: "Factura Papeleria Mar - 2026-10-09",
                                       type: "Factura", date: "2026-10-09")
        let (outcome, usage) = try await classify("Factura nº 12\n\(marker.text)", dir)
        guard case .proposed(let proposal, let destination) = outcome else { Issue.record("\(outcome)"); return }
        #expect(destination == "7-Facturas/Recibidas/Factura Papeleria Mar - 2026-10-09.txt")
        #expect(proposal.action == .file)
        #expect(proposal.documentType == "Factura")
        #expect(proposal.documentDate == "2026-10-09")
        #expect(proposal.confidence == .high)
        #expect(proposal.doubt == nil)
        #expect(usage == TokenUsage(inputTokens: 1000, outputTokens: 200))
    }

    @Test func mediumConfidenceCarriesADoubtLikeARealModel() async throws {
        let dir = try TempDir()
        let marker = QAMarker.proposal(folder: "7-Facturas/Recibidas", name: "Factura", type: "Factura",
                                       confidence: "media")
        let (outcome, _) = try await classify(marker.text, dir)
        guard case .proposed(let proposal, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(proposal.confidence == .medium)
        #expect(proposal.doubt == "Confianza media (marca QA).")
        #expect(proposal.documentDate == nil)
    }

    @Test func aDoubtMarkerLeavesTheDocumentPendingWithThatDoubt() async throws {
        let dir = try TempDir()
        let (outcome, usage) = try await classify(QAMarker.doubt("No sé si es factura o presupuesto").text, dir)
        guard case .pending(let proposal, .modelDoubt(let doubt)) = outcome else { Issue.record("\(outcome)"); return }
        #expect(doubt == "No sé si es factura o presupuesto")
        #expect(proposal?.action == .pending)
        #expect(usage == QAProvider.usage)
    }

    @Test func withoutAMarkerTheDocumentIsPendingWithTheNoMarkerDoubt() async throws {
        let (outcome, _) = try await classify("Un documento cualquiera", try TempDir())
        guard case .pending(_, .modelDoubt(let doubt)) = outcome else { Issue.record("\(outcome)"); return }
        #expect(doubt == "Sin marca QA")
    }

    /// Cada error, como lo deja el `Classifier` con `AnthropicProvider`: el rechazo y la negativa dejan el documento
    /// pendiente; sin conexión pausa el lote y sin saldo lo para.
    @Test func errorMarkersEndAsTheRealProviderErrorsDo() async throws {
        let rejected = try await classify(QAMarker.error("rechazo").text, try TempDir()).0
        #expect(rejected == .pending(nil, .providerError("HTTP 400: documento rechazado (QA)")))

        let refused = try await classify(QAMarker.error("negativa").text, try TempDir()).0
        #expect(refused == .pending(nil, .refused))

        await #expect(throws: LLMError.offline) { try await classify(QAMarker.error("sin-conexion").text, try TempDir()) }
        #expect(LLMError.offline.isTransient)

        let quota = LLMError.quotaExceeded("Your credit balance is too low to access the Anthropic API. "
                                           + "Please go to Plans & Billing to upgrade or purchase credits.")
        await #expect(throws: quota) { try await classify(QAMarker.error("cuota").text, try TempDir()) }
        #expect(quota.isFatal)
    }

    @Test func theResponseEchoesTheModelAndTheProvider() async throws {
        let dir = try TempDir()
        let provider = qa(dir, model: "gpt-5.4-mini", id: .openai)
        let rules = try workspace(dir).rules
        let response = try await provider.complete(PromptBuilder.request(rules: rules, tree: "",
                                                                         document: document(QAMarker.doubt("x").text)))
        #expect(response.model == "gpt-5.4-mini")
        #expect(response.usage == TokenUsage(inputTokens: 1000, outputTokens: 200))
        #expect(provider.id == .openai)
        let quota = LLMError.quotaExceeded("You exceeded your current quota, please check your plan and billing details.")
        await #expect(throws: quota) {
            try await provider.complete(PromptBuilder.request(rules: rules, tree: "",
                                                              document: document(QAMarker.error("cuota").text)))
        }
    }

    @Test func eachRequestLeavesOneLineInTheLog() async throws {
        let dir = try TempDir()
        let marker = QAMarker.proposal(folder: "7-Facturas/Recibidas", name: "Factura", type: "Factura")
        _ = try await classify("Texto\n\(marker.text)", dir, name: "factura.pdf")
        _ = try await classify("Sin marca", dir, name: "otro.txt", provider: qa(dir, model: "claude-haiku-5-5"))
        #expect(try logLines(dir) == [
            ["modelo": "claude-sonnet-5-5", "fichero": "factura.pdf", "marca": marker.text],
            ["modelo": "claude-haiku-5-5", "fichero": "otro.txt", "marca": ""],
        ])
    }

    /// Sin red, nada sale del Mac: ni respuesta ni línea en el registro. Al quitar `sin-red`, vuelve a contestar.
    @Test func theOfflineFlagAnswersOfflineAndSendsNothing() async throws {
        let dir = try TempDir()
        let flag = try dir.write("estado/sin-red", "")
        let marker = QAMarker.doubt("x")
        await #expect(throws: LLMError.offline) { try await classify(marker.text, dir) }
        #expect(try logLines(dir).isEmpty)

        try FileManager.default.removeItem(at: flag)
        let (outcome, _) = try await classify(marker.text, dir)
        guard case .pending(_, .modelDoubt("x")) = outcome else { Issue.record("\(outcome)"); return }
        #expect(try logLines(dir).count == 1)
    }

    @Test func aConnectionErrorMarkerIsNotLogged() async throws {
        let dir = try TempDir()
        await #expect(throws: LLMError.offline) { try await classify(QAMarker.error("sin-conexion").text, dir) }
        #expect(try logLines(dir).isEmpty)
    }

    @Test func aSlowMarkerTakesThatLongAndThenAnswers() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let (outcome, _) = try await classify(QAMarker.slow(1, then: .doubt("lenta")).text, try TempDir())
        #expect(clock.now - start >= .seconds(1))
        guard case .pending(_, .modelDoubt("lenta")) = outcome else { Issue.record("\(outcome)"); return }
    }

    /// `[QA espera=1 carpeta=…]`: tarda y después propone, igual que la misma propuesta sin espera. Las pruebas de
    /// interfaz la usan para ver «Leyendo X de N…» y para retirar el permiso a mitad de la lectura.
    @Test func aSlowProposalWaitsAndThenProposes() async throws {
        let dir = try TempDir()
        let marker = QAMarker.slow(1, then: .proposal(folder: "7-Facturas/Recibidas", name: "Factura Lenta",
                                                      type: "Factura", date: "2026-10-09"))
        let clock = ContinuousClock()
        let start = clock.now
        let (outcome, usage) = try await classify(marker.text, dir)
        #expect(clock.now - start >= .seconds(1))
        guard case .proposed(let proposal, let destination) = outcome else { Issue.record("\(outcome)"); return }
        #expect(destination == "7-Facturas/Recibidas/Factura Lenta.txt")
        #expect(proposal.documentDate == "2026-10-09")
        #expect(proposal.doubt == nil)
        #expect(usage == QAProvider.usage)
        #expect(try logLines(dir) == [["modelo": "claude-sonnet-5-5", "fichero": "escaneo.txt", "marca": marker.text]])
    }

    /// Si la red cae mientras espera, la petición ya ha salido (tiene su línea) pero acaba sin conexión.
    @Test func theNetworkCanDropDuringTheWait() async throws {
        let dir = try TempDir()
        let reading = Task { try await classify(QAMarker.slow(2, then: .doubt("x")).text, dir) }
        // Cuando la petición tiene su línea, el proveedor ya está esperando: entonces se va la red.
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while try logLines(dir).isEmpty, clock.now < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        try dir.write("estado/sin-red", "")
        await #expect(throws: LLMError.offline) { try await reading.value }
        #expect(try logLines(dir).count == 1)
    }

    /// Un lote entero, con la marca dentro de un PDF de verdad (partida en dos líneas por lo larga que es): cada
    /// documento acaba según su marca.
    @Test func aBatchSortsEachDocumentByItsMarker() async throws {
        let dir = try TempDir()
        let ws = try workspace(dir)
        let filler = String(repeating: "Contenido suficiente para no necesitar OCR en este documento. ", count: 3)
        let proposal = QAMarker.proposal(folder: "7-Facturas/Recibidas", name: "Factura Papeleria Mar - 2026-10-09",
                                         type: "Factura", date: "2026-10-09")
        for (name, text) in [("a-factura.pdf", proposal.text), ("b-duda.pdf", QAMarker.doubt("¿Factura?").text),
                             ("c-negativa.pdf", QAMarker.error("negativa").text)] {
            let url = dir.url.appendingPathComponent("99-Pendiente/\(name)")
            try FixtureFactory.textPDF(at: url, pages: [filler + " " + text])
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)],
                                                  ofItemAtPath: url.path)
        }
        let plan = try await SortPipeline(workspace: ws, provider: qa(dir), useCache: false).plan()
        #expect(plan.items.map(\.file.lastPathComponent) == ["a-factura.pdf", "b-duda.pdf", "c-negativa.pdf"])
        guard case .proposal(_, let action) = plan.items[0].kind else { Issue.record("\(plan.items[0].kind)"); return }
        #expect(action.destination == "7-Facturas/Recibidas/Factura Papeleria Mar - 2026-10-09.pdf")
        guard case .pending(_, .modelDoubt("¿Factura?")) = plan.items[1].kind else {
            Issue.record("\(plan.items[1].kind)")
            return
        }
        #expect(plan.items[2].kind == .pending(nil, .refused))
        #expect(plan.usage == TokenUsage(inputTokens: 2000, outputTokens: 400))
        #expect(plan.model == "claude-sonnet-5-5")
        #expect(try logLines(dir).compactMap { $0["fichero"] }.sorted()
                == ["a-factura.pdf", "b-duda.pdf", "c-negativa.pdf"])
    }

    // MARK: - Reglas (spec de Reglas, §9)

    private func askRules(_ instruction: String, _ dir: TempDir) async throws -> (RulesAskResult, Workspace) {
        let ws = try Workspace.initialize(at: dir.url, rulesText: Templates.text(.autonomo, language: .es))
        let (result, usage) = try await RulesAsker(provider: qa(dir)).ask(instruction, in: ws)
        #expect(usage == QAProvider.usage)
        return (result, ws)
    }

    @Test func aRulesMarkerAddsABulletToTheSectionAndAsksForTheFolder() async throws {
        let dir = try TempDir()
        let marker = QAMarker.rulesChange(rule: "Las facturas de la luz van a `10-Suministros/`.", section: "s3",
                                          removing: "- Los tiques y recibos de gastos van con las facturas recibidas.",
                                          createFolder: "10-Suministros", summary: "Luz a 10-Suministros")
        let (result, _) = try await askRules("Las facturas de la luz van a Suministros \(marker.text)", dir)
        guard case .change(let change) = result else { Issue.record("\(result)"); return }
        #expect(change.summary == "Luz a 10-Suministros")
        #expect(change.createFolders == ["10-Suministros"])
        #expect(change.preview.map(\.title) == ["Casos especiales"])
        #expect(change.preview[0].lines.contains(.removed("- Los tiques y recibos de gastos van con las facturas recibidas.")))
        #expect(change.preview[0].lines.last == .added("- Las facturas de la luz van a `10-Suministros/`."))
        let lines = try logLines(dir)
        #expect(lines.count == 1)
        #expect(lines.first?["marca"] == marker.text)
    }

    @Test func withoutASectionTheRuleGoesToANewOne() async throws {
        let dir = try TempDir()
        let (result, _) = try await askRules("x \(QAMarker.rulesChange(rule: "Regla nueva.", title: "Suministros").text)", dir)
        guard case .change(let change) = result else { Issue.record("\(result)"); return }
        #expect(change.preview.map(\.kind) == [.added])
        #expect(change.newText.hasSuffix("## Suministros\n\n- Regla nueva.\n"))
        #expect(change.summary == QAProvider.defaultRulesChangeSummary)
    }

    @Test func aRefusalABrokenAnswerOrNoMarkerAreWhatTheySay() async throws {
        let refusal = try await askRules("x \(QAMarker.rulesRefusal("Eso no son reglas").text)", try TempDir()).0
        #expect(refusal == .refused("Eso no son reglas"))
        let none = try await askRules("Sin marca", try TempDir()).0
        #expect(none == .refused(QAProvider.noRulesChangeRefusal))
        do {
            _ = try await askRules("x \(QAMarker.brokenAnswer.text)", try TempDir())
            Issue.record("Una respuesta rota no se propone")
        } catch let failure as RulesAskFailure {
            guard case .invalidResponse = failure.reason else { Issue.record("\(failure.reason)"); return }
        }
    }

    @Test func aDocumentMarkerCarriesTheRuleItsCorrectionSuggests() async throws {
        let dir = try TempDir()
        let ws = try workspace(dir)
        let proposal = Proposal(action: .file, destination: "5-Bancos", filename: "Recibo.txt", documentType: "Recibo",
                                documentDate: nil, confidence: .high, reason: "r", doubt: nil)
        let marker = QAMarker.proposal(folder: "5-Bancos", name: "Recibo", type: "Recibo")
            .suggesting(rule: "Los recibos de seguros van a 7-Seguros.")
        let learner = RulesLearner(provider: qa(dir))
        let (draft, usage) = try await learner.suggestRule(rules: ws.rules, original: proposal, originalFilename: "scan.txt",
                                                           correctedDestination: "7-Seguros", correctedFilename: "Recibo.txt",
                                                           excerpt: "Recibo de seguro\n\(marker.text)")
        #expect(draft == RuleSuggestionDraft(section: "Casos especiales", rule: "Los recibos de seguros van a 7-Seguros."))
        #expect(usage == QAProvider.usage)
        // Sin regla en la marca, una de serie.
        let (plain, _) = try await learner.suggestRule(rules: ws.rules, original: proposal, originalFilename: "otro.txt",
                                                       correctedDestination: "7-Seguros", correctedFilename: "Recibo.txt",
                                                       excerpt: "Sin marca")
        #expect(plain == RuleSuggestionDraft(section: QAProvider.defaultSuggestionSection,
                                             rule: QAProvider.defaultSuggestionRule))
        #expect(try logLines(dir).map { $0["fichero"] } == ["scan.txt", "otro.txt"])
    }
}
#endif
