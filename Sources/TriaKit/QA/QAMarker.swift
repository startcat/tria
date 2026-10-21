#if DEBUG
import Foundation

/// La marca `[QA …]` que lleva en su texto un documento de la tanda QA, y que `QAProvider` lee para decidir qué
/// contesta (spec QA §4). Solo existe en Debug: la versión que se publica no la lleva.
///
/// Gramática: `[QA clave=valor clave="valor con espacios" …]`. Un valor entre comillas no puede llevar comillas.
/// - `carpeta="…" nombre="…" tipo="…" confianza=alta|media|baja fecha=AAAA-MM-DD`: una propuesta. `nombre` va sin
///   extensión (se pone la del documento) y `fecha` es opcional.
/// - `duda="…"`: pendiente con esa duda.
/// - `error=sin-conexion|rechazo|negativa|cuota`: el fallo de un proveedor de verdad.
/// - `espera=N`: tarda N segundos antes de contestar; va con cualquiera de las otras.
///
/// Al buscarla en un texto, las comillas tipográficas (“ ” „) cuentan como rectas y cada tramo de espacios o saltos de
/// línea cuenta como un espacio: el PDF y el OCR pueden partir la marca en dos líneas o cambiar las comillas.
public struct QAMarker: Sendable, Equatable {
    /// El texto de la marca, tal como va en el documento.
    public var text: String

    public init(text: String) { self.text = text }

    /// `[QA carpeta="2-Facturas Recibidas/2026/4T" nombre="Factura Papeleria Mar - 2026-10-09" tipo="Factura"
    /// confianza=alta fecha=2026-10-09]`. `confidence`: "alta", "media" o "baja".
    public static func proposal(folder: String, name: String, type: String, confidence: String = "alta",
                                date: String? = nil) -> QAMarker {
        var text = "[QA carpeta=\"\(folder)\" nombre=\"\(name)\" tipo=\"\(type)\" confianza=\(confidence)"
        if let date { text += " fecha=\(date)" }
        return QAMarker(text: text + "]")
    }

    /// `[QA duda="No sé si es factura o presupuesto"]`.
    public static func doubt(_ text: String) -> QAMarker {
        QAMarker(text: "[QA duda=\"\(text)\"]")
    }

    /// `[QA error=sin-conexion]`. `kind`: "sin-conexion", "rechazo", "negativa" o "cuota".
    public static func error(_ kind: String) -> QAMarker {
        QAMarker(text: "[QA error=\(kind)]")
    }

    /// `[QA espera=2 …]`: la misma marca, pero tarda esos segundos.
    public static func slow(_ seconds: Int, then marker: QAMarker) -> QAMarker {
        QAMarker(text: "[QA espera=\(seconds) " + marker.text.dropFirst(4))
    }

    /// `[QA regla="…" seccion=s3 titulo="…" quita="…" carpeta-nueva="…" resumen="…"]`: el cambio con el que contesta
    /// «pídeselo a Tria» (spec de Reglas, §9). Sin `section`, la regla va en una sección nueva.
    public static func rulesChange(rule: String, section: String? = nil, title: String? = nil, removing: String? = nil,
                                   createFolder: String? = nil, summary: String? = nil) -> QAMarker {
        var text = "[QA regla=\"\(rule)\""
        if let section { text += " seccion=\(section)" }
        if let title { text += " titulo=\"\(title)\"" }
        if let removing { text += " quita=\"\(removing)\"" }
        if let createFolder { text += " carpeta-nueva=\"\(createFolder)\"" }
        if let summary { text += " resumen=\"\(summary)\"" }
        return QAMarker(text: text + "]")
    }

    /// `[QA negativa="…"]`: «pídeselo a Tria» contesta que no, con ese motivo.
    public static func rulesRefusal(_ reason: String) -> QAMarker { QAMarker(text: "[QA negativa=\"\(reason)\"]") }

    /// `[QA roto=si]`: una respuesta a «pídeselo a Tria» que no es JSON.
    public static let brokenAnswer = QAMarker(text: "[QA roto=si]")

    /// La misma marca con la regla que sugerirá Tria si el usuario corrige el documento: `regla="…" titulo="…"` al
    /// final.
    public func suggesting(rule: String, section: String = "Casos especiales") -> QAMarker {
        QAMarker(text: String(text.dropLast()) + " regla=\"\(rule)\" titulo=\"\(section)\"]")
    }

    /// Las comillas que pueden llegar del PDF o del OCR en lugar de las rectas.
    static let quotes: Set<Character> = ["\"", "“", "”", "„"]

    /// La primera marca de `text`, con las comillas y los espacios normalizados, o `nil` si no hay ninguna.
    public static func find(in text: String) -> QAMarker? {
        var searchFrom = text.startIndex
        while let start = text.range(of: "[QA", range: searchFrom..<text.endIndex) {
            searchFrom = start.upperBound
            // «[QA» seguido de otra letra no es una marca.
            guard start.upperBound < text.endIndex,
                  text[start.upperBound].isWhitespace || text[start.upperBound] == "]" else { continue }
            var index = start.upperBound
            var quoted = false
            while index < text.endIndex {
                let character = text[index]
                if quotes.contains(character) {
                    quoted.toggle()
                } else if character == "]" && !quoted {
                    return QAMarker(text: normalized(text[start.lowerBound...index]))
                }
                index = text.index(after: index)
            }
            return nil
        }
        return nil
    }

    /// Los pares `clave=valor` de la marca. Las claves, en minúscula; si una se repite, cuenta la primera.
    public var attributes: [String: String] {
        guard text.hasPrefix("[QA"), text.hasSuffix("]") else { return [:] }
        var result: [String: String] = [:]
        var rest = Substring(text.dropFirst(3).dropLast())
        while true {
            rest = rest.drop(while: \.isWhitespace)
            guard let equals = rest.firstIndex(of: "=") else { break }
            let key = rest[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            rest = rest[rest.index(after: equals)...]
            let value: Substring
            if rest.first == "\"" {
                let body = rest.dropFirst()
                let close = body.firstIndex(of: "\"") ?? body.endIndex
                value = body[..<close]
                rest = close < body.endIndex ? body[body.index(after: close)...] : body[body.endIndex...]
            } else {
                let end = rest.firstIndex(where: \.isWhitespace) ?? rest.endIndex
                value = rest[..<end]
                rest = rest[end...]
            }
            if !key.isEmpty, result[key] == nil { result[key] = value.trimmingCharacters(in: .whitespaces) }
        }
        return result
    }

    private static func normalized(_ raw: Substring) -> String {
        var text = String(raw)
        for quote in quotes where quote != "\"" { text = text.replacingOccurrences(of: String(quote), with: "\"") }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
#endif
