import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

struct RulesAskerTests {
    private func ask(_ answer: String, _ dir: TempDir,
                     rules: String = WorkspaceFixture.defaultRules) async throws -> (RulesAskResult, TokenUsage, Workspace) {
        let ws = try WorkspaceFixture.make(in: dir, rules: rules)
        let (result, usage) = try await RulesAsker(provider: ScriptedProvider { _ in answer })
            .ask("Las facturas de la luz van a Suministros", in: ws)
        return (result, usage, ws)
    }

    /// El motivo de una respuesta que no se puede proponer; falla si se propone.
    private func reason(_ answer: String, rules: String = WorkspaceFixture.defaultRules) async throws -> RulesAskError? {
        let dir = try TempDir()
        do {
            _ = try await ask(answer, dir, rules: rules)
            Issue.record("Se ha propuesto un cambio que no vale")
            return nil
        } catch let failure as RulesAskFailure {
            #expect(failure.usage == TokenUsage(inputTokens: 100, outputTokens: 10), "Lo que costó se cuenta")
            return failure.reason
        }
    }

    @Test func aGoodChangeIsPreparedButNothingIsTouched() async throws {
        let dir = try TempDir()
        let (result, usage, ws) = try await ask(reply(sections: [("new", suministros)], folders: ["10-Suministros"]), dir)
        guard case .change(let change) = result else { Issue.record("\(result)"); return }
        #expect(change.summary == "Las facturas de la luz van a 10-Suministros")
        #expect(change.createFolders == ["10-Suministros"])
        #expect(change.baseHash == ws.rules.hash)
        #expect(change.newText.hasSuffix(suministros))
        #expect(change.preview.map(\.kind) == [.added])
        _ = try RulesFile.parse(change.newText)
        #expect(usage == TokenUsage(inputTokens: 100, outputTokens: 10))
        #expect(try String(contentsOf: ws.rulesURL, encoding: .utf8) == WorkspaceFixture.defaultRules)
        #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("10-Suministros").path))
    }

    @Test func aChangedSectionIsReplacedInItsPlace() async throws {
        let dir = try TempDir()
        let (result, _, ws) = try await ask(reply(sections: [("s2", "## Nomenclatura\nTodo en minúsculas.\n")]), dir)
        guard case .change(let change) = result else { Issue.record("\(result)"); return }
        let document = RulesDocument.parse(ws.rules.raw)
        #expect(change.newText == document.frontmatter + document.preamble + document.sections[0].text
                + "## Nomenclatura\nTodo en minúsculas.")
        #expect(change.preview.map(\.kind) == [.changed])
        #expect(change.preview[0].title == "Nomenclatura")
    }

    @Test func twoNewSectionsAreFine() async throws {
        let dir = try TempDir()
        let (result, _, _) = try await ask(reply(sections: [("new", "## A\n- a\n"), ("new", "## B\n- b\n")]), dir)
        guard case .change(let change) = result else { Issue.record("\(result)"); return }
        #expect(change.preview.map(\.title) == ["A", "B"])
    }

    @Test func theRequestCarriesNumberedSectionsTreeAndProfileButNoDocument() async throws {
        let dir = try TempDir()
        var ws = try WorkspaceFixture.make(in: dir)
        ws = try ws.saveProfile(Profile(kind: .sl, name: "EMPRESA EJEMPLO SL", taxID: "B00000000"), language: .es)
        try dir.write("99-Pendiente/factura.txt", "Contenido que no se envía")
        let provider = ScriptedProvider { _ in reply(sections: [("new", suministros)]) }
        _ = try await RulesAsker(provider: provider).ask("  Las facturas de la luz van a Suministros\n", in: ws)
        let request = try #require(await provider.requests.first)
        #expect(request.schemaName == "tria_rules_change")
        #expect(request.system == RulesAsker.systemPrompt)
        #expect(request.cachedContext.contains("<<<SECTION s1\n## Carpetas"))
        #expect(request.cachedContext.contains("<<<SECTION s2\n## Nomenclatura"))
        // Está en el árbol de carpetas y no en TRIA.md; la protegida lleva su marca.
        #expect(request.cachedContext.contains("Modelo 303 - IVA/"))
        #expect(!ws.rules.raw.contains("Modelo 303 - IVA"))
        #expect(request.cachedContext.contains("2013/ [protected]"))
        #expect(request.cachedContext.contains("EMPRESA EJEMPLO SL"))
        #expect(!request.cachedContext.contains("Contenido que no se envía"))
        #expect(!request.userText.contains("Contenido que no se envía"))
        #expect(request.userText.contains("<<<REQUEST\nLas facturas de la luz van a Suministros\nREQUEST>>>"))
    }

    @Test func aRefusalChangesNothing() async throws {
        let dir = try TempDir()
        let why = "Eso se hace en el Finder; después dime cómo se llama y actualizo las reglas"
        let (result, _, _) = try await ask(reply(refusal: why, sections: [("new", suministros)]), dir)
        #expect(result == .refused(why))
    }

    @Test func aBrokenHeaderIsRejected() async throws {
        let header: JSONValue = ["new_folders": "never", "protected": ["../fuera"]]
        #expect(try await reason(reply(header: header)) == .invalidRules(.unsafePath(key: "protected", value: "../fuera")))
    }

    @Test func changingTheInboxOrTheDuplicatesIsRejected() async throws {
        let inbox: JSONValue = ["new_folders": "subfolders_only", "protected": [], "inbox": "Entrada"]
        #expect(try await reason(reply(header: inbox)) == .inboxChanged)
        let duplicates: JSONValue = ["new_folders": "subfolders_only", "protected": [], "duplicates": "Repes"]
        #expect(try await reason(reply(header: duplicates)) == .duplicatesChanged)
    }

    @Test(arguments: ["../fuera", "/tmp/fuera", ".tria/x", "99-Pendiente/sub", "98-Duplicados", "~/x", " "])
    func unsafeFoldersAreRejected(_ folder: String) async throws {   // Review Focus 3
        #expect(try await reason(reply(sections: [("new", suministros)], folders: [folder])) == .unsafeFolder(folder))
    }

    @Test func aFolderThatExistsOrRepeatsIsRejected() async throws {   // Review Focus 3
        #expect(try await reason(reply(folders: ["7-Facturas"])) == .folderExists("7-Facturas"))
        // El disco del Mac no distingue mayúsculas: «7-facturas» ya existe.
        #expect(try await reason(reply(folders: ["7-facturas"])) == .folderExists("7-facturas"))
        #expect(try await reason(reply(folders: ["Suministros/", "suministros"])) == .repeatedFolder("suministros"))
    }

    @Test func unknownRepeatedOrDoubleSectionsAreRejected() async throws {
        #expect(try await reason(reply(sections: [("s9", "## X\n")])) == .unknownSection("s9"))
        #expect(try await reason(reply(sections: [("s1", "## Carpetas\n- a\n"), ("s1", "## Carpetas\n- b\n")]))
                == .repeatedSection("s1"))
        #expect(try await reason(reply(sections: [("s1", "## Carpetas\n- a\n## Otra\n- b\n")])) == .notOneSection("s1"))
    }

    @Test func aSectionThatLeavesACodeBlockOpenIsRejected() async throws {
        #expect(try await reason(reply(sections: [("s1", "## Carpetas\n```\n- a\n")])) == .notOneSection("s1"))
        #expect(try await reason(reply(sections: [("new", "## Ejemplos\n~~~\n## Otra\n")])) == .notOneSection("new"))
    }

    @Test func aNewSectionAfterAnOpenCodeBlockIsRejected() async throws {
        // Un TRIA.md escrito a mano que acaba con un bloque abierto: la sección nueva quedaría dentro al volver a leerlo.
        let rules = WorkspaceFixture.defaultRules + "\n\n## Ejemplos\n```\n## no es una sección\n"
        #expect(try await reason(reply(sections: [("new", suministros)]), rules: rules) == .notOneSection("new"))
        // Cambiar otra sección sí vale: lo de detrás no cambia.
        let dir = try TempDir()
        let (result, _, _) = try await ask(reply(sections: [("s2", "## Nomenclatura\nTodo en minúsculas.\n")]), dir,
                                           rules: rules)
        guard case .change(let change) = result else { Issue.record("\(result)"); return }
        #expect(change.preview.map(\.title) == ["Nomenclatura"])
    }

    @Test func aHeaderThatProtectsTheInboxOrTheDuplicatesIsRejected() async throws {
        let inbox: JSONValue = ["new_folders": "subfolders_only", "protected": ["7-Facturas/20*/", "99-Pendiente"]]
        #expect(try await reason(reply(header: inbox)) == .inboxProtected)
        let everything: JSONValue = ["new_folders": "subfolders_only", "protected": ["*"]]
        #expect(try await reason(reply(header: everything)) == .inboxProtected)
        let duplicates: JSONValue = ["new_folders": "never", "protected": ["98-duplicados/"]]
        #expect(try await reason(reply(header: duplicates)) == .duplicatesProtected)
    }

    @Test func aFolderInsideAProtectedOneIsRejected() async throws {
        // «7-Facturas/20*/» ya está protegida: Tria no crea nada dentro.
        #expect(try await reason(reply(sections: [("new", suministros)], folders: ["7-Facturas/2027"]))
                == .protectedFolder("7-Facturas/2027"))
        #expect(try await reason(reply(folders: ["7-facturas/2027/1T"])) == .protectedFolder("7-facturas/2027/1T"))
        // Ni dentro de la que protege el mismo cambio.
        let header: JSONValue = ["new_folders": "subfolders_only", "protected": ["7-Facturas/20*/", "8-Certificados"]]
        #expect(try await reason(reply(header: header, folders: ["8-Certificados/2026"]))
                == .protectedFolder("8-Certificados/2026"))
        // Una que deja de estar protegida en el mismo cambio, sí.
        let dir = try TempDir()
        let unprotect: JSONValue = ["new_folders": "subfolders_only", "protected": []]
        let (result, _, _) = try await ask(reply(header: unprotect, folders: ["7-Facturas/2027"]), dir)
        guard case .change(let change) = result else { Issue.record("\(result)"); return }
        #expect(change.createFolders == ["7-Facturas/2027"])
    }

    @Test func aGoodHeaderChangeIsPreviewedWithTheHeader() async throws {
        let dir = try TempDir()
        let header: JSONValue = ["new_folders": "never", "protected": ["7-Facturas/20*/"]]
        let (result, _, ws) = try await ask(reply(header: header), dir)
        guard case .change(let change) = result else { Issue.record("\(result)"); return }
        #expect(change.preview.map(\.kind) == [.header])
        #expect(change.preview[0].lines.contains(.removed("new_folders: subfolders_only")))
        #expect(change.preview[0].lines.contains(.added("new_folders: never")))
        let rules = try RulesFile.parse(change.newText)
        #expect(rules.header.newFolders == .never)
        #expect(rules.header.inbox == ws.rules.header.inbox && rules.header.duplicates == ws.rules.header.duplicates)
        // Lo de debajo de la cabecera, igual.
        let body = { (text: String) in RulesDocument.parse(text).sections.map(\.text).joined() }
        #expect(body(change.newText) == body(ws.rules.raw))
    }

    @Test func aHeaderLikeTheCurrentOneKeepsItsBytes() async throws {
        let dir = try TempDir()
        // La misma cabecera, con el patrón sin la barra del final, y un cambio en una sección.
        let header: JSONValue = ["new_folders": "subfolders_only", "protected": ["7-Facturas/20*"]]
        let (result, _, ws) = try await ask(reply(sections: [("s2", "## Nomenclatura\nTodo en minúsculas.\n")],
                                                  header: header), dir)
        guard case .change(let change) = result else { Issue.record("\(result)"); return }
        let frontmatter = RulesDocument.parse(ws.rules.raw).frontmatter
        #expect(change.newText.hasPrefix(frontmatter))
        #expect(RulesDocument.parse(change.newText).frontmatter == frontmatter)
        #expect(change.preview.map(\.kind) == [.changed])
    }

    @Test func anAnswerThatIsNotJSONOrChangesNothingIsRejected() async throws {
        guard case .invalidResponse? = try await reason("No sé hacer eso") else { Issue.record("no es invalidResponse"); return }
        #expect(try await reason(reply()) == .noChange)
    }

    @Test func theCostIsEstimatedWithTheConfiguredModel() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        let asker = RulesAsker(provider: ScriptedProvider { _ in "" })
        #expect((asker.estimatedCost(for: ws, model: "claude-sonnet-5-5") ?? 0) > 0)
        #expect(asker.estimatedCost(for: ws, model: "modelo-sin-precio") == nil)
    }

    @Test func aSectionCanBeReadBackFromTheContext() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        let context = try RulesAsker.cachedContext(for: ws)
        #expect(RulesAsker.sectionText("s2", inContext: context)?.hasPrefix("## Nomenclatura\n| Tipo |") == true)
        #expect(RulesAsker.sectionText("s9", inContext: context) == nil)
    }

    @Test func summaryRuleAsksForTheWordsOfTheApp() {   // nunca los valores técnicos de la cabecera
        let prompt = RulesAsker.systemPrompt
        #expect(prompt.contains("Never write the header values (never, subfolders_only, anywhere)"))
        #expect(prompt.contains("\"Nunca\", \"Solo subcarpetas (año, trimestre…)\" and \"Donde haga falta\""))
    }
}
