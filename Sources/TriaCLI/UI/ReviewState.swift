import Foundation
import TriaKit

/// Lo que una tecla pide a la sesión, aparte de cambiar el estado.
enum ReviewCommand: Equatable, Sendable {
    case none
    case edit(SortItem)
    case apply
    case quit
    case interrupt
}

/// El estado de la revisión a pantalla completa: documentos, cursor, marcados y ediciones (spec CLI §5). Las teclas
/// lo cambian sin efectos; aplicar, editar y salir los hace la sesión.
struct ReviewState: Equatable, Sendable {
    let items: [SortItem]
    private(set) var cursor = 0
    /// Primera fila visible de la lista.
    private(set) var top = 0
    private(set) var marked: Set<String>
    /// Duplicados marcados para la Papelera; siempre están también en `marked`.
    private(set) var trashed: Set<String> = []
    private(set) var edits: [String: SortEdit] = [:]

    /// De entrada, marcado lo que aplicaría `--auto`: la confianza alta y los duplicados exactos.
    init(plan: SortPlan) {
        items = plan.items
        marked = Set(SortPipeline.automaticItems(plan).map(\.action.source))
    }

    var current: SortItem? { items.indices.contains(cursor) ? items[cursor] : nil }

    mutating func handle(_ key: KeyPress) -> ReviewCommand {
        switch Self.lowercased(key) {
        case .up, .character("k"):
            move(by: -1)
        case .down, .character("j"):
            move(by: 1)
        case .space:
            toggle()
        case .character("a"):
            // Solo queda marcada la confianza alta: desmarca las ediciones y los duplicados (spec CLI §5).
            marked = Set(items.filter(Self.isHighConfidence).map(\.id))
            trashed.formIntersection(marked)
        case .character("e"):
            guard let item = current, case .proposal = item.kind else { return .none }
            return .edit(item)
        case .character("p"):
            guard let item = current, case .duplicate = item.kind else { return .none }
            if trashed.remove(item.id) == nil {
                trashed.insert(item.id)
                marked.insert(item.id)
            }
        case .enter:
            return .apply
        case .character("q"), .escape, .end:
            return .quit
        case .interrupt:
            return .interrupt
        default:
            break
        }
        return .none
    }

    /// Una edición hecha con `e`: el documento queda marcado con su destino nuevo.
    mutating func applyEdit(_ edit: SortEdit, to id: String) {
        edits[id] = edit
        marked.insert(id)
    }

    /// Mueve la primera fila visible para que se vea el cursor.
    mutating func scroll(visibleRows: Int) {
        let rows = max(1, visibleRows)
        if cursor < top { top = cursor }
        if cursor >= top + rows { top = cursor - rows + 1 }
        top = max(0, min(top, max(0, items.count - rows)))
    }

    /// Los destinos que ya ocupan los demás documentos marcados, para validar una edición.
    func reservedDestinations(excluding id: String) -> Set<String> {
        Set(items.compactMap { item -> String? in
            guard item.id != id, marked.contains(item.id), !trashed.contains(item.id) else { return nil }
            if let edit = edits[item.id] { return edit.approved.action.destination }
            switch item.kind {
            case .proposal(_, let action), .duplicate(_, let action): return action.destination
            case .pending: return nil
            }
        })
    }

    /// Lo que se aplica con Intro, en el orden de la bandeja.
    func approved() -> [ApprovedItem] {
        items.compactMap { item in
            guard marked.contains(item.id) else { return nil }
            if trashed.contains(item.id) { return SortReview.trash(item) }
            if let edit = edits[item.id] { return edit.approved }
            return SortPipeline.approvedItem(for: item)
        }
    }

    /// Las correcciones de lo marcado, para ofrecer después la sugerencia de regla (spec CLI §5).
    func corrections() -> [SortCorrection] {
        items.compactMap { marked.contains($0.id) ? edits[$0.id]?.correction : nil }
    }

    // MARK: - Privado

    private mutating func move(by delta: Int) {
        guard !items.isEmpty else { return }
        cursor = min(max(cursor + delta, 0), items.count - 1)
    }

    /// Los pendientes se ven pero no se marcan (spec CLI §5).
    private mutating func toggle() {
        guard let item = current, SortReview.isApprovable(item) else { return }
        if marked.remove(item.id) == nil {
            marked.insert(item.id)
        } else {
            trashed.remove(item.id)
        }
    }

    private static func isHighConfidence(_ item: SortItem) -> Bool {
        guard !item.undoneBefore, case .proposal(let proposal, _) = item.kind else { return false }
        return proposal.confidence == .high
    }

    private static func lowercased(_ key: KeyPress) -> KeyPress {
        guard case .character(let character) = key else { return key }
        return .character(character.lowercased().first ?? character)
    }
}
