import Foundation

/// La procedencia sigue al documento: enlaza cada movimiento del usuario con la operación que dejó el documento donde
/// él lo recogió. Así, lo que archivó Tria sigue siendo suyo aunque el usuario lo mueva después, una vez o varias.
///
/// Un movimiento B sigue a una operación A cuando:
/// - B es un movimiento del usuario, y los dos están hechos (un movimiento deshecho deja de enlazar);
/// - B salió de donde A dejó el documento (`from` de B es `to` de A, sin distinguir mayúsculas ni forma Unicode);
/// - era el mismo fichero (mismo hash, y las líneas sin hash nunca enlazan) y B empezó cuando A ya había acabado.
public struct MoveChain: Sendable {
    private let byID: [String: JournalOperation]
    /// Movimiento del usuario → la operación a la que sigue.
    private let previousID: [String: String]
    /// Operación → el primer movimiento del usuario que la siguió.
    private let nextID: [String: String]

    public init(operations: [JournalOperation]) {
        // En el orden del registro: por fecha de inicio y, a igual fecha (el registro guarda segundos enteros), en el
        // orden en que llegan. Cada enlace va hacia atrás en este orden, así que la cadena nunca da la vuelta.
        let ordered = operations.enumerated()
            .sorted { ($0.element.startedAt, $0.offset) < ($1.element.startedAt, $1.offset) }
            .map(\.element)
        var byID: [String: JournalOperation] = [:]
        var previousID: [String: String] = [:]
        var nextID: [String: String] = [:]
        // Las operaciones hechas, por la ruta donde dejaron el documento, en el orden del registro.
        var endedAt: [String: [JournalOperation]] = [:]
        for operation in ordered {
            byID[operation.id] = operation
            if let previous = endedAt[JournalIndex.key(operation.from)]?.last(where: { Self.follows(operation, $0) }) {
                previousID[operation.id] = previous.id
                if nextID[previous.id] == nil { nextID[previous.id] = operation.id }
            }
            if operation.state == .done { endedAt[JournalIndex.key(operation.to), default: []].append(operation) }
        }
        self.byID = byID
        self.previousID = previousID
        self.nextID = nextID
    }

    /// Movimientos del usuario, hechos, que siguieron a `operation`, en orden.
    public func userMoves(after operation: JournalOperation) -> [JournalOperation] {
        var moves: [JournalOperation] = []
        var current = operation
        while let next = nextUserMove(after: current) {
            moves.append(next)
            current = next
        }
        return moves
    }

    /// Hacia atrás desde un movimiento del usuario: la primera operación que no es del usuario (la de Tria que lo
    /// archivó), o `nil` si la cadena empieza en un movimiento del usuario. Para una operación de Tria, ella misma.
    public func origin(of operation: JournalOperation) -> JournalOperation? {
        var current = operation
        while current.isUserMove {
            guard let previous = previousID[current.id].flatMap({ byID[$0] }) else { return nil }
            current = previous
        }
        return current
    }

    /// El movimiento del usuario que sacó el documento de donde lo dejó `operation`, si hubo uno.
    func nextUserMove(after operation: JournalOperation) -> JournalOperation? {
        nextID[operation.id].flatMap { byID[$0] }
    }

    private static func follows(_ move: JournalOperation, _ previous: JournalOperation) -> Bool {
        move.isUserMove && move.state == .done && previous.state == .done
            && JournalIndex.key(move.from) == JournalIndex.key(previous.to)
            && previous.sha256 != nil && previous.sha256 == move.sha256
            && move.startedAt >= previous.updatedAt
    }
}
