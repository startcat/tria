import ArgumentParser
import TriaKit

struct UndoCommand: TriaSubcommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "undo", abstract: L10n.help(.undoAbstract))
    }

    @Argument(help: .catalog(.undoBatch)) var batch: String?
    @Flag(help: .catalog(.undoLast)) var last = false
    @Option(help: .catalog(.root)) var root: String?

    func execute(_ env: CLIEnvironment) async throws {
        let workspace = try env.workspace(root: root)
        let lock = try WorkspaceLock.acquire(workspace)
        defer { lock.release() }
        let undoer = Undoer(workspace: workspace)
        let report = try batch.map { try undoer.undo(batch: $0) } ?? undoer.undoLast()
        guard let report, !(report.restored.isEmpty && report.skipped.isEmpty) else {
            env.say(.undoNothing)
            return
        }
        let operations = Dictionary(try Journal(workspace: workspace).operations().map { ($0.id, $0) },
                                    uniquingKeysWith: { first, _ in first })
        for skipped in report.skipped {
            let path = operations[skipped.operationID]?.to ?? skipped.operationID
            switch skipped.reason {
            case .missing: env.say(.undoSkippedMissing, path)
            case .modified: env.say(.undoSkippedModified, path)
            case .unsafe: env.say(.undoSkippedUnsafe, path)
            case .failed(let message): env.say(.undoSkippedFailed, path, message)
            }
        }
        env.say(.undoDone, String(report.restored.count), String(report.skipped.count))
    }
}
