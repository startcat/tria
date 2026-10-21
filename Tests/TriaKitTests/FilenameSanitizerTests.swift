import Testing
@testable import TriaKit

@Test(arguments: [
    ("Modelo 303 - 2023 - 1T.pdf", "doc_x.PDF", "Modelo 303 - 2023 - 1T.PDF"),
    ("Factura: Luz/Agua", "a.pdf", "Factura- Luz-Agua.pdf"),
    ("  ..oculto  ", "a.pdf", "oculto.pdf"),
    ("Nombre.docx", "x.pdf", "Nombre.pdf"),
    ("Acta v1.2", "x.pdf", "Acta v1.2.pdf"),
    ("a\u{0007}b   c", "x.pdf", "ab c.pdf"),
    ("Sin extensión", "LEEME", "Sin extensión"),
])
func sanitizes(proposed: String, original: String, expected: String) {
    #expect(FilenameSanitizer.sanitize(proposed, originalFilename: original) == expected)
}

@Test func emptyNamesAreRejected() {
    #expect(FilenameSanitizer.sanitize("", originalFilename: "a.pdf") == nil)
    #expect(FilenameSanitizer.sanitize(" ... ", originalFilename: "a.pdf") == nil)
}

@Test func longNamesAreTruncatedKeepingTheExtension() throws {
    let name = try #require(FilenameSanitizer.sanitize(String(repeating: "ñ", count: 300), originalFilename: "a.pdf"))
    #expect(name.utf8.count <= 255)
    #expect(name.hasSuffix(".pdf"))
}
