import AppKit
import CoreText
import Foundation

public struct SyntheticDocument: Sendable, Equatable {
    public var folder: String
    public var filename: String
    public var text: String
}

/// Archivo ficticio de una SL (plantilla SL en castellano) para detectar regresiones sin datos reales (spec §9.2).
/// Entidades y NIF inventados. La línea 1 de cada texto es única: los tests la usan como marcador.
public enum SyntheticArchive {
    public static let documents: [SyntheticDocument] = [
        SyntheticDocument(folder: "1-Modelos Tributarios/Modelo 303 - IVA", filename: "Modelo 303 - 2025 - 3T.pdf", text: """
        AGENCIA TRIBUTARIA
        Modelo 303 - Impuesto sobre el Valor Añadido. Autoliquidación
        Ejercicio: 2025. Periodo: 3T
        NIF: B00000000. Razón social: EMPRESA EJEMPLO SL
        Resultado de la liquidación: 1.250,40 €
        Fecha de presentación: 20/10/2025
        """),
        SyntheticDocument(folder: "1-Modelos Tributarios/Modelo 111 - IRPF Retenciones", filename: "Modelo 111 - 2025 - 2T.pdf", text: """
        AGENCIA TRIBUTARIA
        Modelo 111 - Retenciones e ingresos a cuenta
        Rendimientos del trabajo y de actividades económicas. Ejercicio: 2025. Periodo: 2T
        NIF: B00000000. EMPRESA EJEMPLO SL
        Total liquidación: 2.310,00 €. Presentado el 15/07/2025
        """),
        SyntheticDocument(folder: "7-Facturas/Recibidas/2025/1T", filename: "Factura Imprenta Litoral - 2025-02-21.pdf", text: """
        IMPRENTA LITORAL SL. NIF B11111111
        FACTURA Nº IL-0457
        Fecha: 21/02/2025
        Cliente: EMPRESA EJEMPLO SL. NIF B00000000
        Tarjetas de visita, 500 unidades: 60,00 €. IVA 21%: 12,60 €. TOTAL: 72,60 €
        """),
        SyntheticDocument(folder: "7-Facturas/Emitidas/2025/3T", filename: "Factura Emitida 2025-031 Distribuciones Norte - 2025-08-12.pdf", text: """
        EMPRESA EJEMPLO SL. NIF B00000000
        FACTURA Nº 2025-031
        Fecha de emisión: 12/08/2025
        Cliente: DISTRIBUCIONES NORTE SL. NIF B22222222
        Mantenimiento de aplicación web, julio: 1.800,00 €. IVA 21%: 378,00 €. TOTAL: 2.178,00 €
        """),
        SyntheticDocument(folder: "2-Contratos/Renting", filename: "Contrato Renting Flota Verde - 2025-01.pdf", text: """
        CONTRATO DE ARRENDAMIENTO DE VEHÍCULOS (RENTING)
        En Girona, a 13 de enero de 2025
        De una parte, FLOTA VERDE SA, arrendadora.
        De otra parte, EMPRESA EJEMPLO SL, con NIF B00000000, arrendataria.
        Objeto: arrendamiento a largo plazo de una furgoneta durante 36 meses.
        """),
        SyntheticDocument(folder: "3-Actas y Documentos Societarios/Actas de Junta", filename: "Acta Junta General Extraordinaria - 2025-11-04.pdf", text: """
        ACTA
        Junta general extraordinaria de socios de EMPRESA EJEMPLO SL
        En Mataró, a 4 de noviembre de 2025, se reúnen los socios de la sociedad.
        Orden del día: 1. Cambio del domicilio social. 2. Ruegos y preguntas.
        """),
        SyntheticDocument(folder: "4-Correspondencia Bancaria", filename: "Banca Costa Azul - Transferencia Recibida - 2025-04-07.pdf", text: """
        BANCA COSTA AZUL
        Comunicación de transferencia recibida
        Fecha: 07/04/2025. Beneficiario: EMPRESA EJEMPLO SL
        Ordenante: DISTRIBUCIONES NORTE SL. Importe: 3.025,00 €. Concepto: Factura 2025-009
        """),
        SyntheticDocument(folder: "5-Ordenes Domiciliacion", filename: "Orden Domiciliacion Energia Clara - 2025-05-19.pdf", text: """
        ORDEN DE DOMICILIACIÓN DE ADEUDO DIRECTO SEPA
        Referencia de la orden: EC-778812
        Acreedor: ENERGIA CLARA SL. Deudor: EMPRESA EJEMPLO SL
        IBAN ES00 0000 0000 0000 0000 0000. Fecha: 19/05/2025. Firma del deudor.
        """),
        SyntheticDocument(folder: "8-Nominas", filename: "Nominas - 2025-09.pdf", text: """
        RESUMEN DE NÓMINAS
        Periodo de liquidación: septiembre 2025
        Empresa: EMPRESA EJEMPLO SL. CCC 08/0000000/00
        Trabajadores: 3. Total devengado: 9.450,00 €. Líquido a percibir: 7.380,12 €
        """),
        SyntheticDocument(folder: "9-Certificados", filename: "Certificado Corriente Obligaciones Seguridad Social - 2025-06-12.pdf", text: """
        TESORERÍA GENERAL DE LA SEGURIDAD SOCIAL
        Certificado de estar al corriente en el cumplimiento de las obligaciones
        Empresa: EMPRESA EJEMPLO SL. CCC 08/0000000/00
        La empresa se encuentra al corriente de sus obligaciones con la Seguridad Social.
        Fecha de emisión: 12/06/2025
        """),
        SyntheticDocument(folder: "10-Notificaciones AEAT", filename: "AEAT - Propuesta de Liquidacion - 2025-10-08.pdf", text: """
        AGENCIA TRIBUTARIA. NOTIFICACIÓN
        Propuesta de liquidación provisional
        Destinatario: EMPRESA EJEMPLO SL. NIF B00000000. Fecha: 08/10/2025
        Se le comunica la propuesta de liquidación y se abre el trámite de alegaciones.
        """),
        SyntheticDocument(folder: "15-Proteccion de Datos/Politicas Web", filename: "Politica de Cookies - tiendaejemplo.es - 2025.pdf", text: """
        POLÍTICA DE COOKIES
        tiendaejemplo.es
        Responsable: EMPRESA EJEMPLO SL
        Este sitio utiliza cookies técnicas y de análisis. Puede configurarlas en cualquier momento.
        Última actualización: marzo de 2025
        """),
    ]

    public static func build(at root: URL) throws -> Workspace {
        let workspace = try Workspace.initialize(at: root, rulesText: Templates.text(.sl, language: .es))
        for folder in Templates.folders(.sl, language: .es) {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for document in documents {
            try writePDF(document.text, to: root.appendingPathComponent("\(document.folder)/\(document.filename)"))
        }
        // El titular ficticio de los documentos: así `tria eval` mide emitidas y recibidas con perfil (spec del perfil, §8).
        return try workspace.saveProfile(Profile(kind: .sl, name: "EMPRESA EJEMPLO SL", taxID: "B00000000"), language: .es)
    }

    private static func writePDF(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil)
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: box.insetBy(dx: 40, dy: 40), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil), context)
        context.endPDFPage()
        context.closePDF()
    }
}
