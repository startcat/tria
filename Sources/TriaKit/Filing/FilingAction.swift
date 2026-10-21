public struct FilingAction: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case file, duplicate, trash }

    public var kind: Kind
    /// Relativa a la raíz (siempre dentro de la bandeja).
    public var source: String
    /// Relativa a la raíz, con el nombre del fichero. Vacía para `.trash`.
    public var destination: String

    public init(kind: Kind, source: String, destination: String) {
        self.kind = kind
        self.source = source
        self.destination = destination
    }
}
