import Foundation

public struct ArchiveFile: Sendable, Equatable {
    public var relativePath: String
    public var url: URL
    public var size: Int64
    public var modified: Date
}

public enum ArchiveScanner {
    /// Ficheros regulares bajo `root`, sin ocultos (incluye `.tria/`). `excluding` son carpetas
    /// relativas a la raíz que no se recorren. `maxDepth` cuenta componentes de la ruta del fichero.
    public static func files(in root: URL, excluding: [String] = [], maxDepth: Int? = nil) throws -> [ArchiveFile] {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let excluded = Set(excluding.map { $0.normalizedRelativePath.lowercased() })
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: rootPath, isDirectory: true),
            includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }

        var result: [ArchiveFile] = []
        for case let url as URL in enumerator {
            let fullPath = url.standardizedFileURL.path
            guard fullPath.hasPrefix(rootPath + "/") else { continue }
            let relative = String(fullPath.dropFirst(rootPath.count + 1)).normalizedRelativePath
            let depth = relative.split(separator: "/").count
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true {
                if excluded.contains(relative.lowercased()) || (maxDepth.map { depth >= $0 } ?? false) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true, maxDepth.map({ depth <= $0 }) ?? true else { continue }
            result.append(ArchiveFile(
                relativePath: relative, url: url, size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? .distantPast))
        }
        return result.sorted { $0.relativePath < $1.relativePath }
    }
}
