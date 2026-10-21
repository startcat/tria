import Darwin
import Foundation

/// Rutas que Tria no toca nunca: ni mueve nada hacia dentro ni hacia fuera (spec §6.2).
/// Un patrón protege la carpeta que encaja y todo lo que contiene.
public struct ProtectedPaths: Sendable, Equatable {
    public let patterns: [String]

    public init(_ patterns: [String]) {
        self.patterns = patterns.map(\.normalizedRelativePath).filter { !$0.isEmpty }
    }

    public func contains(_ relativePath: String) -> Bool {
        // fnmatch solo iguala mayúsculas en ASCII: se compara en minúsculas para que "È" y "è" coincidan.
        let components = relativePath.normalizedRelativePath.lowercased().split(separator: "/").map(String.init)
        guard !components.isEmpty else { return false }
        for length in 1...components.count {
            let prefix = components[0..<length].joined(separator: "/")
            for pattern in patterns where fnmatch(pattern.lowercased(), prefix, FNM_PATHNAME | FNM_CASEFOLD) == 0 {
                return true
            }
        }
        return false
    }
}
