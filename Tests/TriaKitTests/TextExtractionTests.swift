import AppKit
import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private let filler = String(repeating: "Texto de relleno con contenido útil para superar el umbral. ", count: 3)

@Test func readsTheTextLayerOfAPDF() throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("factura.pdf")
    try FixtureFactory.textPDF(at: url, pages: ["FACTURA 2025-014 Cliente Ejemplo SA. " + filler, "Página dos. " + filler])
    let document = try DocumentExtractor().extract(url)
    #expect(document.method == .textLayer)
    #expect(document.pageCount == 2)
    #expect(document.text.contains("FACTURA 2025-014"))
    #expect(!document.needsImage)
    #expect(document.images.isEmpty)
}

@Test func onlyTheFirstThreePagesAreRead() throws {   // Review Focus 5
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("grande.pdf")
    try FixtureFactory.textPDF(at: url, pages: (1...5).map { "marcador-\($0) " + filler })
    let document = try DocumentExtractor().extract(url)
    #expect(document.pageCount == 5)
    #expect(document.text.contains("marcador-3"))
    #expect(!document.text.contains("marcador-4"))
}

@Test func respectsTheCharacterLimit() throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("largo.pdf")
    try FixtureFactory.textPDF(at: url, pages: [filler + filler])
    let document = try DocumentExtractor(limits: ExtractionLimits(maxCharacters: 50)).extract(url)
    #expect(document.text.count <= 50)
}

@Test(arguments: [
    ("docx", NSAttributedString.DocumentType.officeOpenXML),
    ("odt", .openDocument),
    ("rtf", .rtf),
    ("doc", .docFormat),
])
func convertsWordProcessingFormats(ext: String, type: NSAttributedString.DocumentType) throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("contrato.\(ext)")
    try FixtureFactory.richText(at: url, text: "Contrato de renting AutoRent", type: type)
    let document = try DocumentExtractor().extract(url)
    #expect(document.method == .converted)
    #expect(document.text.contains("Contrato de renting AutoRent"))
}

@Test func readsSpreadsheets() throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("gastos.xlsx")
    try FixtureFactory.xlsx(at: url, sheetName: "Gastos", rows: [["Concepto", "Importe"], ["Hosting", "12,50"]])
    let document = try DocumentExtractor().extract(url)
    #expect(document.method == .spreadsheet)
    #expect(document.text.contains("Gastos"))
    #expect(document.text.contains("Concepto\tImporte\nHosting\t12,50"))
}

@Test func decodesLatin1CSV() throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("lista.csv")
    try "Concepto;Importe\nCafé;2,10\n".data(using: .isoLatin1)!.write(to: url)
    let document = try DocumentExtractor().extract(url)
    #expect(document.method == .plainText)
    #expect(document.text.contains("Café"))
}

@Test func reportsEncryptedCorruptEmptyAndUnsupportedFiles() throws {
    let dir = try TempDir()
    let encrypted = dir.url.appendingPathComponent("cifrado.pdf")
    try FixtureFactory.encryptedPDF(at: encrypted, text: "secreto")
    #expect(throws: ExtractionError.encrypted) { try DocumentExtractor().extract(encrypted) }

    let corrupt = try dir.write("roto.pdf", "esto no es un pdf")
    #expect(throws: ExtractionError.self) { try DocumentExtractor().extract(corrupt) }

    let empty = try dir.write("vacio.pdf", "")
    #expect(throws: ExtractionError.unreadable("empty file")) { try DocumentExtractor().extract(empty) }

    let xls = try dir.write("viejo.xls", "binario")
    #expect(throws: ExtractionError.unsupportedFormat("xls")) { try DocumentExtractor().extract(xls) }
    let pages = try dir.write("nota.pages", "binario")
    #expect(throws: ExtractionError.unsupportedFormat("pages")) { try DocumentExtractor().extract(pages) }
}

@Test func tidyCollapsesBlankLinesAndTrims() {
    #expect(DocumentExtractor.tidy("  a\r\n\n\n\nb  ", limit: 100) == "a\n\nb")
    #expect(DocumentExtractor.usefulCharacters(" a b\nc ") == 3)
}
