import ArgumentParser
import Testing
import TriaKit
@testable import TriaCLI

@Test(arguments: [Lang.ca, .es, .en])
func rootHelpFollowsTheLanguage(_ lang: Lang) {
    let help = CLIEnvironment.$current.withValue(helpEnvironment(lang)) {
        TriaCommand.helpMessage(columns: 10_000)
    }
    #expect(help.contains(L10n.help(.triaAbstract, lang)))
}

@Test func versionLineIsTranslated() {
    #expect(L10n.versionLine(.en) == "tria \(TriaInfo.version) — A Start.cat product · https://start.cat")
    #expect(L10n.versionLine(.ca) == "tria \(TriaInfo.version) — Un producte de Start.cat · https://start.cat")
    #expect(L10n.versionLine(.es) == TriaInfo.versionLine)
}

@Test func triaLangIgnoresCaseAndRegion() {
    #expect(Lang.detect(environment: ["TRIA_LANG": "EN"], preferred: ["es-ES"]) == .en)
    #expect(Lang.detect(environment: ["TRIA_LANG": "ca_ES"], preferred: ["en-US"]) == .ca)
    #expect(Lang.detect(environment: ["TRIA_LANG": "fr"], preferred: ["ca-ES"]) == .ca)
}

/// Todos los comandos, también los anidados, sacados de la propia configuración: uno nuevo entra solo en las pruebas.
let allCommands: [ParsableCommand.Type] = {
    func walk(_ command: ParsableCommand.Type) -> [ParsableCommand.Type] {
        [command] + command.configuration.subcommands.flatMap(walk)
    }
    return walk(TriaCommand.self)
}()

@Test func allCommandsIncludesTheNestedOnes() {
    let names = allCommands.map { String(describing: $0) }
    #expect(names.count == 13)
    #expect(names.contains("Ask") && names.contains("Suggestions"))
}

private func help(_ command: ParsableCommand.Type, _ lang: Lang) -> String {
    CLIEnvironment.$current.withValue(helpEnvironment(lang)) {
        TriaCommand.helpMessage(for: command, columns: 10_000)
    }
}

@Test(arguments: [Lang.ca, .en])
func noSpanishHelpLeaksIntoOtherLanguages(_ lang: Lang) {
    for command in allCommands {
        let text = help(command, lang)
        for key in HelpKey.allCases where L10n.help(key, .es) != L10n.help(key, lang) {
            #expect(!text.contains(L10n.help(key, .es)), "\(command) en \(lang): \(key)")
        }
    }
}

@Test func helpHasNoSpanishWordsOutsideTheCatalog() {
    // Lo que no pasa por el catálogo: una frase en castellano escrita a mano en un comando.
    let spanish = /\b(los|las|para|con|sin|del|una|que|ningún|también)\b|[áéíóúñ¿¡]/
    for command in allCommands {
        #expect(help(command, .en).firstMatch(of: spanish) == nil, "\(command)")
    }
}

@Test(arguments: [Lang.ca, .es, .en])
func nestedHelpFollowsTheLanguage(_ lang: Lang) {
    #expect(help(RulesCommand.Ask.self, lang).contains(L10n.help(.rulesAskAbstract, lang)))
}
