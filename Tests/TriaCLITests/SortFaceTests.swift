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

private func answering(_ answers: [String: String], suggestion: String? = nil) -> ScriptedProvider {
    ScriptedProvider { request in
        if request.schemaName == "tria_rule_suggestion", let suggestion { return suggestion }
        for (name, answer) in answers where request.userText.contains("Original file name: \(name)\n") { return answer }
        return ScriptedProvider.proposalJSON(action: "pending", destination: "", filename: "", confidence: "low", doubt: "?")
    }
}

private func exists(_ cli: CLIHarness, _ path: String) -> Bool {
    FileManager.default.fileExists(atPath: cli.dir.url.appendingPathComponent(path).path)
}

/// Un terminal de verdad para `sort`: teclas sueltas y una ventana donde cabe la pantalla completa.
private let fullTerminal = TerminalCapabilities(colors: .none, errorColors: .none, animates: false, keys: true,
                                                size: TerminalSize(columns: 100, rows: 30))
private let renting = #"{"section":"Casos especiales","rule":"Los contratos de renting van a 2-Contratos/Renting."}"#
private let edited = "2-Contratos/Renting/Contrato Renting Ejemplo - 2024-09.pdf"

/// Dos documentos (alta.pdf con confianza alta y media.pdf con duda) y la carpeta para corregir media.pdf.
private func twoDocuments(answers: [String], capabilities: TerminalCapabilities = .plain,
                          screen: FakeScreen? = nil) throws -> CLIHarness {
    let cli = try CLIHarness(provider: answering(["alta.pdf": modelo, "media.pdf": medium], suggestion: renting),
                             answers: answers, capabilities: capabilities, screen: screen)
    _ = try WorkspaceFixture.make(in: cli.dir, folders: WorkspaceFixture.defaultFolders + ["2-Contratos"])
    try inboxPDF(cli.dir, "alta.pdf")
    try inboxPDF(cli.dir, "media.pdf")
    return cli
}

struct SortFaceTests {
    @Test func sortPrintsAHeaderAndTheReadingLineGoesToStandardError() async throws {
        let cli = try CLIHarness(provider: answering(["alta.pdf": modelo]))
        _ = try WorkspaceFixture.make(in: cli.dir)
        try inboxPDF(cli.dir, "alta.pdf")
        #expect(try await cli.run(["sort", "--dry-run"]) == 0)
        #expect(cli.terminal.output.hasPrefix("Tria · \(cli.dir.url.lastPathComponent) · Anthropic claude-haiku-5-5"))
        #expect(cli.terminal.transcript.contains("Buscando documentos en 99-Pendiente…"))
        #expect(cli.terminal.transcript.contains("✓ 1 documento leído en 0 s"))
        #expect(!cli.terminal.output.contains("leído"))
        #expect(cli.terminal.output.contains("1 listo"))
    }

    @Test func aSecondRunSaysWhatWasAlreadyRead() async throws {
        let cli = try CLIHarness(provider: answering(["alta.pdf": modelo, "media.pdf": medium]))
        _ = try WorkspaceFixture.make(in: cli.dir)
        try inboxPDF(cli.dir, "alta.pdf")
        try inboxPDF(cli.dir, "media.pdf")
        try await cli.run(["sort", "--dry-run"])
        #expect(!cli.terminal.transcript.contains("sin gastar"))
        try await cli.run(["sort", "--dry-run"])
        #expect(cli.terminal.transcript.contains("✓ 2 documentos leídos en 0 s (2 sin gastar: ya estaban leídos)"))
    }

    @Test func theSummaryCountsReadyDoubtfulDuplicatedAndPending() async throws {
        let cli = try CLIHarness(provider: answering(["alta.pdf": modelo, "media.pdf": medium]))
        _ = try WorkspaceFixture.make(in: cli.dir)
        for name in ["alta.pdf", "media.pdf", "rara.pdf", "repe.pdf"] { try inboxPDF(cli.dir, name) }
        try FileManager.default.copyItem(at: cli.dir.url.appendingPathComponent("99-Pendiente/repe.pdf"),
                                         to: cli.dir.url.appendingPathComponent("7-Facturas/Recibidas/Original.pdf"))
        #expect(try await cli.run(["sort", "--dry-run"]) == 0)
        #expect(cli.terminal.output.contains("1 listo · 1 con duda · 1 duplicado · 1 pendiente"))
    }

    @Test func ctrlCInAQuestionLeavesEverythingInTheInbox() async throws {
        let cli = try CLIHarness(provider: answering(["alta.pdf": modelo]), answers: ["r", "^C"])
        _ = try WorkspaceFixture.make(in: cli.dir)
        try inboxPDF(cli.dir, "alta.pdf")
        #expect(try await cli.run(["sort"]) == 130)
        #expect(exists(cli, "99-Pendiente/alta.pdf"))
        #expect(!cli.terminal.transcript.contains("Movidos"))
    }

    @Test func thinkingARuleShowsTheActivity() async throws {
        let wrong = ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "Factura Ejemplo.pdf",
                                                  confidence: "medium", doubt: "¿Factura o contrato?")
        let rule = #"{"section":"Casos especiales","rule":"Los contratos de renting van a 2-Contratos/Renting."}"#
        let cli = try CLIHarness(provider: answering(["scan.pdf": wrong], suggestion: rule),
                                 answers: ["r", "e", "2-Contratos/Renting", "Contrato Renting Ejemplo - 2024-09.pdf", "d"])
        _ = try WorkspaceFixture.make(in: cli.dir, folders: WorkspaceFixture.defaultFolders + ["2-Contratos"])
        try inboxPDF(cli.dir, "scan.pdf")
        #expect(try await cli.run(["sort"]) == 0)
        #expect(exists(cli, "2-Contratos/Renting/Contrato Renting Ejemplo - 2024-09.pdf"))
        #expect(cli.terminal.transcript.contains("Pensando una regla para scan.pdf…"))
        #expect(cli.terminal.transcript.contains("Sugerencia descartada."))
    }

    @Test func theDocumentNameComesFromTheRequest() {
        #expect(RequestTally.documentName(in: "# Document\n\nOriginal file name: scan 1.pdf\nFile dates: …") == "scan 1.pdf")
        #expect(RequestTally.documentName(in: "sin nombre") == nil)
    }

    @Test func sortOpensTheFullScreenInARealTerminal() async throws {
        let screen = FakeScreen(keys: [.enter])
        let terminal = TerminalCapabilities(colors: .none, errorColors: .none, animates: false, keys: true,
                                            size: TerminalSize(columns: 100, rows: 30))
        let cli = try CLIHarness(provider: answering(["alta.pdf": modelo, "media.pdf": medium]), capabilities: terminal,
                                 screen: screen)
        _ = try WorkspaceFixture.make(in: cli.dir)
        try inboxPDF(cli.dir, "alta.pdf")
        try inboxPDF(cli.dir, "media.pdf")
        #expect(try await cli.run(["sort"]) == 1)
        #expect(exists(cli, "1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf"))
        #expect(exists(cli, "99-Pendiente/media.pdf"))
        #expect(screen.events == ["enter", "leave"])
        #expect(!cli.terminal.transcript.contains("¿Qué hacemos?"))
        #expect(!cli.terminal.output.contains("Confianza alta"))   // sin fichas: ya las enseña la pantalla
        #expect(cli.terminal.output.contains("1 listo · 1 con duda"))
        #expect(cli.terminal.output.contains("Movidos: 1"))
    }

    @Test func anEditInTheFullScreenIsWhatGetsAppliedAndOffersARule() async throws {
        let screen = FakeScreen(keys: [.down, .character("e"), .enter])
        let cli = try twoDocuments(answers: ["2-Contratos/Renting", "Contrato Renting Ejemplo - 2024-09.pdf", "d"],
                                   capabilities: fullTerminal, screen: screen)
        #expect(try await cli.run(["sort"]) == 0)
        #expect(exists(cli, edited))
        #expect(exists(cli, "1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf"))
        #expect(!exists(cli, "99-Pendiente/media.pdf") && !exists(cli, "7-Facturas/Recibidas/Factura Dudosa.pdf"))
        #expect(screen.events == ["enter", "leave", "enter", "leave"])
        #expect(cli.terminal.transcript.contains("Pensando una regla para media.pdf…"))
        #expect(cli.terminal.transcript.contains("¿Añadir esta regla a TRIA.md?"))
        #expect(cli.terminal.transcript.contains("Sugerencia descartada."))
    }

    @Test func aSuggestionSavedForLaterKeepsItsOrigin() async throws {   // spec de Reglas, §4.4
        let screen = FakeScreen(keys: [.down, .character("e"), .enter])
        let cli = try twoDocuments(answers: ["2-Contratos/Renting", "Contrato Renting Ejemplo - 2024-09.pdf", "l"],
                                   capabilities: fullTerminal, screen: screen)
        #expect(try await cli.run(["sort"]) == 0)
        let saved = try #require(try SuggestionStore(workspace: Workspace.open(at: cli.dir.url)).list().first)
        #expect(saved.document == "media.pdf")
        #expect(saved.fromFolder == "7-Facturas/Recibidas")
        #expect(saved.toFolder == "2-Contratos/Renting")
        #expect(saved.context == "media.pdf: 7-Facturas/Recibidas → 2-Contratos/Renting")
    }

    @Test func ctrlCInTheFullScreenEndsWith130AndMovesNothing() async throws {
        let screen = FakeScreen(keys: [.interrupt])
        let cli = try twoDocuments(answers: [], capabilities: fullTerminal, screen: screen)
        #expect(try await cli.run(["sort"]) == 130)
        #expect(exists(cli, "99-Pendiente/alta.pdf") && exists(cli, "99-Pendiente/media.pdf"))
        #expect(screen.events == ["enter", "leave"])
        #expect(!cli.terminal.transcript.contains("Movidos"))
    }

    /// Ctrl-D en una edición deja `stdin` en fin de entrada; si no se limpia, la `e` siguiente vuelve sin preguntar y
    /// el Intro que el usuario cree que contesta a la carpeta aplica lo marcado.
    @Test func ctrlDCancelsOnlyThatEditInTheFullScreen() async throws {
        let screen = FakeScreen(keys: [.down, .character("e"), .character("e"), .enter])
        let cli = try twoDocuments(answers: ["^D", "2-Contratos/Renting", "Contrato Renting Ejemplo - 2024-09.pdf", "d"],
                                   capabilities: fullTerminal, screen: screen)
        #expect(try await cli.run(["sort"]) == 0)
        #expect(exists(cli, edited))
        #expect(screen.events == ["enter", "leave", "enter", "leave", "enter", "leave"])
        #expect(cli.terminal.transcript.contains("Sugerencia descartada."))
    }

    @Test func ctrlDCancelsOnlyThatEditInTheCards() async throws {
        let cli = try twoDocuments(answers: ["r", "e", "^D", "e", "2-Contratos/Renting",
                                             "Contrato Renting Ejemplo - 2024-09.pdf", "d"])
        #expect(try await cli.run(["sort"]) == 1)
        #expect(exists(cli, "99-Pendiente/alta.pdf"))
        #expect(exists(cli, edited))
        #expect(cli.terminal.transcript.contains("Sugerencia descartada."))
    }

    /// Lo que dice la IA se limpia para verlo, nunca en `--json`.
    @Test func controlCharactersAreCleanedForPeopleButNotInJSON() async throws {
        let odd = ScriptedProvider.proposalJSON(destination: "7-Facturas/Recibidas", filename: "Factura.pdf",
                                                reason: "primera\nsegunda\u{1B}[2J")
        let cli = try CLIHarness(provider: answering(["alta.pdf": odd]))
        _ = try WorkspaceFixture.make(in: cli.dir)
        try inboxPDF(cli.dir, "alta.pdf")
        #expect(try await cli.run(["sort", "--dry-run"]) == 0)
        #expect(cli.terminal.output.contains("Confianza alta · primera segunda [2J"))
        #expect(!cli.terminal.output.contains("\u{1B}"))
        #expect(try await cli.run(["sort", "--dry-run", "--json"]) == 0)
        #expect(cli.terminal.output.contains(#""reason" : "primera\nsegunda\u001b[2J""#))
    }

    @Test func aSmallWindowFallsBackToTheCards() async throws {
        let screen = FakeScreen(keys: [])
        let narrow = TerminalCapabilities(colors: .none, errorColors: .none, animates: false, keys: true,
                                          size: TerminalSize(columns: 59, rows: 30))
        let cli = try CLIHarness(provider: answering(["alta.pdf": modelo]), answers: ["n"], capabilities: narrow,
                                 screen: screen)
        _ = try WorkspaceFixture.make(in: cli.dir)
        try inboxPDF(cli.dir, "alta.pdf")
        #expect(try await cli.run(["sort"]) == 1)
        #expect(screen.events.isEmpty)
        #expect(cli.terminal.transcript.contains("¿Qué hacemos?"))
        #expect(cli.terminal.output.contains("Confianza alta"))
    }
}
