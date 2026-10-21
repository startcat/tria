import Foundation
import Testing
@testable import TriaKit

private let fullSL = """
---
kind: sl
name: "EMPRESA EJEMPLO SL"
tax_id: "B00000000"
trade_names: ["Ejemplo Norte"]
partners:
  - { name: "Ana Ejemplo Roca", tax_id: "00000000T" }
  - Joan Exemple Pou
clients:
  - { name: "ESTUDIO NORTE SL", short: "Estudio Norte" }
banks:
  - { name: "Banco Ejemplo", account_end: "1234" }
---
# Perfil — Empresa Ejemplo

Las facturas de la gestoría llegan a nombre de Ana, pero son de la sociedad.
"""

@Test func parsesEveryFieldOfAnSL() throws {
    let file = try ProfileFile.parse(fullSL)
    let profile = file.profile
    #expect(profile.kind == .sl)
    #expect(profile.name == "EMPRESA EJEMPLO SL")
    #expect(profile.taxID == "B00000000")
    #expect(profile.tradeNames == ["Ejemplo Norte"])
    #expect(profile.partners == [ProfilePerson(name: "Ana Ejemplo Roca", taxID: "00000000T"),
                                 ProfilePerson(name: "Joan Exemple Pou")])
    #expect(profile.clients == [ProfileClient(name: "ESTUDIO NORTE SL", short: "Estudio Norte")])
    #expect(profile.banks == [ProfileBank(name: "Banco Ejemplo", accountEnd: "1234")])
    #expect(profile.notes == "# Perfil — Empresa Ejemplo\n\nLas facturas de la gestoría llegan a nombre de Ana, pero son de la sociedad.")
    #expect(profile.isComplete)
    #expect(file.warnings.isEmpty)
    #expect(file.language == .es)
    #expect(file.raw == fullSL)
}

@Test func parsesAHousehold() throws {
    let file = try ProfileFile.parse("""
    ---
    kind: hogar
    members:
      - { name: "Ana Ejemplo Roca", tax_id: "00000000T" }
    vehicles:
      - { short: "Coche", plate: "0000 XXX" }
    homes:
      - { short: "Piso", address: "C/ Ejemplo 1, Girona" }
    ---
    """)
    #expect(file.profile.members == [ProfilePerson(name: "Ana Ejemplo Roca", taxID: "00000000T")])
    #expect(file.profile.vehicles == [ProfileVehicle(short: "Coche", plate: "0000 XXX")])
    #expect(file.profile.homes == [ProfileHome(short: "Piso", address: "C/ Ejemplo 1, Girona")])
    #expect(file.profile.isComplete)
}

@Test func theMinimumDependsOnTheKind() {
    var autonomo = Profile(kind: .autonomo, name: "Ana Ejemplo Roca")
    #expect(autonomo.missing == [.taxID])
    autonomo.taxID = "00000000T"
    #expect(autonomo.isComplete)
    #expect(Profile(kind: .sl).missing == [.name, .taxID])
    #expect(Profile(kind: .sl, name: "  ", taxID: "B00000000").missing == [.name])
    var hogar = Profile(kind: .hogar)
    #expect(hogar.missing == [.members])
    hogar.members = [ProfilePerson(name: "Ana")]
    #expect(hogar.isComplete)
}

@Test func errorsSayWhatAndWhere() {
    #expect(throws: ProfileError.missingFrontmatter) { try ProfileFile.parse("kind: sl\n") }
    #expect(throws: ProfileError.missingKind) { try ProfileFile.parse("---\nname: \"X\"\n---\n") }
    #expect(throws: ProfileError.missingKind) { try ProfileFile.parse("---\n---\n") }
    #expect(throws: ProfileError.unknownKind("empresa", line: 2)) { try ProfileFile.parse("---\nkind: empresa\n---\n") }
    #expect(throws: ProfileError.invalidValue(key: "partners", line: 5)) {
        try ProfileFile.parse("---\nkind: sl\nname: \"X\"\npartners:\n  - { nombre: \"Ana\" }\n---\n")
    }
    #expect(throws: ProfileError.invalidValue(key: "name", line: 3)) {
        try ProfileFile.parse("---\nkind: sl\nname: [\"A\", \"B\"]\n---\n")
    }
    do {
        _ = try ProfileFile.parse("---\nkind: sl\nname: \"sin cerrar\n---\n")
        Issue.record("debería fallar")
    } catch let ProfileError.invalidYAML(line, detail) {
        #expect(line != nil)
        #expect(!detail.isEmpty)
    } catch {
        Issue.record("error inesperado: \(error)")
    }
}

@Test func unknownKeysAndOtherKindsWarnButStay() throws {
    let file = try ProfileFile.parse("""
    ---
    kind: autonomo
    name: "Ana Ejemplo Roca"
    tax_id: "00000000T"
    partners:
      - Joan Exemple Pou
    web: https://ejemplo.com
    ---
    """)
    #expect(file.warnings == [.unknownKey("web"), .notForKind(.partners)])
    #expect(file.profile.partners == [ProfilePerson(name: "Joan Exemple Pou")])
    #expect(file.profile.extras.map(\.key) == ["web"])
    #expect(file.profile.extras.first?.yaml.hasPrefix("web:") == true)
}

@Test func readsCRLFAndBOM() throws {
    let text = "\u{FEFF}---\r\nkind: autonomo\r\nname: \"Ana Ejemplo Roca\"\r\ntax_id: \"00000000T\"\r\n---\r\nNotas\r\n"
    let file = try ProfileFile.parse(text)
    #expect(file.profile.name == "Ana Ejemplo Roca")
    #expect(file.profile.notes == "Notas")
    #expect(file.raw == text)
}

@Test func numberLikeValuesStayText() throws {
    let file = try ProfileFile.parse("""
    ---
    kind: autonomo
    name: 2026
    tax_id: ~
    trade_names: Ejemplo Norte
    banks:
      - { name: Banco Ejemplo, account_end: 0123 }
    ---
    """)
    #expect(file.profile.name == "2026")
    #expect(file.profile.taxID == nil)
    #expect(file.profile.tradeNames == ["Ejemplo Norte"])
    #expect(file.profile.banks == [ProfileBank(name: "Banco Ejemplo", accountEnd: "0123")])
}

@Test func theLanguageComesFromTheHeaderComment() throws {
    #expect(try ProfileFile.parse(Templates.profile(.sl, language: .ca)).language == .ca)
    #expect(try ProfileFile.parse(Templates.profile(.sl, language: .es)).language == .es)
    #expect(try ProfileFile.parse("---\nkind: sl\n---\n").language == .es)
}

@Test func theAutonomoTemplateHasAFixedShape() {
    #expect(Templates.profile(.autonomo, language: .es) == """
    ---
    # Perfil de Tria: quién es el titular de este archivo. Se envía al proveedor de IA con cada documento.
    # Las claves van en inglés. Debajo de la segunda línea ---, notas libres para Tria.
    # Tipo: autonomo, sl u hogar.
    kind: autonomo
    # Nombre y apellidos.
    name: ""
    # NIF.
    tax_id: ""
    # Nombres comerciales, si los hay: ["Nombre", "Otro nombre"].
    trade_names: []
    # Clientes habituales: - { name: "RAZÓN SOCIAL", short: "Nombre corto" }, para que carpetas y nombres salgan siempre iguales.
    clients: []
    # Bancos: - { name: "Banco", account_end: "1234" }, con los últimos dígitos de la cuenta, nunca el IBAN entero.
    banks: []
    ---

    """)
    #expect(Templates.profile(.autonomo, language: .ca).contains("# Nom i cognoms."))
}

@Test(arguments: TemplateKind.allCases, TemplateLanguage.allCases)
func everyProfileTemplateReadsBackEmpty(kind: TemplateKind, language: TemplateLanguage) throws {
    let file = try ProfileFile.parse(Templates.profile(kind, language: language))
    #expect(file.profile == Profile(kind: kind))
    #expect(file.language == language)
    #expect(file.warnings.isEmpty)
    #expect(!file.raw.contains("Daniel") && !file.raw.contains("Start.cat"))
}

@Test func renderKeepsEverythingAcrossARoundTrip() throws {
    var profile = Profile(kind: .sl, name: "ESTUDIO \"NORTE\": SL", taxID: "B00000000")
    profile.tradeNames = ["Norte & Cía", "Estudi Nord"]
    profile.partners = [ProfilePerson(name: "Àngels Exemple", taxID: "00000000T"), ProfilePerson(name: "Joan Exemple Pou")]
    profile.clients = [ProfileClient(name: "CLIENTE: EJEMPLO SL", short: "Cliente")]
    profile.banks = [ProfileBank(name: "Banco Ejemplo", accountEnd: "0123")]
    profile.vehicles = [ProfileVehicle(short: "Furgoneta", plate: "0000 XXX")]
    profile.notes = "Notas con --- dentro\nY otra línea."
    profile.extras = [ProfileExtra(key: "web", yaml: "web: ejemplo.com")]
    for language in TemplateLanguage.allCases {
        let file = try ProfileFile.parse(ProfileFile.render(profile, language: language))
        #expect(file.profile == profile)
        #expect(file.language == language)
        #expect(file.warnings == [.unknownKey("web"), .notForKind(.vehicles)])
    }
}

@Test func theHashFollowsTheText() throws {
    let a = try ProfileFile.parse(Templates.profile(.sl, language: .es))
    let b = try ProfileFile.parse(ProfileFile.render(Profile(kind: .sl, name: "EMPRESA EJEMPLO SL"), language: .es))
    #expect(a.hash != b.hash)
    #expect(a.hash == Hashing.sha256(a.raw))
}

@Test func readReturnsNilWithoutAFile() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perfil-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(try ProfileFile.read(in: dir) == nil)
    try Data(Templates.profile(.hogar, language: .es).utf8).write(to: dir.appendingPathComponent("PERFIL.md"))
    #expect(try ProfileFile.read(in: dir)?.profile.kind == .hogar)
}

@Test func anIndentedDashesInsideABlockScalarDoesNotCloseTheHeader() throws {
    let source = "---\nkind: sl\nweb: |\n  uno\n  ---\n  dos\nname: \"X\"\n---\nnotas\n"
    let file = try ProfileFile.parse(source)
    #expect(file.profile.name == "X")
    #expect(file.profile.extras.count == 1)
    #expect(file.profile.extras[0].yaml.contains("---"))
    #expect(file.profile.notes == "notas")
    let again = try ProfileFile.parse(ProfileFile.render(file.profile, language: .es))
    #expect(again.profile.extras.count == 1 && again.profile.extras[0].yaml.contains("  ---"))
    #expect(again.profile.notes == "notas")
}

@Test func anAllEmptyListItemIsSkippedButHalfEmptyIsAnError() throws {
    let file = try ProfileFile.parse("---\nkind: sl\npartners:\n  - { name: \"\", tax_id: \"\" }\n  - { name: \"Ana\" }\n---\n")
    #expect(file.profile.partners == [ProfilePerson(name: "Ana")])
    #expect(throws: ProfileError.self) {
        try ProfileFile.parse("---\nkind: sl\npartners:\n  - { tax_id: \"00000000T\" }\n---\n")
    }
}

@Test func theLanguageOfASpaceIsGuessedFromItsInbox() throws {
    for language in TemplateLanguage.allCases {
        let rules = try RulesFile.parse(Templates.text(.sl, language: language))
        #expect(TemplateLanguage.guess(from: rules) == language)
    }
}
