import Foundation
import Testing
import TriaKit
import TriaTestSupport
@testable import TriaCLI

private let newSection = reply(sections: [("new", suministros)], folders: ["10-Suministros"])
private let instruction = "Las facturas de la luz van a Suministros"

private func rules(_ cli: CLIHarness) throws -> String {
    try String(contentsOf: cli.dir.url.appendingPathComponent("TRIA.md"), encoding: .utf8)
}

struct RulesAskTests {
    @Test func askShowsTheCostTheChangeAndAppliesWithA() async throws {
        let cli = try CLIHarness(provider: ScriptedProvider { _ in newSection }, answers: ["a"])
        _ = try WorkspaceFixture.make(in: cli.dir)
        #expect(try await cli.run(["rules", "ask", instruction]) == 0)
        let transcript = cli.terminal.transcript
        #expect(transcript.contains("Pedir el cambio costará unos "))
        #expect(transcript.contains("Tria está pensando el cambio…"))
        #expect(transcript.contains("Las facturas de la luz van a 10-Suministros"))
        #expect(transcript.contains("+ ## Suministros"))
        #expect(transcript.contains("+ - Las facturas de la luz van a `10-Suministros/`."))
        #expect(transcript.contains("Se creará la carpeta 10-Suministros"))
        #expect(transcript.contains("[a] aplicar · [d] descartar"))
        #expect(transcript.contains("TRIA.md actualizado."))
        #expect(try rules(cli).hasSuffix(suministros))
        #expect(FileManager.default.fileExists(atPath: cli.dir.url.appendingPathComponent("10-Suministros").path))
    }

    @Test func askDiscardsWithD() async throws {
        let cli = try CLIHarness(provider: ScriptedProvider { _ in newSection }, answers: ["d"])
        _ = try WorkspaceFixture.make(in: cli.dir)
        #expect(try await cli.run(["rules", "ask", instruction]) == 0)
        #expect(cli.terminal.transcript.contains("Cambio descartado: TRIA.md sigue igual."))
        #expect(try rules(cli) == WorkspaceFixture.defaultRules)
        #expect(!FileManager.default.fileExists(atPath: cli.dir.url.appendingPathComponent("10-Suministros").path))
    }

    @Test func askWithYesAppliesWithoutAsking() async throws {
        let cli = try CLIHarness(provider: ScriptedProvider { _ in newSection }, interactive: false)
        _ = try WorkspaceFixture.make(in: cli.dir)
        #expect(try await cli.run(["rules", "ask", instruction, "-y"]) == 0)
        #expect(!cli.terminal.transcript.contains("[a] aplicar"))
        #expect(try rules(cli).hasSuffix(suministros))
    }

    @Test func askWithoutATerminalNeedsYesAndSendsNothing() async throws {
        let provider = ScriptedProvider { _ in newSection }
        let cli = try CLIHarness(provider: provider, interactive: false)
        _ = try WorkspaceFixture.make(in: cli.dir)
        #expect(try await cli.run(["rules", "ask", instruction]) == 2)
        #expect(cli.terminal.transcript.contains("Sin terminal interactiva"))
        #expect(await provider.requests.isEmpty)
    }

    @Test func aRefusalIsShownAndExitsWithOne() async throws {
        let why = "Eso se hace en el Finder; después dime cómo se llama y actualizo las reglas"
        let cli = try CLIHarness(provider: ScriptedProvider { _ in reply(refusal: why) }, answers: ["a"])
        _ = try WorkspaceFixture.make(in: cli.dir)
        #expect(try await cli.run(["rules", "ask", "Cambia 7-Facturas por Facturas"]) == 1)
        #expect(cli.terminal.transcript.contains("Tria no hace este cambio: \(why)"))
        #expect(try rules(cli) == WorkspaceFixture.defaultRules)
    }

    @Test func anAnswerThatCannotBeUsedSaysWhy() async throws {
        let cli = try CLIHarness(provider: ScriptedProvider { _ in "{}" }, answers: ["a"])
        _ = try WorkspaceFixture.make(in: cli.dir)
        #expect(try await cli.run(["rules", "ask", instruction]) == 2)
        #expect(cli.terminal.transcript.contains("Tria no ha devuelto un cambio que se pueda aplicar. Vuelve a probar."))
        let exists = try CLIHarness(provider: ScriptedProvider { _ in reply(sections: [("new", suministros)], folders: ["7-Facturas"]) },
                                    answers: ["a"])
        _ = try WorkspaceFixture.make(in: exists.dir)
        #expect(try await exists.run(["rules", "ask", instruction]) == 2)
        #expect(exists.terminal.transcript.contains("No puedo hacer ese cambio: la carpeta «7-Facturas» ya existe."))
    }

    @Test func folderNamesFromTheModelReachTheTerminalWithoutEscapeSequences() {
        let name = "Facturas\u{1B}[31mRojas"
        let errors: [RulesAskError] = [.unsafeFolder(name), .folderExists(name), .repeatedFolder(name), .protectedFolder(name)]
        for lang in [Lang.ca, .es, .en] {
            for error in errors {
                let message = L10n.describe(error, lang)
                #expect(!message.contains("\u{1B}"), "\(error) en \(lang)")
                #expect(message.contains("Facturas [31mRojas"))
            }
            #expect(!L10n.describe(RulesChangeError.unsafeFolder(name), lang).contains("\u{1B}"))
        }
    }

    @Test func protectingTheInboxOrCreatingAFolderInsideAProtectedOneSaysWhy() async throws {
        #expect(L10n.describe(RulesAskError.inboxProtected, .es)
                == "No puedo hacer ese cambio: la bandeja quedaría dentro de una ruta protegida.")
        #expect(L10n.describe(RulesAskError.duplicatesProtected, .ca)
                == "No puc fer aquest canvi: la carpeta de duplicats quedaria dins d'una ruta protegida.")
        #expect(L10n.describe(RulesAskError.protectedFolder("7-Facturas/2027"), .en)
                == "I can't make that change: the folder '7-Facturas/2027' is inside a protected path.")
        #expect(L10n.describe(RulesChangeError.inboxProtected, .es) == "La bandeja está dentro de una ruta protegida.")
        #expect(L10n.describe(RulesChangeError.duplicatesProtected, .es)
                == "La carpeta de duplicados está dentro de una ruta protegida.")
        let header: JSONValue = ["new_folders": "subfolders_only", "protected": ["99-Pendiente"]]
        let cli = try CLIHarness(provider: ScriptedProvider { _ in reply(header: header) }, answers: ["a"])
        _ = try WorkspaceFixture.make(in: cli.dir)
        #expect(try await cli.run(["rules", "ask", "No toques la bandeja"]) == 2)
        #expect(cli.terminal.transcript.contains("No puedo hacer ese cambio: la bandeja quedaría dentro de una ruta protegida."))
        #expect(try rules(cli) == WorkspaceFixture.defaultRules)
    }

    @Test func removedLinesAreRedAndAddedLinesGreen() async throws {
        let change = reply(sections: [("s2", "## Nomenclatura\nTodo en minúsculas.\n")])
        let cli = try CLIHarness(provider: ScriptedProvider { _ in change }, answers: ["d"], capabilities: .colored)
        _ = try WorkspaceFixture.make(in: cli.dir)
        #expect(try await cli.run(["rules", "ask", "Los nombres, en minúsculas"]) == 0)
        #expect(cli.terminal.output.contains("\u{1B}[38;5;131m- | Tipo | Formato | Ejemplo |\u{1B}[39m"))
        #expect(cli.terminal.output.contains("\u{1B}[38;5;65m+ Todo en minúsculas.\u{1B}[39m"))
        #expect(cli.terminal.output.contains("  ## Nomenclatura"))
    }

    @Test func whileAnotherProcessSortsTheChangeWaits() async throws {
        let cli = try CLIHarness(provider: ScriptedProvider { _ in newSection }, interactive: false)
        let ws = try WorkspaceFixture.make(in: cli.dir)
        let since = ISO8601DateFormatter().string(from: Date())
        try Data(#"{"pid":1,"host":"otro-mac","since":"\#(since)"}"#.utf8).write(to: ws.lockURL)
        #expect(try await cli.run(["rules", "ask", instruction, "-y"]) == 2)
        #expect(cli.terminal.transcript.contains("Ordenando desde otro sitio (el CLI u otro Mac)."))
        #expect(try rules(cli) == WorkspaceFixture.defaultRules)
    }
}
