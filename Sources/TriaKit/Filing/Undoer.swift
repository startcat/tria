import Foundation

public struct SkippedUndo: Sendable, Equatable {
    public enum Reason: Sendable, Hashable {
        case missing, modified
        /// La entrada del journal no es de fiar: ruta fuera del espacio, oculta o sin hash.
        case unsafe
        case failed(String)
        /// Un movimiento del usuario no vuelve atrás: su carpeta de antes ya no existe, no es una carpeta o ya no se
        /// puede entrar en ella (protegida, la bandeja, los duplicados…). No se vuelve a crear.
        case previousFolderUnavailable
    }
    public var operationID: String
    public var reason: Reason

    public init(operationID: String, reason: Reason) {
        self.operationID = operationID
        self.reason = reason
    }
}

public struct UndoReport: Sendable, Equatable {
    public var restored: [AppliedMove]
    public var skipped: [SkippedUndo]

    public init(restored: [AppliedMove], skipped: [SkippedUndo]) {
        self.restored = restored
        self.skipped = skipped
    }
}

/// Devuelve los ficheros a su sitio si siguen donde se dejaron y no han cambiado. Nunca sobrescribe.
/// Sigue los movimientos del usuario: lo que archivó Tria vuelve a la bandeja desde donde lo dejó él. Un movimiento
/// del usuario vuelve a su carpeta de antes, que no se crea si ya no existe.
public struct Undoer: Sendable {
    public let workspace: Workspace
    public let journal: Journal

    public init(workspace: Workspace) {
        self.workspace = workspace
        self.journal = Journal(workspace: workspace)
    }

    public func undo(batch: String) throws -> UndoReport {
        _ = try journal.reconcile()
        let operations = try journal.operations()
        return try restore(Array(operations.filter { $0.batch == batch && $0.state == .done }.reversed()),
                           chain: MoveChain(operations: operations))
    }

    /// Deshace una sola operación: «Deshacer y devolver a la bandeja» en la app (spec de la app, §5.2).
    public func undo(operation id: String) throws -> UndoReport {
        _ = try journal.reconcile()
        let operations = try journal.operations()
        return try restore(operations.filter { $0.id == id && $0.state == .done },
                           chain: MoveChain(operations: operations))
    }

    /// `chain` va con todo el registro, en su orden: los movimientos del usuario que siguieron a una operación son de
    /// otros lotes.
    private func restore(_ operations: [JournalOperation], chain: MoveChain) throws -> UndoReport {
        var report = UndoReport(restored: [], skipped: [])
        for operation in operations {
            // Lo que archivó Tria y movió después el usuario está donde lo dejó el último de esos movimientos.
            let moves = operation.isUserMove ? [] : chain.userMoves(after: operation)
            let place = moves.last?.to ?? operation.to
            // El journal es un fichero más del espacio (que puede estar en una unidad compartida): sus rutas no son
            // de fiar. Solo se deshace lo que tiene hash, sale de dentro de la raíz (o de la Papelera, si se envió
            // allí) y vuelve a dentro de la raíz.
            guard let expected = operation.sha256, !expected.isEmpty, let current = currentURL(of: operation, at: place),
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
            if operation.isUserMove && !canReturnToPreviousFolder(operation) {
                report.skipped.append(SkippedUndo(operationID: operation.id, reason: .previousFolderUnavailable))
                continue
            }
            let target = Collision.uniqueRelativePath(operation.from, root: workspace.root)
            guard let targetURL = workspace.containedURL(forRelative: target) else {
                report.skipped.append(SkippedUndo(operationID: operation.id, reason: .unsafe))
                continue
            }
            // Un fallo al mover se salta y se informa; el resto del lote se deshace igualmente (spec §10).
            do {
                // Lo de Tria vuelve a la bandeja, que se crea si falta; un movimiento del usuario nunca crea carpetas.
                if !operation.isUserMove {
                    try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                }
                try FileManager.default.moveItem(at: current, to: targetURL)
            } catch {
                report.skipped.append(SkippedUndo(operationID: operation.id, reason: .failed(error.localizedDescription)))
                continue
            }
            try appendUndone(operation, from: place, to: target)
            // Los movimientos del usuario de por medio también quedan deshechos: la cadena se cierra y el registro deja
            // de buscar allí el documento.
            for move in moves { try appendUndone(move, from: move.to, to: target) }
            report.restored.append(AppliedMove(operationID: operation.id, from: place, to: target))
        }
        return report
    }

    /// Reconcilia antes: tras un cierre inesperado, el último movimiento también se puede deshacer (spec §6.7).
    public func undoLast() throws -> UndoReport? {
        _ = try journal.reconcile()
        guard let batch = try journal.batches().first(where: { $0.done > 0 }) else { return nil }
        return try undo(batch: batch.id)
    }

    /// `path` es donde está ahora lo que dejó `operation`: su `to` o el del último movimiento del usuario.
    private func currentURL(of operation: JournalOperation, at path: String) -> URL? {
        if operation.op == .trash {
            return PathSafety.isInTrash(path) ? URL(fileURLWithPath: path) : nil
        }
        return workspace.containedURL(forRelative: path)
    }

    /// Un movimiento del usuario solo vuelve a su carpeta de antes si sigue siendo una carpeta y se puede entrar en
    /// ella, con las mismas comprobaciones que al mover (la carpeta y la ruta con el nombre).
    private func canReturnToPreviousFolder(_ operation: JournalOperation) -> Bool {
        let folder = (operation.from as NSString).deletingLastPathComponent
        let validator = Validator(workspace: workspace)
        guard validator.destinationError(folder) == nil, validator.destinationError(operation.from) == nil else {
            return false
        }
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: workspace.url(forRelative: folder).path, isDirectory: &isFolder)
            && isFolder.boolValue
    }

    private func appendUndone(_ operation: JournalOperation, from: String, to: String) throws {
        try journal.append(JournalEvent(id: operation.id, batch: operation.batch, op: operation.op, state: .undone,
                                        from: from, to: to, sha256: operation.sha256, byUser: operation.byUser))
    }
}
