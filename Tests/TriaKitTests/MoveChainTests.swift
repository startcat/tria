import Foundation
import Testing
@testable import TriaKit

/// La procedencia sigue al documento: los movimientos del usuario se enlazan con la operación que dejó el documento
/// donde estaba, y el índice responde por la ruta de ahora.
struct MoveChainTests {
    private let inbox = "99-Pendiente/scan.pdf"
    private let filed = "4-Correspondencia/Contrato telefonía.pdf"
    private let moved = "2-Contratos/Contrato telefonía.pdf"
    private let movedAgain = "2-Contratos/Telefonía/Contrato telefonía.pdf"

    /// Una operación como la deja `Journal.operations()`: empieza en `at` y acaba en `until` (por defecto, el mismo
    /// segundo, como en el registro, que guarda segundos enteros).
    private func operation(_ id: String, from: String, to: String, sha: String? = "h", at start: TimeInterval,
                           until end: TimeInterval? = nil, byUser: Bool = false,
                           state: JournalEvent.State = .done) -> JournalOperation {
        JournalOperation(id: id, batch: "b_\(id)", op: .move, state: state, from: from, to: to, sha256: sha,
                         reason: nil, confidence: nil, restoredTo: state == .undone ? from : nil, error: nil,
                         startedAt: Date(timeIntervalSince1970: start),
                         updatedAt: Date(timeIntervalSince1970: end ?? start), byUser: byUser)
    }

    @Test func afterAUserMoveTheNewPathKeepsTriasFiling() {
        let filing = operation("op_tria", from: inbox, to: filed, at: 1_000)
        let move = operation("op_user", from: filed, to: moved, at: 2_000, byUser: true)
        let index = JournalIndex(operations: [filing, move])

        #expect(index.operation(at: moved)?.id == filing.id)
        #expect(index.lastUserMove(at: moved)?.id == move.id)
        #expect(index.operation(at: filed) == nil)
        #expect(index.lastUserMove(at: filed) == nil)
        #expect(index.isSuperseded(filing))
        #expect(!index.isSuperseded(move))
        let chain = MoveChain(operations: [filing, move])
        #expect(chain.userMoves(after: filing).map(\.id) == [move.id])
        #expect(chain.userMoves(after: move).isEmpty)
        #expect(chain.origin(of: move)?.id == filing.id)
        #expect(chain.origin(of: filing)?.id == filing.id)
    }

    @Test func twoUserMovesInARowStillReachTheFiling() {
        let filing = operation("op_tria", from: inbox, to: filed, at: 1_000)
        let first = operation("op_user_1", from: filed, to: moved, at: 2_000, byUser: true)
        let second = operation("op_user_2", from: moved, to: movedAgain, at: 3_000, byUser: true)
        let index = JournalIndex(operations: [filing, first, second])

        #expect(index.operation(at: movedAgain)?.id == filing.id)
        #expect(index.lastUserMove(at: movedAgain)?.id == second.id)
        #expect(index.operation(at: moved) == nil)
        #expect(index.lastUserMove(at: moved) == nil)
        #expect(index.isSuperseded(filing) && index.isSuperseded(first) && !index.isSuperseded(second))
        let chain = MoveChain(operations: [filing, first, second])
        #expect(chain.userMoves(after: filing).map(\.id) == [first.id, second.id])
        #expect(chain.userMoves(after: first).map(\.id) == [second.id])
        #expect(chain.origin(of: second)?.id == filing.id)
    }

    @Test func aHandPlacedDocumentMovedHasNoFiling() {
        let move = operation("op_user", from: filed, to: moved, at: 2_000, byUser: true)
        let index = JournalIndex(operations: [move])

        #expect(index.operation(at: moved) == nil)
        #expect(index.lastUserMove(at: moved)?.id == move.id)
        #expect(MoveChain(operations: [move]).origin(of: move) == nil)
    }

    @Test func anUndoneUserMoveGivesThePathBackToTheFiling() {
        let filing = operation("op_tria", from: inbox, to: filed, at: 1_000)
        let move = operation("op_user", from: filed, to: moved, at: 2_000, until: 3_000, byUser: true, state: .undone)
        let index = JournalIndex(operations: [filing, move])

        #expect(index.operation(at: filed)?.id == filing.id)
        #expect(index.lastUserMove(at: filed) == nil)
        #expect(index.operation(at: moved) == nil)
        #expect(index.lastUserMove(at: moved) == nil)
        #expect(!index.isSuperseded(filing))
        let chain = MoveChain(operations: [filing, move])
        #expect(chain.userMoves(after: filing).isEmpty)
        #expect(chain.origin(of: move) == nil)
    }

    @Test func aMoveOfAnotherFileFromThatPathDoesNotLink() {
        let filing = operation("op_tria", from: inbox, to: filed, at: 1_000)
        let move = operation("op_user", from: filed, to: moved, sha: "otro", at: 2_000, byUser: true)
        let index = JournalIndex(operations: [filing, move])

        #expect(MoveChain(operations: [filing, move]).origin(of: move) == nil)
        #expect(!index.isSuperseded(filing))
        #expect(index.operation(at: filed)?.id == filing.id)
        #expect(index.operation(at: moved) == nil)
        #expect(index.lastUserMove(at: moved)?.id == move.id)
    }

    /// M6: dos líneas sin hash no son «el mismo fichero».
    @Test func linesWithoutAHashNeverLink() {
        let filing = operation("op_tria", from: inbox, to: filed, sha: nil, at: 1_000)
        let move = operation("op_user", from: filed, to: moved, sha: nil, at: 2_000, byUser: true)
        let chain = MoveChain(operations: [filing, move])

        #expect(chain.origin(of: move) == nil)
        #expect(chain.userMoves(after: filing).isEmpty)
        #expect(!JournalIndex(operations: [filing, move]).isSuperseded(filing))
    }

    @Test func aMoveMustStartOnceTheOperationBeforeItHasEnded() {
        let filing = operation("op_tria", from: inbox, to: filed, at: 1_000, until: 2_000)
        let early = operation("op_early", from: filed, to: moved, at: 1_500, byUser: true)
        #expect(MoveChain(operations: [filing, early]).origin(of: early) == nil)

        // El registro guarda segundos enteros: un movimiento en el mismo segundo en que acabó la operación sí la sigue.
        let sameSecond = operation("op_same", from: filed, to: moved, at: 2_000, byUser: true)
        #expect(MoveChain(operations: [filing, sameSecond]).origin(of: sameSecond)?.id == filing.id)
    }

    @Test func thePathKeyIgnoresCaseAndUnicodeForm() {
        let filing = operation("op_tria", from: inbox, to: filed, at: 1_000)
        // Desde SMB el nombre llega en NFD ("i" + acento combinado) y con otra capitalización.
        let move = operation("op_user", from: "4-correspondencia/Contrato telefoni\u{0301}a.pdf", to: moved,
                             at: 2_000, byUser: true)
        #expect(MoveChain(operations: [filing, move]).origin(of: move)?.id == filing.id)
    }

    @Test func goingBackAndForthInTheSameSecondFollowsTheJournalOrder() {
        let filing = operation("op_tria", from: inbox, to: filed, at: 1_000)
        let there = operation("op_1", from: filed, to: moved, at: 1_000, byUser: true)
        let back = operation("op_2", from: moved, to: filed, at: 1_000, byUser: true)
        let again = operation("op_3", from: filed, to: movedAgain, at: 1_000, byUser: true)
        let operations = [filing, there, back, again]
        let chain = MoveChain(operations: operations)

        #expect(chain.userMoves(after: filing).map(\.id) == [there.id, back.id, again.id])
        #expect(chain.origin(of: again)?.id == filing.id)
        #expect(chain.origin(of: there)?.id == filing.id)
        let index = JournalIndex(operations: operations)
        #expect(index.operation(at: movedAgain)?.id == filing.id)
        #expect(index.operation(at: filed) == nil)
        #expect(index.operation(at: moved) == nil)
    }
}
