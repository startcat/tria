import ArgumentParser
import TriaKit

public struct TriaCommand: AsyncParsableCommand {
    /// Calculada: la ayuda y la versión salen en el idioma del usuario (`L10n.help`).
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tria",
            abstract: L10n.help(.triaAbstract),
            version: L10n.versionLine(CLIEnvironment.current.lang),
            subcommands: [InitCommand.self, SortCommand.self, StatusCommand.self, UndoCommand.self, LogCommand.self,
                          RulesCommand.self, ConfigCommand.self, EvalCommand.self]
        )
    }

    public init() {}
}
