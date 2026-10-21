import Foundation

/// Las rutas que vienen de fuera (el modelo, el journal, que es un fichero más del espacio) no son de fiar
/// (spec §6.5 y §11): se comprueban antes de tocar el disco.
enum PathSafety {
    /// Relativa, sin "~" inicial y sin componentes ocultos (".tria", ".oculta" y también "..").
    static func isSafeRelative(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else { return false }
        let components = trimmed.split(separator: "/").filter { $0 != "." }
        return !components.isEmpty && !components.contains { $0.hasPrefix(".") }
    }

    /// Ruta absoluta dentro de una Papelera (la del usuario o la `.Trashes` de un volumen). En Debug, también la de la
    /// tanda QA (`QATrash.folder`), si está puesta.
    static func isInTrash(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        guard path.hasPrefix("/"), !components.contains("..") else { return false }
        #if DEBUG
        if QATrash.contains(path) { return true }
        #endif
        return components.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }
}

extension Workspace {
    /// La ruta relativa con los enlaces simbólicos de la parte existente ya resueltos,
    /// o `nil` si, una vez resuelta, queda fuera de la raíz.
    func resolvedRelativePath(_ relative: String) -> String? {
        var existing = url(forRelative: relative)
        var missing: [String] = []
        while existing.path != root.path && !FileManager.default.fileExists(atPath: existing.path) {
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        let resolved = existing.resolvingSymlinksInPath().path
        let rootPath = root.path
        guard resolved == rootPath || resolved.hasPrefix(rootPath + "/") else { return nil }
        let base = resolved == rootPath ? "" : String(resolved.dropFirst(rootPath.count + 1))
        return ([base] + missing).filter { !$0.isEmpty }.joined(separator: "/").normalizedRelativePath
    }

    /// URL de una ruta relativa leída del journal, solo si es segura y queda dentro de la raíz.
    func containedURL(forRelative relative: String) -> URL? {
        guard PathSafety.isSafeRelative(relative), let resolved = resolvedRelativePath(relative),
              resolved.isEmpty || PathSafety.isSafeRelative(resolved) else { return nil }
        return url(forRelative: relative)
    }
}
