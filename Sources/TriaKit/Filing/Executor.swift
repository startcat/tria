import Foundation

public struct ApprovedItem: Sendable, Equatable {
    public var action: FilingAction
    public var sha256: String?
    public var confidence: Confidence?
    public var reason: String?
    public var provider: String?
    public var model: String?
    /// El usuario cambió la carpeta o el nombre que proponía Tria antes de archivar (spec de la app, §9, pieza 5).
    public var corrected: Bool = false
    /// Lo que costó leer el documento, si llegó al proveedor.
    public var usage: TokenUsage? = nil

    public init(action: FilingAction, sha256: String? = nil, confidence: Confidence? = nil,
                reason: String? = nil, provider: String? = nil, model: String? = nil,
                corrected: Bool = false, usage: TokenUsage? = nil) {
        self.action = action
        self.sha256 = sha256
        self.confidence = confidence
        self.reason = reason
        self.provider = provider
        self.model = model
        self.corrected = corrected
        self.usage = usage
    }
}

public struct AppliedMove: Sendable, Equatable {
    public var operationID: String
    public var from: String
    public var to: String
}

public struct FailedMove: Sendable, Equatable {
    public var source: String
    public var message: String
}

public struct ApplyReport: Sendable, Equatable {
    public var batch: String
    public var applied: [AppliedMove]
    public var failed: [FailedMove]
}

public typealias Trasher = @Sendable (URL) throws -> URL

public enum ExecutorError: Error, Equatable, Sendable {
    /// El destino, una vez resueltos los enlaces simbólicos, incumple las invariantes del Validator.
    case unsafeDestination(String)
}

/// Mueve de uno en uno, con intención antes y confirmación después. Nunca sobrescribe (spec §6.6–6.7).
public struct Executor: Sendable {
    public let workspace: Workspace
    public let journal: Journal
    private let trasher: Trasher

    public static let systemTrash: Trasher = { url in
        #if DEBUG
        // La tanda QA nunca toca la Papelera de verdad.
        if let folder = QATrash.folder { return try QATrash.move(url, into: folder) }
        #endif
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return (resulting as URL?) ?? url
    }

    public init(workspace: Workspace, trasher: @escaping Trasher = Executor.systemTrash) {
        self.workspace = workspace
        self.journal = Journal(workspace: workspace)
        self.trasher = trasher
    }

    public func apply(_ items: [ApprovedItem], batch: String = Journal.newBatchID()) -> ApplyReport {
        var report = ApplyReport(batch: batch, applied: [], failed: [])
        for var item in items {
            let source = workspace.url(forRelative: item.action.source)
            guard FileManager.default.fileExists(atPath: source.path) else {
                report.failed.append(FailedMove(source: item.action.source, message: "source missing"))
                continue
            }
            // Se mueve lo que se propuso: si el fichero ha cambiado desde entonces, se queda en la bandeja.
            // El journal guarda siempre el hash de lo movido, que es lo que permite deshacer con seguridad.
            do {
                let current = try Hashing.sha256(of: source)
                if let expected = item.sha256, !expected.isEmpty, expected != current {
                    report.failed.append(FailedMove(source: item.action.source, message: "changed since it was proposed"))
                    continue
                }
                item.sha256 = current
            } catch {
                report.failed.append(FailedMove(source: item.action.source, message: String(describing: error)))
                continue
            }
            let id = Journal.newOperationID()
            do {
                let to = item.action.kind == .trash
                    ? try trash(item, source: source, id: id, batch: batch)
                    : try move(item, source: source, id: id, batch: batch)
                report.applied.append(AppliedMove(operationID: id, from: item.action.source, to: to))
            } catch {
                try? journal.append(event(item, id: id, batch: batch, state: .failed, to: "",
                                          error: String(describing: error)))
                report.failed.append(FailedMove(source: item.action.source, message: String(describing: error)))
            }
        }
        return report
    }

    private func move(_ item: ApprovedItem, source: URL, id: String, batch: String) throws -> String {
        if let problem = Validator(workspace: workspace)
            .destinationError(item.action.destination, allowDuplicates: item.action.kind == .duplicate) {
            throw ExecutorError.unsafeDestination(problem.feedback)
        }
        var target = Collision.uniqueRelativePath(item.action.destination, root: workspace.root)
        try journal.append(event(item, id: id, batch: batch, state: .intent, to: target))
        for _ in 0..<20 {
            let url = workspace.url(forRelative: target)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try FileManager.default.moveItem(at: source, to: url)
                try journal.append(event(item, id: id, batch: batch, state: .done, to: target))
                return target
            } catch CocoaError.fileWriteFileExists {
                target = Collision.uniqueRelativePath(item.action.destination, root: workspace.root, reserved: [target])
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    private func trash(_ item: ApprovedItem, source: URL, id: String, batch: String) throws -> String {
        try journal.append(event(item, id: id, batch: batch, state: .intent, to: ""))
        let resulting = try trasher(source)
        try journal.append(event(item, id: id, batch: batch, state: .done, to: resulting.path))
        return resulting.path
    }

    private func event(_ item: ApprovedItem, id: String, batch: String, state: JournalEvent.State,
                       to: String, error: String? = nil) -> JournalEvent {
        JournalEvent(id: id, batch: batch, op: item.action.kind == .trash ? .trash : .move, state: state,
                     from: item.action.source, to: to, sha256: item.sha256, confidence: item.confidence,
                     reason: item.reason, provider: item.provider, model: item.model, error: error,
                     corrected: item.corrected, usage: item.usage)
    }
}
