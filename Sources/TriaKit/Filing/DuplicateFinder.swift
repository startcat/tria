import Foundation

public struct DuplicateScan: Sendable, Equatable {
    public var hashes: [URL: String]
    public var originals: [URL: String]
    /// Ficheros de la bandeja que no se han podido leer, con el motivo: quedan pendientes, el lote sigue.
    public var unreadable: [URL: String] = [:]
}

/// Duplicados exactos por SHA-256, sin llamar a la IA (spec §6.3, paso 1).
public struct DuplicateFinder: Sendable {
    public let workspace: Workspace

    public init(workspace: Workspace) { self.workspace = workspace }

    /// Calcula el hash de los ficheros de la bandeja y busca su original: un archivado del mismo tamaño y el mismo
    /// hash o, si no lo hay, una copia anterior en la propia bandeja. Los archivados que solo están en la nube no se
    /// leen, porque leerlos forzaría su descarga (spec de la app, §7). Por eso no cuentan como original, y el fichero de
    /// la bandeja se lee como cualquier otro. `isDownloaded` solo se cambia en las pruebas.
    public func scan(_ inboxFiles: [URL], isDownloaded: (URL) -> Bool = Workspace.isDownloaded) throws -> DuplicateScan {
        try scan(inboxFiles, isDownloaded: isDownloaded, archiveFiles: workspace.archiveFiles)
    }

    /// `archiveFiles` lista el archivo; solo se cambia en las pruebas.
    func scan(_ inboxFiles: [URL], isDownloaded: (URL) -> Bool,
              archiveFiles: () throws -> [ArchiveFile]) throws -> DuplicateScan {
        var scan = DuplicateScan(hashes: [:], originals: [:])
        var sizes: [URL: Int64] = [:]
        for file in inboxFiles {
            do {
                scan.hashes[file] = try Hashing.sha256(of: file)
                sizes[file] = Int64((try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            } catch {
                scan.unreadable[file] = error.localizedDescription
            }
        }
        let wanted = Set(sizes.values.filter { $0 > 0 })
        // Sin nada que buscar, el archivo no se recorre: puede ser grande y estar en una unidad de red.
        guard !wanted.isEmpty else { return scan }
        let candidates = Dictionary(grouping: try archiveFiles()
            .filter { wanted.contains($0.size) && isDownloaded($0.url) }, by: \.size)
        var archiveHashes: [String: String] = [:]

        var firstInInbox: [String: String] = [:]
        for file in inboxFiles {
            guard let hash = scan.hashes[file], let size = sizes[file], size > 0 else { continue }
            for candidate in candidates[size] ?? [] {
                // Un archivado ilegible no puede ser el original de nada.
                guard let candidateHash = archiveHashes[candidate.relativePath]
                    ?? (try? Hashing.sha256(of: candidate.url)) else { continue }
                archiveHashes[candidate.relativePath] = candidateHash
                if candidateHash == hash {
                    scan.originals[file] = candidate.relativePath
                    break
                }
            }
            if scan.originals[file] == nil {
                if let original = firstInInbox[hash] { scan.originals[file] = original }
                else { firstInInbox[hash] = workspace.relativePath(of: file) }
            }
        }
        return scan
    }
}
