import Foundation

public struct ResolvedPath: Sendable, Equatable {
    /// Ruta con los componentes existentes escritos como están en disco (NFC) y el resto tal cual.
    public var relative: String
    /// Cuántos componentes finales no existen todavía.
    public var missingComponents: Int
    /// Si un componente existe pero es un fichero, la ruta hasta él.
    public var blockedBy: String?
}

public enum PathResolver {
    public static func resolve(_ relative: String, root: URL) -> ResolvedPath {
        let components = relative.normalizedRelativePath.split(separator: "/").map(String.init)
        var resolved: [String] = []
        var current = root
        for (index, component) in components.enumerated() {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: current.path)) ?? []
            guard let match = entries.first(where: { $0.nfc.lowercased() == component.nfc.lowercased() }) else {
                resolved += components[index...]
                return ResolvedPath(relative: resolved.joined(separator: "/"),
                                    missingComponents: components.count - index, blockedBy: nil)
            }
            var isDirectory: ObjCBool = false
            let matchURL = current.appendingPathComponent(match)
            FileManager.default.fileExists(atPath: matchURL.path, isDirectory: &isDirectory)
            resolved.append(match.nfc)
            if !isDirectory.boolValue {
                let blocked = resolved.joined(separator: "/")
                resolved += components[(index + 1)...]
                return ResolvedPath(relative: resolved.joined(separator: "/"), missingComponents: 0, blockedBy: blocked)
            }
            current = matchURL
        }
        return ResolvedPath(relative: resolved.joined(separator: "/"), missingComponents: 0, blockedBy: nil)
    }
}
