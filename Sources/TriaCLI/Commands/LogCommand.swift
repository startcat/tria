import ArgumentParser
import Foundation
import TriaKit

struct LogCommand: TriaSubcommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "log", abstract: L10n.help(.logAbstract))
    }

    @Argument(help: .catalog(.logBatch)) var batch: String?
    @Option(help: .catalog(.root)) var root: String?

    func execute(_ env: CLIEnvironment) async throws {
        let journal = Journal(workspace: try env.workspace(root: root))
        if let batch {
            for operation in try journal.operations() where operation.batch == batch {
                env.terminal.write(Presenter.operation(operation, env, style: env.style))
            }
            return
        }
        let batches = try journal.batches()
        if batches.isEmpty { env.say(.logEmpty) }
        for line in Presenter.batches(batches, env, style: env.style) { env.terminal.write(line) }
    }
}
