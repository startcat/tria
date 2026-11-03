import Foundation

/// Un documento del archivo que el usuario mueve a otra carpeta («Mover a»). Lo mueve `Executor.relocate`.
public struct RelocationItem: Sendable, Equatable {
    /// Ruta relativa a la raíz, con el nombre del fichero.
    public var source: String
    /// Carpeta de destino, relativa a la raíz y sin el nombre. Tiene que existir: «Mover a» no crea carpetas.
    public var folder: String

    public init(source: String, folder: String) {
        self.source = source
        self.folder = folder
    }
}

/// Por qué no se ha movido un documento.
public enum RelocationProblem: Sendable, Equatable {
    /// Ya no está donde estaba.
    case missing
    /// Solo está en la nube: leerlo para comprobarlo forzaría la descarga.
    case onlyInCloud
    /// No puede salir de donde está: una carpeta protegida, la bandeja, los duplicados, algo oculto o suelto en la raíz.
    case notMovable
    /// Ya está en esa carpeta.
    case sameFolder
    /// La carpeta de destino no existe o no es una carpeta.
    case folderMissing
    /// No se ha podido leer para calcular su hash.
    case unreadable(String)
    /// La carpeta de destino no vale (`Validator.destinationError`).
    case destination(ValidationError)
    /// Ha fallado al moverlo.
    case failed(String)
}

public struct FailedRelocation: Sendable, Equatable {
    public var source: String
    public var problem: RelocationProblem

    public init(source: String, problem: RelocationProblem) {
        self.source = source
        self.problem = problem
    }
}

public struct RelocationReport: Sendable, Equatable {
    public var batch: String
    public var moved: [AppliedMove]
    public var failed: [FailedRelocation]

    public init(batch: String, moved: [AppliedMove], failed: [FailedRelocation]) {
        self.batch = batch
        self.moved = moved
        self.failed = failed
    }
}
