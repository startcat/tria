import Foundation

/// Inserta una regla bajo una sección de `TRIA.md` de forma determinista (spec §7.3). La sección se busca como en el
/// editor (`RulesDocument`): una línea `## ` fuera de un bloque de código, con ese título sin mirar mayúsculas (la
/// primera, si se repite). La viñeta va al final de su contenido, antes de sus líneas en blanco; si la sección no
/// existe, se añade al final. Siempre con los saltos de línea del fichero (`\n` o `\r\n`); lo demás no cambia.
public enum RulesPatcher {
    public static func insert(rule: String, section: String, into text: String) -> String {
        apply(rule: rule, section: section, to: text).text
    }

    /// Cambio exacto en formato diff: contexto con dos espacios, líneas añadidas con "+ ".
    public static func preview(rule: String, section: String, in text: String) -> String {
        let result = apply(rule: rule, section: section, to: text)
        let lines = RulesDocument.lines(result.text).map { $0.trimmingCharacters(in: .newlines) }
        var output: [String] = []
        let context = max(0, result.inserted.lowerBound - 2)..<min(lines.count, result.inserted.upperBound + 1)
        for index in context {
            output.append((result.inserted.contains(index) ? "+ " : "  ") + lines[index])
        }
        return output.joined(separator: "\n")
    }

    /// El texto con la viñeta y las líneas añadidas (por posición en el texto, desde 0).
    private static func apply(rule: String, section: String, to text: String) -> (text: String, inserted: Range<Int>) {
        let trimmed = rule.trimmingCharacters(in: .whitespaces)
        let bullet = trimmed.hasPrefix("- ") ? trimmed : "- " + trimmed
        let title = section.trimmingCharacters(in: .whitespaces)
        var document = RulesDocument.parse(text)
        let ending = document.lineEnding

        guard let index = document.sections.firstIndex(where: { $0.title.lowercased() == title.lowercased() }) else {
            let appended = document.appending("## \(title)\n\n\(bullet)\n")
            let count = RulesDocument.lines(appended.text).count
            return (appended.text, (count - 3)..<count)
        }
        var lines = RulesDocument.lines(document.sections[index].text)
        let last = lines.lastIndex { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? 0
        // Solo la última línea del fichero puede no llevar salto: se le pone, y la viñeta se queda sin él.
        let terminated = lines[last].unicodeScalars.last == "\n"
        if !terminated { lines[last] += ending }
        // Bajo un título sin nada más, la viñeta va tras una línea en blanco.
        let blank = last == 0 ? [ending] : []
        lines.insert(contentsOf: blank + [bullet + (terminated ? ending : "")], at: last + 1)
        let before = RulesDocument.lines(document.frontmatter + document.preamble
                                         + document.sections[..<index].map(\.text).joined()).count
        document.sections[index].text = lines.joined()
        let position = before + last + 1 + blank.count
        return (document.text, position..<(position + 1))
    }
}
