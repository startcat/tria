import Foundation

/// Índice del registro para encontrar documentos: por la ruta donde están ahora, por el nombre con el que llegaron
/// o por el nombre que les puso Tria (spec de la app, §9, pieza 3). Se construye una vez y se consulta muchas.
/// Sigue los movimientos del usuario (`MoveChain`): lo que archivó Tria sigue siendo suyo en su ruta nueva.
public struct JournalIndex: Sendable {
    /// Operaciones terminadas (hechas o deshechas), de la más reciente a la más antigua.
    public let operations: [JournalOperation]
    private let chain: MoveChain
    /// La operación hecha que dejó el documento en cada ruta y que ningún movimiento del usuario ha sacado de allí.
    private let byCurrentPath: [String: JournalOperation]

    /// `operations` como las da `Journal.operations()`: en el orden del registro, que decide entre las que empezaron
    /// en el mismo segundo.
    public init(operations: [JournalOperation]) {
        let finished = operations.filter { $0.state == .done || $0.state == .undone }
            .sorted { $0.updatedAt > $1.updatedAt }
        self.operations = finished
        let chain = MoveChain(operations: operations)
        var byPath: [String: JournalOperation] = [:]
        for operation in finished where operation.state == .done && operation.op == .move
            && chain.nextUserMove(after: operation) == nil {
            let key = Self.key(operation.to)
            if byPath[key] == nil { byPath[key] = operation }
        }
        self.chain = chain
        byCurrentPath = byPath
    }

    /// La operación de Tria que archivó lo que ahora está en `relativePath`, siguiendo los movimientos del usuario;
    /// `nil` si no lo archivó Tria o si, según el registro, ya no está allí.
    public func operation(at relativePath: String) -> JournalOperation? {
        byCurrentPath[Self.key(relativePath)].flatMap(chain.origin(of:))
    }

    /// El movimiento del usuario que lo dejó en `relativePath`, si fue uno.
    public func lastUserMove(at relativePath: String) -> JournalOperation? {
        byCurrentPath[Self.key(relativePath)].flatMap { $0.isUserMove ? $0 : nil }
    }

    /// El documento ya no está donde lo dejó `operation`: un movimiento del usuario lo sacó de allí.
    public func isSuperseded(_ operation: JournalOperation) -> Bool {
        chain.nextUserMove(after: operation) != nil
    }

    /// Dónde está ahora lo que dejó `operation`: el `to` del último movimiento del usuario que lo siguió, o el suyo si
    /// nadie lo movió. Sirve para encontrar un documento movido por el nombre con el que llegó.
    public func currentPath(of operation: JournalOperation) -> String {
        chain.userMoves(after: operation).last?.to ?? operation.to
    }

    /// Operaciones cuyo nombre original o nuevo contiene `query`, sin distinguir mayúsculas ni acentos.
    public func search(_ query: String, limit: Int = 50) -> [JournalOperation] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).nfc
        guard !needle.isEmpty else { return [] }
        return Array(operations.lazy.filter {
            Self.matches(Self.name(of: $0.from), needle) || Self.matches(Self.name(of: $0.to), needle)
        }.prefix(limit))
    }

    /// Último componente de una ruta del registro (relativa o, en la Papelera, absoluta).
    public static func name(of path: String) -> String {
        (path.nfc as NSString).lastPathComponent
    }

    /// La clave de una ruta: normalizada y en minúsculas, para no distinguir mayúsculas ni forma Unicode.
    static func key(_ path: String) -> String { path.normalizedRelativePath.lowercased() }

    private static func matches(_ name: String, _ needle: String) -> Bool {
        !name.isEmpty && name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

extension Journal {
    public func index() throws -> JournalIndex { JournalIndex(operations: try operations()) }
}
