/// Anchura en columnas del terminal y recortes que nunca parten un carácter (spec CLI §5, ventana pequeña).
/// Trabaja con caracteres completos (`Character`): una letra con su tilde, un emoji o un ideograma no se parten.
/// Los recortes son para texto sin colores: se recorta primero y se pinta después.
enum TextWidth {
    static let ellipsis: Character = "…"

    /// Columnas que ocupa `text`. Los códigos de color no ocupan.
    static func columns(_ text: String) -> Int {
        visible(text).reduce(0) { $0 + columns(of: $1) }
    }

    /// 2 para ideogramas, hangul, formas de anchura completa y emojis; 0 para controles; 1 para el resto.
    static func columns(of character: Character) -> Int {
        guard let first = character.unicodeScalars.first else { return 0 }
        if first.properties.generalCategory == .control { return 0 }
        if character.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0 == "\u{FE0F}" }) {
            return 2
        }
        return isWide(first) ? 2 : 1
    }

    /// Recorta por el final, con «…».
    static func truncateEnd(_ text: String, to width: Int) -> String {
        guard columns(text) > width else { return text }
        guard width > 1 else { return width == 1 ? String(ellipsis) : "" }
        return String(prefix(Array(text), columns: width - 1)) + String(ellipsis)
    }

    /// Recorta por el medio: «Factura Pa…10-05.pdf».
    static func truncateMiddle(_ text: String, to width: Int) -> String {
        guard columns(text) > width else { return text }
        guard width > 1 else { return width == 1 ? String(ellipsis) : "" }
        let characters = Array(text)
        let budget = width - 1
        let head = prefix(characters, columns: (budget + 1) / 2)
        let used = head.reduce(0) { $0 + columns(of: $1) }
        let tail = Array(prefix(Array(characters.reversed()), columns: budget - used).reversed())
        return String(head) + String(ellipsis) + String(tail)
    }

    /// Recorta una ruta quitando carpetas del medio («2-Facturas Recibidas/…/4T/Factura.pdf»); si ni así cabe,
    /// por el medio del texto.
    static func truncatePath(_ path: String, to width: Int) -> String {
        guard columns(path) > width else { return path }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 3 {
            for start in 2..<parts.count {
                let candidate = parts[0] + "/…/" + parts[start...].joined(separator: "/")
                if columns(candidate) <= width { return candidate }
            }
        }
        return truncateMiddle(path, to: width)
    }

    /// El texto en una sola línea y sin órdenes para el terminal: cada carácter de control (C0 con Esc, saltos de línea
    /// y tabuladores, DEL y C1) pasa a ser un espacio. Para lo que llega de la IA o de un nombre de fichero antes de
    /// enseñarlo; nunca para `--json`.
    static func singleLine(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isControl) else { return text }
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars { scalars.append(isControl(scalar) ? " " : scalar) }
        return String(scalars)
    }

    /// Parte `text` en líneas de `width` columnas como mucho, sin partir caracteres: lo que se aprueba se ve entero.
    /// Corta en un espacio; en una ruta (`path`), mejor después de una «/», para no partir el nombre de una carpeta. Solo
    /// parte una palabra (o una carpeta) que no cabe sola en una línea. Los espacios de los extremos no se enseñan (uno al
    /// principio daría una primera línea vacía). Sin texto, ninguna línea.
    static func wrap(_ text: String, width: Int, path: Bool = false) -> [String] {
        var characters = Array(text.drop { $0 == " " })
        while characters.last == " " { characters.removeLast() }
        let limit = max(1, width)
        var lines: [String] = []
        var start = 0
        while start < characters.count {
            var end = start
            var used = 0
            while end < characters.count, used + columns(of: characters[end]) <= limit {
                used += columns(of: characters[end])
                end += 1
            }
            guard end < characters.count else {
                lines.append(String(characters[start...]))
                break
            }
            // Después de la última «/» que cabe o en el último espacio (el primero que ya no cabe también vale): por este
            // orden en una ruta y al revés en el texto. Sin ninguno, se parte la palabra, con un carácter como mínimo.
            let slash = (start..<end).last { characters[$0] == "/" }.map { $0 + 1 }
            let space = ((start + 1)..<(end + 1)).last { characters[$0] == " " }
            let cut = (path ? slash ?? space : space ?? slash) ?? max(end, start + 1)
            var line = String(characters[start..<cut])
            while line.last == " " { line.removeLast() }
            lines.append(line)
            start = cut
            while start < characters.count, characters[start] == " " { start += 1 }
        }
        return lines
    }

    /// Una ruta partida (ver `wrap`) en `rows` líneas como mucho. Las carpetas no se quitan nunca: si no cabe, se acorta
    /// el nombre del fichero por el medio; si ni las carpetas caben, salen enteras en las líneas que hagan falta.
    static func wrapPath(_ path: String, width: Int, rows: Int) -> [String] {
        let whole = wrap(path, width: width, path: true)
        guard whole.count > rows else { return whole }
        let split = path.lastIndex(of: "/").map { path.index(after: $0) } ?? path.startIndex
        let folders = String(path[..<split]), name = String(path[split...])
        func lines(_ budget: Int) -> [String] { wrap(folders + truncateMiddle(name, to: budget), width: width, path: true) }
        // El nombre más largo que cabe, buscado a medias: un nombre más largo no ocupa menos líneas.
        var best = lines(1)
        var low = 2, high = columns(name) - 1
        while low <= high {
            let budget = (low + high) / 2
            let candidate = lines(budget)
            if candidate.count <= rows {
                best = candidate
                low = budget + 1
            } else {
                high = budget - 1
            }
        }
        return best
    }

    /// Rellena con espacios por la derecha hasta `width` columnas.
    static func pad(_ text: String, to width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - columns(text)))
    }

    /// Rellena por la izquierda: cifras alineadas a la derecha.
    static func padLeft(_ text: String, to width: Int) -> String {
        String(repeating: " ", count: max(0, width - columns(text))) + text
    }

    // MARK: - Privado

    private static func prefix(_ characters: [Character], columns limit: Int) -> [Character] {
        var used = 0
        var result: [Character] = []
        for character in characters {
            let width = columns(of: character)
            guard used + width <= limit else { break }
            used += width
            result.append(character)
        }
        return result
    }

    /// Lo que se ve: sin las secuencias de escape (ESC [ … letra).
    private static func visible(_ text: String) -> [Character] {
        var result: [Character] = []
        var escaping = false
        var bracket = false
        for character in text {
            if escaping {
                if !bracket && character == "[" { bracket = true; continue }
                if let ascii = character.asciiValue, (0x40...0x7E).contains(ascii) { escaping = false }
                continue
            }
            if character == "\u{1B}" {
                escaping = true
                bracket = false
                continue
            }
            result.append(character)
        }
        return result
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
    }

    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}
