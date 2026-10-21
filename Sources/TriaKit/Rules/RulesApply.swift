import Foundation

extension Workspace {
    /// `.tria/rules-history/`: las versiones anteriores de `TRIA.md`, una por cambio aplicado (spec de Reglas, §4.3).
    public var rulesHistoryURL: URL { stateURL.appendingPathComponent("rules-history", isDirectory: true) }

    /// Aplica un cambio de reglas (spec de Reglas, §4.3) y devuelve el espacio recargado:
    /// 1. si `TRIA.md` ya no es el del cambio, `changedOnDisk` y no escribe (se mira antes y después del cerrojo);
    /// 2. toma el cerrojo del espacio, como al ordenar; si lo tiene otro, `locked` (o `lockedByThisProcess`, si es este
    ///    mismo proceso);
    /// 3. guarda la versión anterior en `.tria/rules-history/AAAA-MM-DD-HHMMSS.md` y deja las 20 últimas (si no puede
    ///    borrar las viejas, sigue);
    /// 4. crea las carpetas, escribe `TRIA.md` de forma atómica y lo vuelve a leer; si no se pudiera, deja el de antes.
    ///
    /// Nunca renombra, mueve ni borra nada del archivo: solo crea carpetas, y solo dentro del espacio.
    public func apply(_ change: RulesChange, now: Date = Date()) throws -> Workspace {
        _ = try rulesOnDisk(matching: change.baseHash)
        let lock: WorkspaceLock
        do {
            lock = try WorkspaceLock.acquire(self)
        } catch let error as WorkspaceError {
            if case .locked = error {
                throw error.isHeldByThisProcess ? RulesChangeError.lockedByThisProcess : RulesChangeError.locked
            }
            throw error
        }
        defer { lock.release() }
        let previous = try rulesOnDisk(matching: change.baseHash)
        do { _ = try RulesFile.parse(change.newText) } catch let error as RulesError {
            throw RulesChangeError.invalidRules(error)
        }
        let folders = try change.createFolders.map { path -> URL in
            guard let url = containedURL(forRelative: path), !isReserved(path) else {
                throw RulesChangeError.unsafeFolder(path)
            }
            return url
        }
        try RulesHistory.save(previous, in: rulesHistoryURL, now: now)
        // Si no se pueden borrar las copias más viejas, el cambio se aplica igual: sobran copias, no falta ninguna.
        try? RulesHistory.prune(rulesHistoryURL)
        for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try Data(change.newText.utf8).write(to: rulesURL, options: .atomic)
        do {
            return try reloaded()
        } catch {
            try? previous.write(to: rulesURL, options: .atomic)
            throw error
        }
    }

    /// Si la carpeta es la bandeja, la de duplicados o `.tria`, o cae dentro de una (sin mirar mayúsculas): en ellas no
    /// se crean carpetas nuevas.
    func isReserved(_ path: String) -> Bool {
        let folder = path.normalizedRelativePath.lowercased()
        return [rules.header.inbox, rules.header.duplicates, Self.stateFolderName].contains { reserved in
            let reserved = reserved.normalizedRelativePath.lowercased()
            return folder == reserved || folder.hasPrefix(reserved + "/")
        }
    }

    /// `TRIA.md` tal como está en el disco, si su hash (el de `RulesFile.hash`) es `hash`.
    private func rulesOnDisk(matching hash: String) throws -> Data {
        guard let data = FileManager.default.contents(atPath: rulesURL.path),
              Hashing.sha256(String(decoding: data, as: UTF8.self)) == hash else {
            throw RulesChangeError.changedOnDisk
        }
        return data
    }
}

/// Las copias de `TRIA.md` de antes de cada cambio aplicado. Deshacerlas desde la app queda fuera (spec, §12).
enum RulesHistory {
    static let keep = 20

    static func save(_ data: Data, in folder: URL, now: Date) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        // Dos cambios en el mismo segundo: «… (2).md».
        let name = Collision.uniqueRelativePath(formatter.string(from: now) + ".md", root: folder)
        try data.write(to: folder.appendingPathComponent(name), options: .withoutOverwriting)
    }

    /// Deja las `keep` más recientes por fecha de modificación (y por nombre, si coinciden).
    static func prune(_ folder: URL) throws {
        let key = URLResourceKey.contentModificationDateKey
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [key],
                                                                options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "md" }
            .map { ($0, (try? $0.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast) }
            .sorted { ($0.1, $0.0.lastPathComponent) < ($1.1, $1.0.lastPathComponent) }
        for (url, _) in files.dropLast(keep) { try FileManager.default.removeItem(at: url) }
    }
}
