import Testing
import TriaKit
@testable import TriaCLI

@Test(arguments: [Lang.ca, .es, .en])
func cliVersionIsTheTranslatedVersionLine(_ lang: Lang) {
    let configuration = CLIEnvironment.$current.withValue(helpEnvironment(lang)) { TriaCommand.configuration }
    #expect(configuration.version == L10n.versionLine(lang))
    #expect(configuration.commandName == "tria")
}
