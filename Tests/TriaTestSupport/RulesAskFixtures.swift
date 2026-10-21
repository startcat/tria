import Foundation
import TriaKit

/// Ayudantes de las pruebas de «pídeselo a Tria» (motor y CLI).
/// La respuesta de `tria_rules_change` que daría el modelo.
public func reply(summary: String = "Las facturas de la luz van a 10-Suministros", refusal: String? = nil,
                   sections: [(String, String)] = [], header: JSONValue = .null, folders: [String] = []) -> String {
    let value: JSONValue = [
        "summary": .string(summary), "refusal": refusal.map(JSONValue.string) ?? .null,
        "sections": .array(sections.map { ["id": .string($0.0), "text": .string($0.1)] }),
        "header": header, "create_folders": .array(folders.map(JSONValue.string)),
    ]
    return String(decoding: try! value.encodedData(), as: UTF8.self)
}

public let suministros = "## Suministros\n\n- Las facturas de la luz van a `10-Suministros/`.\n"
