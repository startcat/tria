import Testing
@testable import TriaKit

@Test func patternProtectsMatchingFolderAndDescendants() {
    let protected = ProtectedPaths(["7-Facturas/20*/"])
    #expect(protected.contains("7-Facturas/2013"))
    #expect(protected.contains("7-Facturas/2013/1T/Factura X.pdf"))
    #expect(!protected.contains("7-Facturas"))
    #expect(!protected.contains("7-Facturas/Libros Trimestrales/x.pdf"))
}

@Test func matchingIsCaseInsensitive() {
    #expect(ProtectedPaths(["7-Facturas/20*"]).contains("7-facturas/2013/a.pdf"))
}

@Test func matchingNormalizesNFD() {
    let decomposedPath = "Correspondencia\u{0300}/2020/carta.pdf"
    #expect(ProtectedPaths(["Correspondencià/*"]).contains(decomposedPath))
}

@Test func emptyPatternsProtectNothing() {
    #expect(!ProtectedPaths([]).contains("a/b"))
}

@Test func caseFoldingCoversAccentedLetters() {
    #expect(ProtectedPaths(["Correspondència/*"]).contains("CORRESPONDÈNCIA/2020/carta.pdf"))
}
