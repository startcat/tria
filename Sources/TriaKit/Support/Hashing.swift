import CryptoKit
import Foundation

public enum Hashing {
    /// SHA-256 de un fichero leyendo en bloques de 1 MiB (nunca carga el fichero entero en memoria).
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    public static func sha256(_ data: Data) -> String { hex(SHA256.hash(data: data)) }

    public static func sha256(_ string: String) -> String { sha256(Data(string.utf8)) }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
