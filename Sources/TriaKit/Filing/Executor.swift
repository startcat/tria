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

    public init(operationID: String, from: String, to: String) {
        self.operationID = operationID
        self.from = from
        self.to = to
    }
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
        return try moveWithoutOverwriting(source, to: item.action.destination, createsFolders: true) { state, to in
            event(item, id: id, batch: batch, state: state, to: to)
        }
    }

    /// Apunta la intención, mueve y lo confirma. Nunca sobrescribe: si otro fichero ocupa el destino justo entonces,
    /// prueba con el siguiente nombre libre, hasta 20 veces. `createsFolders` crea las carpetas que falten, como al
    /// archivar; al mover del archivo es `false`, porque «Mover a» nunca crea una carpeta (ni la que se borre mientras).
    private func moveWithoutOverwriting(_ source: URL, to destination: String, createsFolders: Bool,
                                        event: (JournalEvent.State, String) -> JournalEvent) throws -> String {
        var target = Collision.uniqueRelativePath(destination, root: workspace.root)
        try journal.append(event(.intent, target))
        for _ in 0..<20 {
            let url = workspace.url(forRelative: target)
            if createsFolders {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
            }
            do {
                try FileManager.default.moveItem(at: source, to: url)
                try journal.append(event(.done, target))
                return target
            } catch CocoaError.fileWriteFileExists {
                target = Collision.uniqueRelativePath(destination, root: workspace.root, reserved: [target])
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

// MARK: - Mover del archivo («Mover a»)

extension Executor {
    /// Mueve documentos del archivo a otra carpeta que ya existe. Cada uno es una operación `move` del lote, marcada
    /// `byUser` y con el hash de lo movido, para poder deshacerla. Como no hay propuesta, comprueba en el momento que el
    /// documento sigue ahí, que puede salir de donde está y entrar donde va, y lee su hash. Nunca sobrescribe ni crea
    /// carpetas, y lo que falla no para a los demás. No coge el bloqueo: lo coge quien llama, como con `apply`.
    /// `isDownloaded` solo se cambia en las pruebas.
    public func relocate(_ items: [RelocationItem], batch: String = Journal.newBatchID(),
                         isDownloaded: (URL) -> Bool = Workspace.isDownloaded) -> RelocationReport {
        var report = RelocationReport(batch: batch, moved: [], failed: [])
        for item in items {
            // El informe devuelve las rutas como llegan, para que quien llama las reconozca; el registro, normalizadas.
            let source = item.source.normalizedRelativePath
            let folder = item.folder.normalizedRelativePath
            let url = workspace.url(forRelative: source)
            if let problem = relocationProblem(source: source, folder: folder, url: url, isDownloaded: isDownloaded) {
                report.failed.append(FailedRelocation(source: item.source, problem: problem))
                continue
            }
            let sha256: String
            do {
                sha256 = try Hashing.sha256(of: url)
            } catch {
                report.failed.append(FailedRelocation(source: item.source,
                                                      problem: .unreadable(error.localizedDescription)))
                continue
            }
            let id = Journal.newOperationID()
            func event(_ state: JournalEvent.State, to: String, error: String? = nil) -> JournalEvent {
                JournalEvent(id: id, batch: batch, op: .move, state: state, from: source, to: to, sha256: sha256,
                             error: error, byUser: true)
            }
            do {
                let to = try moveWithoutOverwriting(url, to: "\(folder)/\((source as NSString).lastPathComponent)",
                                                    createsFolders: false) { event($0, to: $1) }
                report.moved.append(AppliedMove(operationID: id, from: item.source, to: to))
            } catch {
                // Al registro, el error entero, para saber qué pasó; al informe, que lo lee el usuario, la frase del
                // sistema, como al deshacer (`Undoer`).
                try? journal.append(event(.failed, to: "", error: String(describing: error)))
                report.failed.append(FailedRelocation(source: item.source,
                                                      problem: .failed(error.localizedDescription)))
            }
        }
        return report
    }

    /// Las comprobaciones de `relocate` antes de leer el hash, en orden: el primer problema, o `nil` si se puede mover.
    private func relocationProblem(source: String, folder: String, url: URL,
                                   isDownloaded: (URL) -> Bool) -> RelocationProblem? {
        let validator = Validator(workspace: workspace)
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        // Lo suelto en la raíz tampoco sale: su carpeta de antes sería la raíz, y ahí no se puede devolver.
        let current = (source as NSString).deletingLastPathComponent
        guard !current.isEmpty, validator.destinationError(source) == nil else { return .notMovable }
        // La carpeta y también la ruta con el nombre, como al archivar: "7-Facturas/2024.pdf" encaja con "7-Facturas/20*".
        let name = (source as NSString).lastPathComponent
        if let error = validator.destinationError(folder) ?? validator.destinationError("\(folder)/\(name)") {
            return .destination(error)
        }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workspace.url(forRelative: folder).path, isDirectory: &isFolder),
              isFolder.boolValue else { return .folderMissing }
        if isSameFolder(current, folder) { return .sameFolder }
        guard isDownloaded(url) else { return .onlyInCloud }
        return nil
    }

    /// Sin distinguir mayúsculas y con los enlaces simbólicos resueltos: un atajo a la carpeta de ahora es la misma.
    private func isSameFolder(_ lhs: String, _ rhs: String) -> Bool {
        func key(_ path: String) -> String { (workspace.resolvedRelativePath(path) ?? path).lowercased() }
        return key(lhs) == key(rhs)
    }
}
