import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

@Test func jsonValueLiteralsRoundTrip() throws {
    let value: JSONValue = ["type": "object", "max": 4096, "strict": true, "items": ["a", nil]]
    let data = try value.encodedData()
    #expect(String(decoding: data, as: UTF8.self) == #"{"items":["a",null],"max":4096,"strict":true,"type":"object"}"#)
    #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
    #expect(value["type"]?.stringValue == "object")
}

@Test func sha256KnownVectors() {
    #expect(Hashing.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func sha256OfFileStreamsAndMatchesInMemoryHash() throws {
    let dir = try TempDir()
    let data = Data((0..<3_000_000).map { UInt8($0 % 251) })   // > 1 MiB: varios bloques
    let url = dir.url.appendingPathComponent("big.bin")
    try data.write(to: url)
    #expect(try Hashing.sha256(of: url) == Hashing.sha256(data))
}

@Test func nfcNormalizesDecomposedAccents() {
    let decomposed = "Correspondencia\u{0300}"   // "a" + acento grave combinante
    #expect(decomposed.nfc == "Correspondencià")
}

@Test func normalizedRelativePathCleansSeparators() {
    #expect("/a//b/./c/".normalizedRelativePath == "a/b/c")
    #expect("".normalizedRelativePath == "")
}
