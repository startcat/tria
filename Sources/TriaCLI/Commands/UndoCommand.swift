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
        let all = try Journal(workspace: workspace).operations()
        let operations = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let index = JournalIndex(operations: all)
        for skipped in report.skipped {
            // Si el usuario movió lo que dejó Tria, se muestra dónde está ahora, no donde lo dejó Tria.
            let path = operations[skipped.operationID].map { $0.isUserMove ? $0.to : index.currentPath(of: $0) }
                ?? skipped.operationID
            switch skipped.reason {
            case .missing: env.say(.undoSkippedMissing, path)
            case .modified: env.say(.undoSkippedModified, path)
            case .unsafe: env.say(.undoSkippedUnsafe, path)
            case .failed(let message): env.say(.undoSkippedFailed, path, message)
            case .previousFolderUnavailable: env.say(.undoSkippedFolder, path)
            case .notMovable: env.say(.undoSkippedProtected, path)
            }
        }
        env.say(.undoDone, String(report.restored.count), String(report.skipped.count))
    }
}
