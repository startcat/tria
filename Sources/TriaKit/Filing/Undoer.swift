import Foundation

public struct SkippedUndo: Sendable, Equatable {
    public enum Reason: Sendable, Hashable {
        case missing, modified
        /// La entrada del journal no es de fiar: ruta fuera del espacio, oculta o sin hash.
        case unsafe
        case failed(String)
    }
    public var operationID: String
    public var reason: Reason
}

public struct UndoReport: Sendable, Equatable {
    public var restored: [AppliedMove]
    public var skipped: [SkippedUndo]
}

/// Devuelve los ficheros a su sitio si siguen donde Tria los dejó y no han cambiado. Nunca sobrescribe.
public struct Undoer: Sendable {
    public let workspace: Workspace
    public let journal: Journal

    public init(workspace: Workspace) {
        self.workspace = workspace
        self.journal = Journal(workspace: workspace)
    }

    public func undo(batch: String) throws -> UndoReport {
        _ = try journal.reconcile()
        let operations = try journal.operations().filter { $0.batch == batch && $0.state == .done }
        return try restore(Array(operations.reversed()))
    }

    /// Deshace una sola operación: «Deshacer y devolver a la bandeja» en la app (spec de la app, §5.2).
    public func undo(operation id: String) throws -> UndoReport {
        _ = try journal.reconcile()
        return try restore(try journal.operations().filter { $0.id == id && $0.state == .done })
    }

    private func restore(_ operations: [JournalOperation]) throws -> UndoReport {
        var report = UndoReport(restored: [], skipped: [])
        for operation in operations {
            // El journal es un fichero más del espacio (que puede estar en una unidad compartida): sus rutas no son
            // de fiar. Solo se deshace lo que tiene hash, sale de dentro de la raíz (o de la Papelera, si se envió
            // allí) y vuelve a dentro de la raíz.
            guard let expected = operation.sha256, !expected.isEmpty, let current = currentURL(of: operation),
                  workspace.containedURL(forRelative: operation.from) != nil else {
                report.skipped.append(SkippedUndo(operationID: operation.id, reason: .unsafe))
                continue
            }
            guard FileManager.default.fileExists(atPath: current.path) else {
                report.skipped.append(SkippedUndo(operationID: operation.id, reason: .missing))
                continue
            }
            if (try? Hashing.sha256(of: current)) != expected {
                report.skipped.append(SkippedUndo(operationID: operation.id, reason: .modified))
                continue
            }
            let target = Collision.uniqueRelativePath(operation.from, root: workspace.root)
            guard let targetURL = workspace.containedURL(forRelative: target) else {
                report.skipped.append(SkippedUndo(operationID: operation.id, reason: .unsafe))
                continue
            }
            // Un fallo al mover se salta y se informa; el resto del lote se deshace igualmente (spec §10).
            do {
                try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: current, to: targetURL)
            } catch {
                report.skipped.append(SkippedUndo(operationID: operation.id, reason: .failed(error.localizedDescription)))
                continue
            }
            try journal.append(JournalEvent(id: operation.id, batch: operation.batch, op: operation.op,
                                            state: .undone, from: operation.to, to: target, sha256: operation.sha256))
            report.restored.append(AppliedMove(operationID: operation.id, from: operation.to, to: target))
        }
        return report
    }

    /// Reconcilia antes: tras un cierre inesperado, el último movimiento también se puede deshacer (spec §6.7).
    public func undoLast() throws -> UndoReport? {
        _ = try journal.reconcile()
        guard let batch = try journal.batches().first(where: { $0.done > 0 }) else { return nil }
        return try undo(batch: batch.id)
    }

    private func currentURL(of operation: JournalOperation) -> URL? {
        if operation.op == .trash {
            return PathSafety.isInTrash(operation.to) ? URL(fileURLWithPath: operation.to) : nil
        }
        return workspace.containedURL(forRelative: operation.to)
    }
}
