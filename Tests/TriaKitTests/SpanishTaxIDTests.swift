import Testing
@testable import TriaKit

@Test(arguments: ["00000000T", "12345678Z", "X1234567L", "Y0000000Z", "B00000000", "B12345674", "Q1234567D",
                  "A12345674", "K1234567L", "Z1234567R", "b-0000000-0", "ES B00000000", " 12345678-z "])
func validSpanishTaxIDs(_ value: String) {
    #expect(SpanishTaxID.isValid(value))
}

@Test(arguments: ["12345678A", "B12345675", "X1234567A", "123456789", "B1234567", "", "ABCDEFGHI", "I12345674"])
func invalidSpanishTaxIDs(_ value: String) {
    #expect(!SpanishTaxID.isValid(value))
}

@Test func normalizationDropsSeparatorsAndTheVATPrefix() {
    #expect(SpanishTaxID.normalized("es b-00.000.000") == "B00000000")
    #expect(SpanishTaxID.normalized(" 12345678-z ") == "12345678Z")
}
