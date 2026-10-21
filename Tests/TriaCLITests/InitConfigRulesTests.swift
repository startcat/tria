import Foundation
import Testing
import TriaKit
import TriaTestSupport
@testable import TriaCLI

@Test func initWithATemplateCreatesRulesAndFolders() async throws {
    let cli = try CLIHarness()
    #expect(try await cli.run(["init", "--template", "sl", "--lang", "es"]) == 0)
    #expect(FileManager.default.fileExists(atPath: cli.dir.url.appendingPathComponent("TRIA.md").path))
    #expect(FileManager.default.fileExists(atPath: cli.dir.url.appendingPathComponent("1-Modelos Tributarios/Modelo 303 - IVA").path))
    #expect(cli.terminal.transcript.contains("Espacio creado"))
    #expect(try await cli.run(["init"]) == 0)
    #expect(cli.terminal.transcript.contains("Ya hay un TRIA.md"))
}

@Test func initWithoutChoicesNeedsATerminal() async throws {
    let cli = try CLIHarness(interactive: false)
    #expect(try await cli.run(["init"]) == 2)
    #expect(cli.terminal.transcript.contains("Sin terminal interactiva"))
}

@Test func initAsksForATemplateInAnEmptyFolder() async throws {
    let cli = try CLIHarness(answers: ["3"])
    #expect(try await cli.run(["init", "--lang", "ca"]) == 0)
    #expect(FileManager.default.fileExists(atPath: cli.dir.url.appendingPathComponent("10-Subministraments").path))
}

@Test func initLearnsRulesFromAnExistingFolder() async throws {
    let cli = try CLIHarness(provider: ScriptedProvider { _ in draftJSON })
    try cli.dir.write("Facturas/Factura Luz - 2025-01-10.txt", "Factura de luz")
    #expect(try await cli.run(["init", "--learn", "--yes"]) == 0)
    let rules = try Workspace.open(at: cli.dir.url).rules
    #expect(rules.body.contains("# Reglas aprendidas"))
}

@Test func missingKeyIsExplained() async throws {
    let cli = try CLIHarness(key: nil)
    try cli.dir.write("Facturas/a.txt", "a")
    #expect(try await cli.run(["init", "--learn", "--yes"]) == 2)
    #expect(cli.terminal.transcript.contains("ANTHROPIC_API_KEY"))
}

@Test func configSavesProviderModelAndKey() async throws {
    let cli = try CLIHarness(answers: ["sk-openai-123456789"])
    #expect(try await cli.run(["config", "--provider", "openai", "--model", "gpt-5.4-nano", "--set-key"]) == 0)
    #expect(try UserConfig.load(from: cli.env.configURL) == UserConfig(provider: .openai, model: "gpt-5.4-nano"))
    #expect(try cli.secrets.apiKey(for: .openai) == "sk-openai-123456789")
    #expect(cli.terminal.transcript.contains("Proveedor: openai · modelo: gpt-5.4-nano · key: sk-ope…6789"))
}

@Test func rulesCheckWarnsAboutUnmatchedProtectedPatterns() async throws {
    let cli = try CLIHarness()
    let rules = WorkspaceFixture.defaultRules.replacingOccurrences(of: "  - \"7-Facturas/20*/\"",
                                                                   with: "  - \"7-Facturas/20*/\"\n  - \"Archivo Viejo/*\"")
    _ = try WorkspaceFixture.make(in: cli.dir, rules: rules)
    #expect(try await cli.run(["rules", "check"]) == 0)
    #expect(cli.terminal.transcript.contains("«Archivo Viejo/*» no coincide con ninguna carpeta"))
    #expect(cli.terminal.transcript.contains("TRIA.md es válido."))
}

@Test func rulesCheckFailsOnInvalidRules() async throws {
    let cli = try CLIHarness()
    try cli.dir.write("TRIA.md", "sin cabecera")
    #expect(try await cli.run(["rules", "check"]) == 2)
    #expect(cli.terminal.transcript.contains("TRIA.md no es válido"))
}

@Test func rulesLearnWritesADraftAndLeavesTRIAAlone() async throws {
    let cli = try CLIHarness(provider: ScriptedProvider { _ in draftJSON })
    let ws = try WorkspaceFixture.make(in: cli.dir)
    try cli.dir.write("7-Facturas/Recibidas/Factura Luz - 2025-01-10.txt", "Factura de luz")
    #expect(try await cli.run(["rules", "learn", "--yes"]) == 0)
    #expect(FileManager.default.fileExists(atPath: cli.dir.url.appendingPathComponent("TRIA.draft.md").path))
    #expect(try ws.reloaded().rules.raw == WorkspaceFixture.defaultRules)
}

@Test func suggestionsCanBeListedAppliedAndDiscarded() async throws {
    let cli = try CLIHarness()
    let ws = try WorkspaceFixture.make(in: cli.dir)
    let store = SuggestionStore(workspace: ws)
    let keep = RuleSuggestion(draft: RuleSuggestionDraft(section: "Nomenclatura", rule: "Los recibos llevan el mes."), context: "a.pdf")
    let drop = RuleSuggestion(draft: RuleSuggestionDraft(section: "Nomenclatura", rule: "Regla mala."), context: "b.pdf")
    try store.add(keep)
    try store.add(drop)
    #expect(try await cli.run(["rules", "suggestions"]) == 0)
    #expect(cli.terminal.transcript.contains(keep.id))
    #expect(try await cli.run(["rules", "suggestions", "--apply", keep.id]) == 0)
    #expect(try ws.reloaded().rules.body.contains("- Los recibos llevan el mes."))
    #expect(try await cli.run(["rules", "suggestions", "--discard", drop.id]) == 0)
    #expect(try store.list().isEmpty)
}

@Test func rulesCheckRejectsAProtectedDuplicatesFolder() async throws {
    let cli = try CLIHarness()
    let rules = WorkspaceFixture.defaultRules.replacingOccurrences(of: "  - \"7-Facturas/20*/\"",
                                                                   with: "  - \"7-Facturas/20*/\"\n  - \"98*\"")
    _ = try WorkspaceFixture.make(in: cli.dir, rules: rules)
    #expect(try await cli.run(["rules", "check"]) == 2)
    #expect(cli.terminal.transcript.contains("La carpeta de duplicados está dentro de una ruta protegida."))
}

@Test func aBrokenProfileIsExplainedWithItsLine() async throws {
    let cli = try CLIHarness()
    #expect(try await cli.run(["init", "--template", "sl", "--lang", "es", "--yes"]) == 0)
    try cli.dir.write("PERFIL.md", "---\nkind: empresa\n---\n")
    #expect(try await cli.run(["status"]) == 2)
    #expect(cli.terminal.transcript.contains("PERFIL.md no es válido: línea 2: el tipo «empresa» no existe"))
}

@Test func initWithATemplateAlsoCreatesTheProfile() async throws {
    let cli = try CLIHarness()
    #expect(try await cli.run(["init", "--template", "sl", "--lang", "es", "--yes"]) == 0)
    let profile = try #require(try Workspace.open(at: cli.dir.url).profile)
    #expect(profile.profile.kind == .sl)
    #expect(profile.language == .es)
    #expect(cli.terminal.transcript.contains("rellénalo para que Tria sepa quién es el titular"))
}

@Test func initAsksTheMinimumInATerminal() async throws {
    let cli = try CLIHarness(answers: ["2", "EMPRESA EJEMPLO SL", "B00000000"])
    #expect(try await cli.run(["init", "--lang", "es"]) == 0)
    let profile = try #require(try Workspace.open(at: cli.dir.url).profile?.profile)
    #expect(profile.name == "EMPRESA EJEMPLO SL" && profile.taxID == "B00000000")
    #expect(cli.terminal.transcript.contains("Razón social"))
    #expect(cli.terminal.transcript.contains("Tria ya sabe quién es el titular"))
}

@Test func aHouseholdAsksForAMemberInCatalan() async throws {
    let cli = try CLIHarness(answers: ["3", "Ana Ejemplo Roca"])
    #expect(try await cli.run(["init", "--lang", "ca"]) == 0)
    let file = try #require(try Workspace.open(at: cli.dir.url).profile)
    #expect(file.profile.members == [ProfilePerson(name: "Ana Ejemplo Roca")])
    #expect(file.language == .ca)
}

@Test func anExistingSpaceGainsAProfileWithATemplate() async throws {
    let cli = try CLIHarness()
    #expect(try await cli.run(["init", "--template", "autonomo", "--lang", "es", "--yes"]) == 0)
    try FileManager.default.removeItem(at: cli.dir.url.appendingPathComponent("PERFIL.md"))
    #expect(try await cli.run(["init"]) == 0)
    #expect(cli.terminal.transcript.contains("no hay PERFIL.md"))
    #expect(try await cli.run(["init", "--template", "autonomo", "--yes"]) == 0)
    #expect(try Workspace.open(at: cli.dir.url).profile?.profile.kind == .autonomo)
}

@Test func rulesCheckReviewsTheProfile() async throws {
    let cli = try CLIHarness()
    #expect(try await cli.run(["init", "--template", "sl", "--lang", "es", "--yes"]) == 0)
    #expect(try await cli.run(["rules", "check"]) == 0)
    #expect(cli.terminal.transcript.contains("a PERFIL.md le falta el nombre y el NIF"))
    try cli.dir.write("PERFIL.md", """
    ---
    kind: sl
    name: "EMPRESA EJEMPLO SL"
    tax_id: "B12345675"
    vehicles:
      - Coche
    web: https://ejemplo.com
    ---
    """)
    #expect(try await cli.run(["rules", "check"]) == 0)
    let transcript = cli.terminal.transcript
    #expect(transcript.contains("tiene la clave «web»"))
    #expect(transcript.contains("la clave «vehicles» no es del tipo «sl»"))
    #expect(transcript.contains("el NIF «B12345675» no parece correcto"))
    #expect(transcript.contains("TRIA.md y PERFIL.md son válidos"))
}

@Test func rulesCheckWithoutAProfileWarns() async throws {
    let cli = try CLIHarness()
    #expect(try await cli.run(["init", "--template", "hogar", "--lang", "es", "--yes"]) == 0)
    try FileManager.default.removeItem(at: cli.dir.url.appendingPathComponent("PERFIL.md"))
    #expect(try await cli.run(["rules", "check"]) == 0)
    #expect(cli.terminal.transcript.contains("no hay PERFIL.md"))
    #expect(cli.terminal.transcript.contains("TRIA.md es válido"))
}

@Test func statusWarnsAboutAnIncompleteProfileOnStandardError() async throws {
    let cli = try CLIHarness()
    #expect(try await cli.run(["init", "--template", "sl", "--lang", "es", "--yes"]) == 0)
    #expect(try await cli.run(["status"]) == 0)
    #expect(cli.terminal.transcript.contains("a PERFIL.md le falta el nombre y el NIF"))
    #expect(!cli.terminal.output.contains("le falta"))
}

/// `status` avisa del NIF que no cuadra con el mismo texto que `rules check`, por la salida de error como los otros
/// avisos del perfil; con un NIF que cuadra o sin `PERFIL.md`, no.
@Test func statusWarnsAboutAWrongTaxIDLikeRulesCheck() async throws {
    let cli = try CLIHarness()
    #expect(try await cli.run(["init", "--template", "autonomo", "--lang", "es", "--yes"]) == 0)
    let warning = "Aviso: el NIF «00000000A» no parece correcto (la letra o el dígito de control no cuadran)."
    try cli.dir.write("PERFIL.md", "---\nkind: autonomo\nname: \"Ana Ejemplo Roca\"\ntax_id: \"00000000A\"\n---\n")
    #expect(try await cli.run(["status"]) == 0)
    #expect(cli.terminal.transcript.contains(warning))
    #expect(!cli.terminal.output.contains("no parece correcto"))

    let valid = try CLIHarness()
    #expect(try await valid.run(["init", "--template", "autonomo", "--lang", "es", "--yes"]) == 0)
    try valid.dir.write("PERFIL.md", "---\nkind: autonomo\nname: \"Ana Ejemplo Roca\"\ntax_id: \"00000000T\"\n---\n")
    let afterInit = valid.terminal.transcript.count
    #expect(try await valid.run(["status"]) == 0)
    // Solo lo que dice `status`: con un perfil completo y un NIF que cuadra, ningún aviso.
    #expect(!valid.terminal.transcript.dropFirst(afterInit).contains("Aviso:"))

    let none = try CLIHarness()
    #expect(try await none.run(["init", "--template", "autonomo", "--lang", "es", "--yes"]) == 0)
    try FileManager.default.removeItem(at: none.dir.url.appendingPathComponent("PERFIL.md"))
    #expect(try await none.run(["status"]) == 0)
    #expect(none.terminal.transcript.contains("no hay PERFIL.md"))
    #expect(!none.terminal.transcript.contains("no parece correcto"))
}

@Test func initKeepsAnExistingProfileWithoutTRIA() async throws {
    let cli = try CLIHarness()
    let filled = "---\nkind: sl\nname: \"EMPRESA EJEMPLO SL\"\ntax_id: \"B00000000\"\npartners:\n  - { name: \"Ana Ejemplo Roca\" }\nweb: \"ejemplo.test\"\n---\nNotas mías.\n"
    try cli.dir.write("PERFIL.md", filled)
    #expect(try await cli.run(["init", "--template", "sl", "--lang", "es", "--yes"]) == 0)
    let after = try String(contentsOf: cli.dir.url.appendingPathComponent("PERFIL.md"), encoding: .utf8)
    #expect(after == filled)
    #expect(cli.terminal.transcript.contains("Se mantiene el PERFIL.md que ya había."))
}

@Test func interactiveInitDoesNotAskTheProfileWhenItExists() async throws {
    let cli = try CLIHarness(answers: ["n", "2"])
    let filled = "---\nkind: sl\nname: \"EMPRESA EJEMPLO SL\"\n---\n"
    try cli.dir.write("PERFIL.md", filled)
    #expect(try await cli.run(["init", "--lang", "es"]) == 0)
    #expect(!cli.terminal.transcript.contains("Razón social"))
    #expect(try String(contentsOf: cli.dir.url.appendingPathComponent("PERFIL.md"), encoding: .utf8) == filled)
}
