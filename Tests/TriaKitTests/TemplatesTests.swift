import Testing
@testable import TriaKit

@Test(arguments: TemplateKind.allCases, TemplateLanguage.allCases)
func everyTemplateParsesAndListsItsFolders(kind: TemplateKind, language: TemplateLanguage) throws {
    let text = Templates.text(kind, language: language)
    let rules = try RulesFile.parse(text)
    #expect(rules.header.newFolders == .subfoldersOnly)
    #expect(rules.header.inbox == (language == .es ? "99-Pendiente" : "99-Pendent"))
    #expect(rules.header.duplicates == (language == .es ? "98-Duplicados" : "98-Duplicats"))
    let folders = Templates.folders(kind, language: language)
    #expect(!folders.isEmpty)
    for folder in folders where !folder.contains("/") {
        #expect(text.contains("`\(folder)/`"), "La tabla de carpetas no menciona \(folder)")
    }
}

@Test func slTemplateMatchesTheSyntheticArchive() {
    let folders = Templates.folders(.sl, language: .es)
    for folder in ["1-Modelos Tributarios/Modelo 303 - IVA", "1-Modelos Tributarios/Modelo 111 - IRPF Retenciones",
                   "2-Contratos/Renting", "3-Actas y Documentos Societarios/Actas de Junta", "4-Correspondencia Bancaria",
                   "5-Ordenes Domiciliacion", "7-Facturas/Emitidas", "7-Facturas/Recibidas", "8-Nominas",
                   "9-Certificados", "10-Notificaciones AEAT", "15-Proteccion de Datos/Politicas Web"] {
        #expect(folders.contains(folder), "Falta \(folder)")
    }
}

@Test func templatesNeverNamePeople() {
    for kind in TemplateKind.allCases {
        for language in TemplateLanguage.allCases {
            let text = Templates.text(kind, language: language)
            #expect(!text.contains("Daniel") && !text.contains("Startcat") && !text.contains("Start.cat"))
        }
    }
}

@Test(arguments: TemplateKind.allCases, TemplateLanguage.allCases)
func rulesTalkAboutTheProfile(kind: TemplateKind, language: TemplateLanguage) {
    #expect(Templates.text(kind, language: language).contains("del perfil"))
}
