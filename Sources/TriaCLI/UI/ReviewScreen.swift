import Foundation
import TriaKit

/// La cabecera de la revisión: el espacio a la izquierda, y el modelo y el coste a la derecha.
struct ReviewHeader: Equatable, Sendable {
    var workspace: String
    var model: String
    var cost: String?
}

/// Dibuja la revisión en líneas que caben en la ventana (spec CLI §5). Es una función pura: entran el estado y el
/// tamaño y salen las líneas. Ninguna llega a la última columna, que haría saltar de línea a algunos terminales.
///
/// Las filas de la lista recortan el destino por el medio; el detalle del documento del cursor lo enseña entero, con
/// la duda y el motivo: lo que se aprueba se ve entero.
enum ReviewScreen {
    /// La cabecera, tres rayas y la ayuda: lo que no es ni la lista ni el detalle.
    static let frameRows = 5
    /// El detalle cuando todo cabe en una línea: nombre, destino y motivo.
    static let minimumDetailRows = 3
    /// Lo que la lista conserva como mínimo cuando el detalle pide más.
    static let minimumListRows = 3

    /// Las filas de la lista: lo que dejan el marco y el detalle, al menos una.
    static func listRows(_ state: ReviewState, size: TerminalSize, env: CLIEnvironment) -> Int {
        max(1, size.rows - frameRows - detailRows(state, size: size, env: env))
    }

    /// Las filas del detalle. Mide lo que pide el documento que más necesita, para que la lista no salte al moverse,
    /// sin pasar del tope: la mitad de las filas que deja el marco, y 3 como mínimo para la lista. Si ni las carpetas
    /// del documento del cursor caben en el tope, el detalle crece hasta que quepan y la lista se queda con menos.
    static func detailRows(_ state: ReviewState, size: TerminalSize, env: CLIEnvironment) -> Int {
        let room = size.rows - frameRows
        let cap = max(0, min(room / 2, room - minimumListRows))
        let width = max(1, size.columns)
        let wanted = state.items.map { content(state, $0, env: env).rows(width: width) }.max() ?? 0
        var rows = min(cap, max(minimumDetailRows, wanted))
        if let item = state.current {
            rows = max(rows, min(content(state, item, env: env).minimumRows(width: width), room - 1))
        }
        return max(0, rows)
    }

    static func lines(_ state: ReviewState, header: ReviewHeader, size: TerminalSize, env: CLIEnvironment,
                      style: Style) -> [String] {
        let width = max(1, size.columns)
        let detailRows = detailRows(state, size: size, env: env)
        let visible = max(1, size.rows - frameRows - detailRows)
        let shown = Array(state.items.indices.dropFirst(state.top).prefix(visible))
        let nameWidth = nameColumn(state.items, width: width)
        var lines = [headerLine(header, width: width, style: style),
                     rule(width: width, more: state.top > 0 ? "↑" : nil, style: style)]
        lines += shown.map { row(state, index: $0, nameWidth: nameWidth, width: width, env: env, style: style) }
        lines.append(rule(width: width, more: state.top + visible < state.items.count ? "↓" : nil, style: style))
        lines += detail(state, rows: detailRows, width: width, env: env, style: style)
        lines.append(rule(width: width, more: nil, style: style))
        lines.append(help(state.marked.count, width: width, env: env, style: style))
        return Array(lines.prefix(max(0, size.rows)))
    }

    // MARK: - Piezas

    /// Un trozo de línea: texto sin colores y su papel.
    private typealias Piece = (text: String, role: StyleRole?)

    /// Junta los trozos sin pasar de `width - 1` columnas y luego los pinta. Sin caracteres de control: un salto de
    /// línea o un Esc de la IA o de un nombre romperían la pantalla.
    private static func fit(_ pieces: [Piece], width: Int, style: Style) -> String {
        var remaining = max(0, width - 1)
        var line = ""
        for piece in pieces {
            guard remaining > 0 else { break }
            let clean = TextWidth.singleLine(piece.text)
            let text = TextWidth.columns(clean) <= remaining ? clean : TextWidth.truncateEnd(clean, to: remaining)
            remaining -= TextWidth.columns(text)
            line += piece.role.map { style.paint(text, $0) } ?? text
        }
        return line
    }

    private static func headerLine(_ header: ReviewHeader, width: Int, style: Style) -> String {
        // Limpios ya al medir: `fit` los limpia igualmente, pero un Esc no ocupa nada y su espacio sí.
        let left = " Tria · \(TextWidth.singleLine(header.workspace))"
        let right = TextWidth.singleLine(header.model) + (header.cost.map { " · ≈ \($0)" } ?? "")
        let gap = width - 1 - TextWidth.columns(left) - TextWidth.columns(right)
        guard gap >= 2 else { return fit([(left, .strong)], width: width, style: style) }
        return fit([(left, .strong), (String(repeating: " ", count: gap), nil), (right, .muted)], width: width, style: style)
    }

    /// Una raya; con `more`, una flecha al final que avisa de que hay más filas por arriba o por abajo.
    private static func rule(width: Int, more: String?, style: Style) -> String {
        let dashes = max(0, width - 2 - (more == nil ? 0 : 2))
        return fit([(" " + String(repeating: "─", count: dashes) + (more.map { " " + $0 } ?? ""), .muted)],
                   width: width, style: style)
    }

    /// La columna de nombres: lo que ocupa el más largo, sin pasar de un tercio de la ventana (ni bajar de 12).
    private static func nameColumn(_ items: [SortItem], width: Int) -> Int {
        let longest = items.map { TextWidth.columns(name($0)) }.max() ?? 0
        return min(longest, max(12, (width - 13) / 3))
    }

    /// « ▸ [✓] ●  nombre  → destino»: 10 columnas fijas, el nombre, dos espacios y lo que pasará con el documento.
    private static func row(_ state: ReviewState, index: Int, nameWidth: Int, width: Int, env: CLIEnvironment,
                            style: Style) -> String {
        let item = state.items[index]
        let selected = index == state.cursor
        let box: Piece
        if !SortReview.isApprovable(item) {
            box = ("   ", nil)
        } else if state.trashed.contains(item.id) {
            box = ("[×]", .danger)
        } else if state.marked.contains(item.id) {
            box = ("[✓]", .success)
        } else {
            box = ("[ ]", nil)
        }
        let symbol: Piece
        switch item.kind {
        case .proposal(let proposal, _): symbol = ("●", Presenter.role(proposal.confidence))
        case .duplicate: symbol = ("≡", .warning)
        case .pending: symbol = (" ", nil)
        }
        let name = TextWidth.pad(TextWidth.truncateMiddle(self.name(item), to: nameWidth), to: nameWidth)
        let room = max(0, width - 1 - 10 - nameWidth - 2)
        let nameRole: StyleRole? = selected ? .strong : nil
        let pieces: [Piece] = [(" ", nil), (selected ? "▸" : " ", .accent), (" ", nil), box, (" ", nil), symbol,
                               ("  ", nil), (name, nameRole), ("  ", nil), target(state, item, room: room, env: env)]
        return fit(pieces, width: width, style: style)
    }

    /// El nombre del documento, sin caracteres de control (ver `fit`).
    private static func name(_ item: SortItem) -> String { TextWidth.singleLine(item.file.lastPathComponent) }

    /// Lo que pasará con el documento: su destino, su duda, de qué es duplicado o por qué está pendiente.
    private static func target(_ state: ReviewState, _ item: SortItem, room: Int, env: CLIEnvironment) -> Piece {
        func path(_ destination: String) -> Piece {
            ("→ " + TextWidth.truncatePath(TextWidth.singleLine(destination), to: max(0, room - 2)), .accent)
        }
        func line(_ text: String) -> String { TextWidth.truncateEnd(TextWidth.singleLine(text), to: room) }
        switch item.kind {
        case .proposal(let proposal, let action):
            if let edit = state.edits[item.id] { return path(edit.approved.action.destination) }
            if proposal.confidence != .high, let doubt = proposal.doubt { return (line("? " + doubt), .warning) }
            return path(action.destination)
        case .duplicate(let original, _):
            if state.trashed.contains(item.id) { return ("→ " + env.t(.screenTrash), .danger) }
            return (line(env.t(.statusDuplicate, original)), .muted)
        case .pending(_, let reason):
            return (line(env.t(.statusPending, Presenter.reason(reason, env))), .warning)
        }
    }

    // MARK: - Detalle

    /// Lo que enseña el detalle de un documento: una línea con el nombre (que se puede recortar), el destino (que se
    /// parte tras una «/», con la sangría bajo la flecha) y las notas (que se parten por palabras): la duda, el motivo,
    /// de qué es duplicado o por qué está pendiente. Todo sin caracteres de control.
    private struct Content {
        var title: [Piece]
        var destination: (path: String, role: StyleRole)?
        var notes: [(prefix: String, text: String, role: StyleRole?)]

        /// Lo que queda para el texto: el destino va detrás de « → » y cada nota detrás de « » y su prefijo.
        static func destinationWidth(_ width: Int) -> Int { width - 1 - 3 }
        static func noteWidth(_ width: Int, prefix: String) -> Int { width - 1 - 1 - TextWidth.columns(prefix) }

        /// Las líneas de las notas, sin el margen: la primera de cada una con su prefijo y las demás debajo del texto.
        func noteLines(width: Int) -> [(text: String, role: StyleRole?)] {
            notes.flatMap { note in
                let hang = String(repeating: " ", count: TextWidth.columns(note.prefix))
                return TextWidth.wrap(note.text, width: Self.noteWidth(width, prefix: note.prefix)).enumerated()
                    .map { (($0.offset == 0 ? note.prefix : hang) + $0.element, note.role) }
            }
        }

        /// Lo que pide entero.
        func rows(width: Int) -> Int {
            let destination = destination.map {
                TextWidth.wrap($0.path, width: Self.destinationWidth(width), path: true).count
            } ?? 0
            return 1 + destination + noteLines(width: width).count
        }

        /// Lo mínimo: el nombre y las carpetas enteras, con el nombre del fichero lo más corto posible.
        func minimumRows(width: Int) -> Int {
            1 + (destination.map { TextWidth.wrapPath($0.path, width: Self.destinationWidth(width), rows: 1).count } ?? 0)
        }
    }

    private static func content(_ state: ReviewState, _ item: SortItem, env: CLIEnvironment) -> Content {
        let clean = TextWidth.singleLine
        let name: Piece = (" " + self.name(item), .strong)
        switch item.kind {
        case .proposal(let proposal, let action):
            var tags = [env.t(.screenConfidence, Presenter.confidence(proposal.confidence, env))]
            if state.edits[item.id] != nil { tags.append(env.t(.screenEdited)) }
            if item.undoneBefore { tags.append(env.t(.screenUndone)) }
            var notes: [(prefix: String, text: String, role: StyleRole?)] = []
            if proposal.confidence != .high, let doubt = proposal.doubt { notes.append(("? ", clean(doubt), .warning)) }
            notes.append(("", clean(proposal.reason), nil))
            return Content(title: [name, (" · " + tags.joined(separator: " · "), Presenter.role(proposal.confidence))],
                           destination: (clean(state.edits[item.id]?.approved.action.destination ?? action.destination),
                                         .accent),
                           notes: notes)
        case .duplicate(let original, let action):
            let trashed = state.trashed.contains(item.id)
            return Content(title: [name],
                           destination: trashed ? (env.t(.screenTrash), .danger) : (clean(action.destination), .accent),
                           notes: [("", clean(env.t(.statusDuplicate, original)), .muted)])
        case .pending(_, let reason):
            return Content(title: [name], destination: nil,
                           notes: [("", clean(env.t(.statusPending, Presenter.reason(reason, env))), .warning)])
        }
    }

    /// El detalle del documento del cursor en `rows` líneas. Si las notas no caben, la última que se ve acaba en «…»;
    /// si el destino no cabe, se acorta el nombre del fichero (ver `detailRows`).
    private static func detail(_ state: ReviewState, rows: Int, width: Int, env: CLIEnvironment,
                               style: Style) -> [String] {
        guard rows > 0 else { return [] }
        guard let item = state.current else { return Array(repeating: "", count: rows) }
        let content = content(state, item, env: env)
        var lines = [fit(content.title, width: width, style: style)]
        if let destination = content.destination {
            let parts = TextWidth.wrapPath(destination.path, width: Content.destinationWidth(width),
                                           rows: max(1, rows - 1))
            lines += parts.enumerated().map { index, part in
                fit([(" ", nil), ((index == 0 ? "→ " : "  ") + part, destination.role)], width: width, style: style)
            }
        }
        let room = max(0, rows - lines.count)
        var notes = content.noteLines(width: width)
        if notes.count > room, room > 0 {
            notes = Array(notes.prefix(room))
            notes[room - 1].text = TextWidth.truncateEnd(notes[room - 1].text + "…", to: width - 2)
        }
        lines += notes.prefix(room).map { fit([(" " + $0.text, $0.role)], width: width, style: style) }
        return Array(lines.prefix(rows)) + Array(repeating: "", count: max(0, rows - lines.count))
    }

    /// La ayuda con la cifra de lo marcado; si no cabe entera, la corta.
    private static func help(_ count: Int, width: Int, env: CLIEnvironment, style: Style) -> String {
        let long = " " + env.t(.screenHelp, String(count))
        let text = TextWidth.columns(long) <= width - 1 ? long : " " + env.t(.screenHelpShort, String(count))
        return fit([(text, .muted)], width: width, style: style)
    }
}
