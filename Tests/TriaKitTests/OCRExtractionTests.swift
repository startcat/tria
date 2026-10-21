import Foundation
import ImageIO
import Testing
import TriaTestSupport
@testable import TriaKit

private let invoiceLines = ["FACTURA NUMERO 2025-014", "CLIENTE EJEMPLO SOCIEDAD ANONIMA", "IMPORTE TOTAL 1210 EUROS"]

@Test func visionReadsTextFromAnImage() throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("foto.png")
    try FixtureFactory.png(at: url, lines: invoiceLines)
    let document = try DocumentExtractor().extract(url)
    #expect(document.method == .ocr)
    #expect(document.text.uppercased().contains("FACTURA"))
    #expect(document.pageCount == 1)
}

@Test func visionReadsAScannedPDF() throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("escaneo.pdf")
    try FixtureFactory.imageOnlyPDF(at: url, lines: invoiceLines)
    let document = try DocumentExtractor().extract(url)
    #expect(document.method == .ocr)
    #expect(document.text.uppercased().contains("FACTURA"))
}

@Test func ocrRescuesAShortTextLayer() throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("corto.pdf")
    try FixtureFactory.textPDF(at: url, pages: ["Hola"])
    let extractor = DocumentExtractor(recognizer: StubRecognizer(text: String(repeating: "texto reconocido ", count: 20)))
    let document = try extractor.extract(url)
    #expect(document.method == .ocr)
    #expect(!document.needsImage)
}

@Test func blankImageFallsBackToAResizedJPEG() throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("blanco.png")
    try FixtureFactory.blankPNG(at: url)
    let document = try DocumentExtractor(recognizer: StubRecognizer(text: "")).extract(url)
    #expect(document.needsImage)
    let jpeg = try #require(document.images.first)
    #expect(jpeg.prefix(2) == Data([0xFF, 0xD8]))
    let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(max(image.width, image.height) <= 1568)
}

@Test func blankPDFSendsTheFirstTwoPages() throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("vacio.pdf")
    try FixtureFactory.blankPDF(at: url, pages: 3)
    let document = try DocumentExtractor(recognizer: StubRecognizer(text: "")).extract(url)
    #expect(document.needsImage)
    #expect(document.images.count == 2)
}

@Test func imagesCanBeDisabled() throws {
    let dir = try TempDir()
    let url = dir.url.appendingPathComponent("vacio.pdf")
    try FixtureFactory.blankPDF(at: url, pages: 1)
    let extractor = DocumentExtractor(limits: ExtractionLimits(includeImages: false), recognizer: StubRecognizer(text: ""))
    let document = try extractor.extract(url)
    #expect(document.needsImage)
    #expect(document.images.isEmpty)
}

@Test func catalanIsOnlyRequestedWhenVisionSupportsIt() {
    #expect(VisionTextRecognizer.languages(supported: ["en-US", "es-ES"]) == ["es-ES", "en-US"])
    #expect(VisionTextRecognizer.languages(supported: ["ca-ES", "es-ES", "en-US"]) == ["es-ES", "ca-ES", "en-US"])
}
