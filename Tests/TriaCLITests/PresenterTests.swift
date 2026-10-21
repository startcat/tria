import Foundation
import Testing
@testable import TriaCLI
@testable import TriaKit

struct PresenterTests {
    @Test func aCardAlignsItsLinesUnderTheName() throws {
        let env = try CLIHarness().env
        let item = UIFixtures.proposal("scan_0012.pdf", "2-Facturas Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf")
        #expect(Presenter.card(item, index: 1, total: 9, env, style: .plain) == [
            " 1/9  scan_0012.pdf",
            "      → 2-Facturas Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf",
            "      ● Confianza alta · Factura de Papelería Mar del 5 de octubre.",
        ])
    }

    @Test func aDoubtfulCardShowsTheDoubtAndTwoDigitCountersAlign() throws {
        let env = try CLIHarness().env
        let item = UIFixtures.proposal("nota.pdf", "6-Varios/Nota.pdf", confidence: .low, reason: "Una nota.",
                                       doubt: "No queda claro qué es.")
        #expect(Presenter.card(item, index: 3, total: 12, env, style: .plain) == [
            "  3/12  nota.pdf",
            "        → 6-Varios/Nota.pdf",
            "        ● Confianza baja · Una nota.",
            "        Duda: No queda claro qué es.",
        ])
    }

    @Test func duplicatePendingAndUndoneCards() throws {
        let env = try CLIHarness().env
        #expect(Presenter.card(UIFixtures.duplicate("descarga (2).pdf", of: "5-Bancos/descarga.pdf"), index: 4,
                               total: 5, env, style: .plain)
                == [" 4/5  descarga (2).pdf", "      ≡ DUPLICADO de 5-Bancos/descarga.pdf → 98-Duplicados/descarga (2).pdf"])
        #expect(Presenter.card(UIFixtures.pending("IMG_4471.jpg", .encrypted), index: 5, total: 5, env, style: .plain)
                == [" 5/5  IMG_4471.jpg", "      ○ PENDIENTE: PDF protegido con contraseña"])
        let undone = UIFixtures.proposal("alta.pdf", "7-Facturas/Recibidas/A.pdf", undone: true)
        #expect(Presenter.card(undone, index: 1, total: 1, env, style: .plain).last
                == "      ↺ Ya lo deshiciste una vez: en modo automático no se aplica.")
    }

    @Test func colorsMarkTheDestinationAndTheConfidence() throws {
        let env = try CLIHarness().env
        let lines = Presenter.card(UIFixtures.proposal("a.pdf", "7-Facturas/Recibidas/A.pdf"), index: 1, total: 1, env,
                                   style: Style(.palette256))
        #expect(lines[0] == " 1/1  \u{1B}[1ma.pdf\u{1B}[22m")
        #expect(lines[1] == "      \u{1B}[38;5;166m→ 7-Facturas/Recibidas/A.pdf\u{1B}[39m")
        #expect(lines[2].hasPrefix("      \u{1B}[38;5;65m●\u{1B}[39m Confianza alta"))
    }

    @Test func theSummaryCountsEachKindInOneLine() throws {
        let env = try CLIHarness().env
        #expect(Presenter.summary(UIFixtures.plan(UIFixtures.mockup), env, style: .plain)
                == "2 listos · 1 con duda · 1 duplicado · 1 pendiente")
        let one = UIFixtures.plan([UIFixtures.proposal("a.pdf", "7-Facturas/Recibidas/A.pdf")])
        #expect(Presenter.summary(one, env, style: .plain) == "1 listo")
        #expect(Presenter.summary(one, env, style: Style(.palette256)) == "\u{1B}[38;5;65m1 listo\u{1B}[39m")
    }

    @Test func theHeaderNamesTheSpaceTheProviderAndTheModel() {
        #expect(Presenter.header(workspace: "Despacho", provider: .anthropic, model: "claude-haiku-5-5", style: .plain)
                == "Tria · Despacho · Anthropic claude-haiku-5-5")
        #expect(Presenter.header(workspace: "Casa", provider: .openai, model: "gpt-5.4-mini", style: Style(.palette256))
                == "\u{1B}[38;5;244mTria · Casa · OpenAI gpt-5.4-mini\u{1B}[39m")
    }

    @Test func resultsAreGreenAndFailuresRed() throws {
        let env = try CLIHarness().env
        let report = ApplyReport(batch: "b_1", applied: [AppliedMove(operationID: "op_1", from: "a", to: "b")],
                                 failed: [FailedMove(source: "c.pdf", message: "sin permiso")])
        #expect(Presenter.applied(report, env, style: .plain) == [
            "✓ Movidos: 1 · fallidos: 1 · lote b_1 (deshacer: tria undo --last)",
            "  ✗ No se ha podido mover c.pdf: sin permiso",
        ])
        let painted = Presenter.applied(report, env, style: Style(.palette256))
        #expect(painted[0].hasPrefix("\u{1B}[38;5;65m✓ Movidos: 1"))
        #expect(painted[1] == "  \u{1B}[38;5;131m✗ No se ha podido mover c.pdf: sin permiso\u{1B}[39m")
    }

    @Test func promptKeysAreHighlightedOnlyWithColors() {
        let prompt = "[s] aplicar · [e] editar · [o] omitir · [q] terminar: "
        #expect(Presenter.keys(prompt, style: .plain) == prompt)
        #expect(Presenter.keys("[s] sí · [s/N] [", style: Style(.palette256))
                == "[\u{1B}[1m\u{1B}[38;5;166ms\u{1B}[39m\u{1B}[22m] sí · [s/N] [")
    }

    @Test func addedRuleLinesAreGreen() {
        let preview = "  ## Casos especiales\n+ - Los contratos van a 2-Contratos."
        #expect(Presenter.rulePreview(preview, style: .plain) == preview)
        #expect(Presenter.rulePreview(preview, style: Style(.palette256))
                == "  ## Casos especiales\n\u{1B}[38;5;65m+ - Los contratos van a 2-Contratos.\u{1B}[39m")
    }

    @Test func warningsAreAmberOnTheirOwnOutput() throws {
        let cli = try CLIHarness(capabilities: .colored)
        cli.env.say(.warning, .pendingLeft, "2")
        cli.env.warn(.profileNone)
        #expect(cli.terminal.output == "\u{1B}[38;5;136mQuedan 2 pendientes en la bandeja.\u{1B}[39m")
        #expect(cli.terminal.transcript.contains("\u{1B}[38;5;136mAviso: no hay PERFIL.md"))
    }

    @Test func heldReadsAsOnHold() throws {
        let env = try CLIHarness().env
        #expect(Presenter.reason(.held, env) == "en espera")
    }

    @Test func countsChooseSingularOrPlural() {
        #expect(L10n.count(1, .summaryPendingOne, .summaryPendingMany, .ca) == "1 pendent")
        #expect(L10n.count(3, .summaryPendingOne, .summaryPendingMany, .en) == "3 pending")
        #expect(L10n.count(2, .summaryReadyOne, .summaryReadyMany, .es) == "2 listos")
        #expect(L10n.count(1, .summaryDuplicateOne, .summaryDuplicateMany, .es) == "1 duplicado")
        #expect(L10n.count(1, .pendingLeftOne, .pendingLeft, .ca) == "Queda 1 pendent a la safata.")
        #expect(L10n.count(1, .pendingLeftOne, .pendingLeft, .es) == "Queda 1 pendiente en la bandeja.")
        #expect(L10n.count(1, .pendingLeftOne, .pendingLeft, .en) == "1 document remains in the inbox.")
        #expect(L10n.count(2, .pendingLeftOne, .pendingLeft, .es) == "Quedan 2 pendientes en la bandeja.")
    }
}

struct ControlCharacterTests {
    private func clean(_ lines: [String]) -> Bool { !lines.contains { $0.unicodeScalars.contains(where: isControl) } }

    @Test func cardsStatusLogResultsAndRulesShowNoControlCharacters() throws {
        let env = try CLIHarness().env
        let card = Presenter.card(UIFixtures.proposal("a\nb.pdf", "6-Varios/\u{1B}[2JNota.pdf", confidence: .low,
                                                      reason: "una\nrazón", doubt: "una\u{9B}duda"),
                                  index: 1, total: 1, env, style: .plain)
        #expect(clean(card))
        #expect(card[0].hasSuffix("a b.pdf"))
        #expect(clean(Presenter.card(UIFixtures.duplicate("c\r.pdf", of: "5-Bancos/\u{7F}c.pdf"), index: 1, total: 1, env,
                                     style: .plain)))
        #expect(clean(Presenter.card(UIFixtures.pending("d.pdf", .providerError("mal\n\u{1B}[31m")), index: 1, total: 1,
                                     env, style: .plain)))
        let status = [StatusItem(file: URL(fileURLWithPath: "/tmp/e\n.pdf"), relativePath: "99-Pendiente/e\n.pdf",
                                 state: .duplicate(original: "5-Bancos/\u{1B}e.pdf"))]
        #expect(clean(Presenter.status(status, env, style: .plain)))
        let report = ApplyReport(batch: "b_1", applied: [],
                                 failed: [FailedMove(source: "f\n.pdf", message: "sin\u{1B}[2J permiso")])
        #expect(clean(Presenter.applied(report, env, style: .plain)))
        #expect(clean(Presenter.rulePreview("  ## Casos\n+ - Los\u{1B}[2J contratos\tvan", style: .plain)
            .components(separatedBy: "\n")))
    }

    /// La cabecera de `tria sort` cita el nombre de la carpeta del espacio, que puede llevar cualquier cosa.
    @Test func theHeaderShowsTheFolderNameWithoutControlCharacters() {
        #expect(Presenter.header(workspace: "Des\npacho\u{1B}[2J", provider: .anthropic, model: "claude\u{7}",
                                 style: .plain) == "Tria · Des pacho [2J · Anthropic claude ")
    }

    /// Los errores para leer citan lo que dice el proveedor, un fichero o el sistema: en una línea y sin órdenes.
    @Test func errorMessagesShowNoControlCharacters() throws {
        let env = try CLIHarness().env
        #expect(describe(LLMError.quotaExceeded("Sin saldo\n\u{1B}[2J"), env)
                == "Tu cuenta del proveedor no tiene saldo o cuota: Sin saldo  [2J")
        struct Odd: Error, CustomStringConvertible { let description = "uno\r\ndos\u{1B}]0;título\u{7}" }
        #expect(describe(Odd(), env) == "uno  dos ]0;título ")
    }

    @Test func messagesSanitizeWhatTheyQuote() throws {
        let cli = try CLIHarness()
        cli.env.say(.success, .suggestionApplied, "regla\u{1B}[2J\nmala")
        cli.env.warn(.profileWarnTaxID, "B\u{1B}12")
        #expect(clean([cli.terminal.transcript.replacingOccurrences(of: "\n", with: "")]))
        #expect(cli.terminal.output.hasSuffix("regla [2J mala"))
    }
}

struct CardWidthTests {
    private func narrow(_ columns: Int) throws -> CLIEnvironment {
        try CLIHarness(capabilities: TerminalCapabilities(colors: .none, errorColors: .none, animates: false, keys: false,
                                                          size: TerminalSize(columns: columns, rows: 24))).env
    }

    /// El nombre se recorta por el medio; el destino y el motivo se parten, con la sangría del texto tras el símbolo.
    @Test func longDestinationsAndReasonsWrapUnderTheirSymbol() throws {
        let env = try narrow(40)
        let item = UIFixtures.proposal("un nombre de fichero escaneado larguísimo 0012.pdf",
                                       "2-Facturas Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf",
                                       reason: "Una razón extremadamente larga que no cabe en la línea de la ficha.")
        let lines = Presenter.card(item, index: 1, total: 9, env, style: .plain)
        for line in lines { #expect(TextWidth.columns(line) <= 40) }
        #expect(lines[0].hasPrefix(" 1/9  un nombre"))
        #expect(lines[0].contains("…") && lines[0].hasSuffix("0012.pdf"))
        #expect(Array(lines[1...3]) == ["      → 2-Facturas Recibidas/2026/4T/", "        Factura Papeleria Mar -",
                                        "        2026-10-05.pdf"])
        let reason = TextWidth.wrap("Confianza alta · Una razón extremadamente larga que no cabe en la línea de la ficha.",
                                    width: 32)
        #expect(Array(lines[4...]) == ["      ● " + reason[0]] + reason.dropFirst().map { "        " + $0 })
        let painted = Presenter.card(item, index: 1, total: 9, env, style: Style(.palette256))
        #expect(painted[1] == "      \u{1B}[38;5;166m→ 2-Facturas Recibidas/2026/4T/\u{1B}[39m")
        #expect(painted[2] == "        \u{1B}[38;5;166mFactura Papeleria Mar -\u{1B}[39m")
    }

    @Test func theDoubtTheDuplicateAndThePendingReasonWrapInsteadOfBeingCut() throws {
        let env = try narrow(50)
        func block(_ text: String, first: String, path: Bool = false) -> [String] {
            let parts = TextWidth.wrap(text, width: 42, path: path)
            return ["      " + first + parts[0]] + parts.dropFirst().map { "        " + $0 }
        }
        let doubt = "No queda claro qué es: parece una nota suelta escrita a mano en una servilleta."
        let doubtful = UIFixtures.proposal("nota.pdf", "6-Varios/Nota.pdf", confidence: .low, reason: "Una nota.",
                                           doubt: doubt)
        let lines = Presenter.card(doubtful, index: 1, total: 1, env, style: .plain)
        let expected = block("Duda: " + doubt, first: "")
        #expect(expected.count > 1 && Array(lines.suffix(expected.count)) == expected)
        let original = "4-Correo/Extractos bancarios/extracto.txt"
        #expect(Presenter.card(UIFixtures.duplicate("extracto (2).txt", of: original), index: 1, total: 1, env,
                               style: .plain).dropFirst()
                == block("DUPLICADO de \(original) → 98-Duplicados/extracto (2).txt", first: "≡ ", path: true)[...])
        let pending = UIFixtures.pending("IMG_4471.jpg", .providerError("el proveedor ha devuelto un error muy largo"))
        #expect(Presenter.card(pending, index: 1, total: 1, env, style: .plain).dropFirst()
                == block("PENDIENTE: " + Presenter.reason(.providerError("el proveedor ha devuelto un error muy largo"), env),
                         first: "○ ")[...])
    }

    @Test func truncationHappensBeforePaintingAndWithoutAWidthNothingIsCut() throws {
        let item = UIFixtures.proposal("un nombre de fichero escaneado larguísimo 0012.pdf", "7-Facturas/Recibidas/A.pdf")
        let painted = Presenter.card(item, index: 1, total: 1, try narrow(30), style: Style(.palette256))
        #expect(painted[0].hasSuffix("\u{1B}[22m") && painted[0].contains("…"))
        let plain = try CLIHarness().env
        #expect(Presenter.card(item, index: 1, total: 1, plain, style: .plain)[0].hasSuffix("larguísimo 0012.pdf"))
        // En una tubería no hay ancho: nada se parte, cada cosa en su línea como siempre.
        let long = UIFixtures.proposal("a.pdf", "7-Facturas/Recibidas/" + String(repeating: "Carpeta larga/", count: 10)
                                       + "A.pdf", reason: String(repeating: "Una razón larga. ", count: 10), doubt: "Una duda.")
        #expect(Presenter.card(long, index: 1, total: 1, plain, style: .plain).count == 3)
    }
}
