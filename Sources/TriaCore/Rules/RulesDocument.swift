import Foundation

/// Una sección de `TRIA.md`: desde su línea `## ` hasta la siguiente o el final (spec de Reglas, §3).
public struct RulesSection: Equatable, Sendable, Identifiable {
    /// "s1", "s2"…, por orden. Estable mientras no cambie el fichero.
    public var id: String
    /// El texto tras "## ", sin espacios a los lados.
    public var title: String
    /// La sección entera, título incluido, con sus saltos de línea tal cual.
    public var text: String

    public init(id: String, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

/// `TRIA.md` partido en piezas, sin interpretarlas (spec de Reglas, §3): la cabecera con sus dos líneas `---`, lo que va
/// de la cabecera a la primera sección y las secciones. Una sección empieza en una línea `## ` fuera de un bloque de
/// código. No valida: eso sigue siendo `RulesFile.parse`. Vuelve a dar el texto exacto: `parse(t).text == t`, también
/// con `\r\n`, con marca de orden de bytes o sin salto final. Las secciones se identifican por posición: un `TRIA.md`
/// escrito a mano puede repetir títulos.
public struct RulesDocument: Equatable, Sendable {
    public var frontmatter: String
    public var preamble: String
    public var sections: [RulesSection]

    public init(frontmatter: String = "", preamble: String = "", sections: [RulesSection] = []) {
        self.frontmatter = frontmatter
        self.preamble = preamble
        self.sections = sections
    }

    public var text: String { frontmatter + preamble + sections.map(\.text).joined() }

    /// Los saltos de línea del fichero: `\r\n` si los usa; si no, `\n`.
    public var lineEnding: String { text.contains("\r\n") ? "\r\n" : "\n" }

    public func section(_ id: String) -> RulesSection? { sections.first { $0.id == id } }

    /// La misma sección en otra versión del fichero: la del mismo `id` si conserva el título; si no, la única con ese
    /// título. `nil` si no hay ninguna o hay varias.
    public func matching(_ section: RulesSection) -> RulesSection? {
        if let same = self.section(section.id), same.title == section.title { return same }
        let titled = sections.filter { $0.title == section.title }
        return titled.count == 1 ? titled[0] : nil
    }

    public static func parse(_ text: String) -> RulesDocument {
        let lines = Self.lines(text)
        var start = 0
        var frontmatter = ""
        if let first = lines.first, isDashes(first),
           let end = lines.indices.dropFirst().first(where: { isDashes(lines[$0]) }) {
            frontmatter = lines[...end].joined()
            start = end + 1
        }
        var preamble = ""
        var sections: [RulesSection] = []
        var fence: String?
        for line in lines[start...] {
            let content = Self.content(line)
            if fence == nil, content.hasPrefix("## ") {
                let title = String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                sections.append(RulesSection(id: "s\(sections.count + 1)", title: title, text: line))
            } else if sections.isEmpty {
                preamble += line
            } else {
                sections[sections.count - 1].text += line
            }
            if let marker = fenceMarker(content) {
                if fence == nil { fence = marker } else if fence == marker { fence = nil }
            }
        }
        return RulesDocument(frontmatter: frontmatter, preamble: preamble, sections: sections)
    }

    /// El documento con la sección `id` cambiada por `text` (una sola sección, que empieza por `## `). El texto nuevo
    /// usa los saltos de línea del fichero y acaba con tantos como la sección que sustituye, para no pegarse a la
    /// siguiente. Lo demás no cambia. `nil` si la sección no existe.
    public func replacing(_ id: String, with text: String) -> RulesDocument? {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = self
        let body = Self.normalized(text, breaks: Self.trailingBreaks(sections[index].text), lineEnding: lineEnding)
        copy.sections[index] = RulesSection(id: id, title: Self.title(of: body), text: body)
        return copy
    }

    /// El documento con una sección nueva al final, separada de lo anterior por una línea en blanco.
    public func appending(_ text: String) -> RulesDocument {
        var copy = self
        let ending = lineEnding
        let missing = max(0, 2 - Self.trailingBreaks(copy.text))
        if !copy.text.isEmpty, missing > 0 {
            let separator = String(repeating: ending, count: missing)
            if copy.sections.isEmpty {
                copy.preamble += separator
            } else {
                copy.sections[copy.sections.count - 1].text += separator
            }
        }
        let body = Self.normalized(text, breaks: 1, lineEnding: ending)
        copy.sections.append(RulesSection(id: "s\(copy.sections.count + 1)", title: Self.title(of: body), text: body))
        return copy
    }

    /// El documento con otra cabecera (`---` … `---`), con los saltos de línea del fichero y su marca de orden de bytes.
    public func replacingFrontmatter(_ frontmatter: String) -> RulesDocument {
        var copy = self
        let body = Self.normalized(frontmatter, breaks: 1, lineEnding: lineEnding)
        copy.frontmatter = self.frontmatter.hasPrefix("\u{FEFF}") ? "\u{FEFF}" + body : body
        return copy
    }

    /// La primera sección, por posición, que no se volvería a leer igual (con su título y en su sitio) al escribir el
    /// documento y leerlo otra vez: lo de antes deja abierto un bloque de código que se la tragaría. `nil` si todas se
    /// leen igual. Si sobra alguna al final, el número de secciones.
    package func firstLostSection() -> Int? {
        let titles = sections.map(\.title)
        let reread = Self.parse(text).sections.map(\.title)
        guard reread != titles else { return nil }
        return titles.indices.first { $0 >= reread.count || reread[$0] != titles[$0] } ?? titles.count
    }

    /// La línea, contando desde 1, donde se abre un bloque de código que el texto deja sin cerrar; `nil` si los cierra
    /// todos. Cuenta como `parse`: un bloque se cierra con el mismo marcador que lo abre.
    package static func openFenceLine(_ text: String) -> Int? {
        var open: (marker: String, line: Int)?
        for (index, line) in lines(text).enumerated() {
            guard let marker = fenceMarker(content(line)) else { continue }
            if open == nil { open = (marker, index + 1) } else if open?.marker == marker { open = nil }
        }
        return open?.line
    }

    // MARK: - Apoyo

    /// Las líneas con su salto (`\n` o `\r\n`) al final; la última, sin él si el texto no acaba en salto. Se parte con
    /// Foundation: en Swift, `\r\n` es un solo carácter y `split(separator: "\n")` no lo partiría.
    package static func lines(_ text: String) -> [String] {
        var parts = text.components(separatedBy: "\n")
        let last = parts.removeLast()
        var lines = parts.map { $0 + "\n" }
        if !last.isEmpty { lines.append(last) }
        return lines
    }

    /// Los saltos de línea del final del texto (un `\r\n` cuenta como uno).
    private static func trailingBreaks(_ text: String) -> Int {
        var count = 0
        for scalar in text.unicodeScalars.reversed() {
            if scalar == "\n" {
                count += 1
            } else if scalar != "\r" {
                break
            }
        }
        return count
    }

    /// El texto con `breaks` saltos al final y los saltos de línea del fichero.
    static func normalized(_ text: String, breaks: Int, lineEnding: String) -> String {
        var body = text.replacingOccurrences(of: "\r\n", with: "\n")
        while body.hasSuffix("\n") { body.removeLast() }
        body += String(repeating: "\n", count: breaks)
        return lineEnding == "\n" ? body : body.replacingOccurrences(of: "\n", with: lineEnding)
    }

    /// La línea sin su salto ni la marca de orden de bytes.
    private static func content(_ line: String) -> String {
        line.trimmingCharacters(in: .newlines).replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    private static func isDashes(_ line: String) -> Bool {
        content(line).trimmingCharacters(in: .whitespaces) == "---"
    }

    /// "```" o "~~~" si la línea abre o cierra un bloque de código (con hasta tres espacios delante).
    private static func fenceMarker(_ content: String) -> String? {
        let trimmed = content.drop { $0 == " " }
        guard content.count - trimmed.count <= 3 else { return nil }
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func title(of section: String) -> String {
        let first = lines(section).first.map(content) ?? ""
        return first.hasPrefix("## ") ? String(first.dropFirst(3)).trimmingCharacters(in: .whitespaces) : first
    }
}
