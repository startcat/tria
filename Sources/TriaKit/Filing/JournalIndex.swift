import Foundation

/// Índice del registro para encontrar documentos: por la ruta donde están ahora, por el nombre con el que llegaron
/// o por el nombre que les puso Tria (spec de la app, §9, pieza 3). Se construye una vez y se consulta muchas.
public struct JournalIndex: Sendable {
    /// Operaciones terminadas (hechas o deshechas), de la más reciente a la más antigua.
    public let operations: [JournalOperation]
    private let byCurrentPath: [String: JournalOperation]

    public init(operations: [JournalOperation]) {
        let finished = operations.filter { $0.state == .done || $0.state == .undone }
            .sorted { $0.updatedAt > $1.updatedAt }
        self.operations = finished
        var byPath: [String: JournalOperation] = [:]
        for operation in finished where operation.state == .done && operation.op == .move {
            let key = Self.key(operation.to)
            if byPath[key] == nil { byPath[key] = operation }
        }
        byCurrentPath = byPath
    }

    /// La operación que dejó un fichero en `relativePath`, si según el registro sigue allí.
    public func operation(at relativePath: String) -> JournalOperation? {
        byCurrentPath[Self.key(relativePath)]
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

    private static func key(_ path: String) -> String { path.normalizedRelativePath.lowercased() }

    private static func matches(_ name: String, _ needle: String) -> Bool {
        !name.isEmpty && name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

extension Journal {
    public func index() throws -> JournalIndex { JournalIndex(operations: try operations()) }
}
