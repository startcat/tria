#if DEBUG
import Foundation
import Testing
@testable import TriaKit

/// La marca `[QA …]`: el texto que construye y lo que lee de un documento (spec QA §4).
struct QAMarkerTests {
    static let invoice = QAMarker.proposal(folder: "2-Facturas Recibidas/2026/4T",
                                           name: "Factura Papeleria Mar - 2026-10-09", type: "Factura",
                                           confidence: "alta", date: "2026-10-09")

    /// El texto exacto de «Interfaces comunes» del plan: las pruebas de interfaz llevan una copia (Tarea 6) que escribe
    /// lo mismo.
    @Test func theMarkersHaveTheTextOfThePlan() {
        #expect(Self.invoice.text == #"[QA carpeta="2-Facturas Recibidas/2026/4T" "#
                + #"nombre="Factura Papeleria Mar - 2026-10-09" tipo="Factura" confianza=alta fecha=2026-10-09]"#)
        #expect(QAMarker.proposal(folder: "A", name: "B", type: "C").text
                == #"[QA carpeta="A" nombre="B" tipo="C" confianza=alta]"#)
        #expect(QAMarker.doubt("No sé si es factura o presupuesto").text
                == #"[QA duda="No sé si es factura o presupuesto"]"#)
        #expect(QAMarker.error("sin-conexion").text == "[QA error=sin-conexion]")
        #expect(QAMarker.slow(2, then: .doubt("x")).text == #"[QA espera=2 duda="x"]"#)
    }

    @Test func theFirstMarkerIsFoundWithItsAttributes() throws {
        let found = try #require(QAMarker.find(in: "Factura nº 12\n\(Self.invoice.text)\n[QA duda=\"otra\"] Total 10 €"))
        #expect(found == Self.invoice)
        #expect(found.attributes == ["carpeta": "2-Facturas Recibidas/2026/4T",
                                     "nombre": "Factura Papeleria Mar - 2026-10-09", "tipo": "Factura",
                                     "confianza": "alta", "fecha": "2026-10-09"])
        #expect(QAMarker.slow(3, then: .error("cuota")).attributes == ["espera": "3", "error": "cuota"])
    }

    /// `QAMarker.slow` escribe una sola marca, con `espera` delante de lo demás (como la copia de las pruebas de
    /// interfaz, Tarea 6): se encuentra entera y se leen todos sus campos.
    @Test func aSlowProposalIsOneMarkerWithAllItsFields() throws {
        let slow = QAMarker.slow(2, then: Self.invoice)
        #expect(slow.text == #"[QA espera=2 carpeta="2-Facturas Recibidas/2026/4T" "#
                + #"nombre="Factura Papeleria Mar - 2026-10-09" tipo="Factura" confianza=alta fecha=2026-10-09]"#)
        let found = try #require(QAMarker.find(in: "Factura nº 12\n\(slow.text)\nTotal 10 €"))
        #expect(found == slow)
        #expect(found.attributes == ["espera": "2", "carpeta": "2-Facturas Recibidas/2026/4T",
                                     "nombre": "Factura Papeleria Mar - 2026-10-09", "tipo": "Factura",
                                     "confianza": "alta", "fecha": "2026-10-09"])
    }

    /// El PDF parte una marca larga en dos líneas y el OCR puede dar comillas tipográficas: se lee igual.
    @Test func aMarkerSplitAcrossLinesOrWithCurlyQuotesIsTheSameMarker() {
        let marker = QAMarker.proposal(folder: "7-Facturas/Recibidas", name: "Factura Papeleria Mar", type: "Factura")
        let split = #"[QA carpeta="7-Facturas/Recibidas" nombre="Factura"# + "\n"
            + #"Papeleria Mar" tipo="Factura" confianza=alta]"#
        #expect(QAMarker.find(in: split) == marker)
        let curly = "[QA carpeta=“7-Facturas/Recibidas” nombre=“Factura Papeleria Mar” tipo=„Factura” confianza=alta]"
        #expect(QAMarker.find(in: curly) == marker)
    }

    @Test func withoutAMarkerThereIsNothing() {
        #expect(QAMarker.find(in: "Factura nº 12. Total 10 €") == nil)
        #expect(QAMarker.find(in: "[QAX carpeta=\"A\"]") == nil)
        #expect(QAMarker.find(in: "[QA carpeta=\"A\" sin cerrar") == nil)
    }

    /// Un «]» dentro de unas comillas no cierra la marca.
    @Test func aBracketInsideQuotesDoesNotCloseTheMarker() throws {
        let found = try #require(QAMarker.find(in: #"[QA duda="¿[sic] o no?"] resto"#))
        #expect(found.attributes["duda"] == "¿[sic] o no?")
    }

    @Test func theRulesMarkersHaveAFixedShape() {
        #expect(QAMarker.rulesChange(rule: "Luz a 10-Suministros.", section: "s3", createFolder: "10-Suministros",
                                     summary: "Luz").text
                == "[QA regla=\"Luz a 10-Suministros.\" seccion=s3 carpeta-nueva=\"10-Suministros\" resumen=\"Luz\"]")
        #expect(QAMarker.rulesChange(rule: "x", title: "Suministros", removing: "- y").text
                == "[QA regla=\"x\" titulo=\"Suministros\" quita=\"- y\"]")
        #expect(QAMarker.rulesRefusal("Eso se hace en el Finder").text == "[QA negativa=\"Eso se hace en el Finder\"]")
        #expect(QAMarker.brokenAnswer.text == "[QA roto=si]")
        let marker = QAMarker.proposal(folder: "5-Bancos", name: "Recibo", type: "Recibo").suggesting(rule: "Los seguros, a 7-Seguros.")
        #expect(marker.text == "[QA carpeta=\"5-Bancos\" nombre=\"Recibo\" tipo=\"Recibo\" confianza=alta regla=\"Los seguros, a 7-Seguros.\" titulo=\"Casos especiales\"]")
        #expect(marker.attributes["carpeta"] == "5-Bancos")
        #expect(marker.attributes["regla"] == "Los seguros, a 7-Seguros.")
    }
}
#endif
