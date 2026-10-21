import Foundation

public enum WorkspaceError: Error, Equatable, Sendable {
    case rootNotFound(String)
    case rulesNotFound(String)
    case rules(RulesError)
    /// `PERFIL.md` existe pero no se puede leer: el espacio no se abre (spec del perfil, §6).
    case profile(ProfileError)
    case rulesAlreadyExist
    case locked(host: String, pid: Int32, since: Date)

    /// El bloqueo lo tiene este mismo proceso (la app ordenando a la vez), no el CLI ni otro Mac. Solo `.locked`.
    public var isHeldByThisProcess: Bool {
        guard case .locked(let host, let pid, let since) = self else { return false }
        return WorkspaceLock.Holder(host: host, pid: pid, since: since).isThisProcess
    }
}

public struct InboxListing: Sendable, Equatable {
    public var ready: [URL]
    public var inUse: [URL]
    public var ignoredFolders: [URL]
}

/// Una carpeta raíz con su `TRIA.md`. Todo el estado vive dentro (spec §6.1).
public struct Workspace: Sendable {
    public static let rulesFileName = "TRIA.md"
    public static let stateFolderName = ".tria"
    public static let profileFileName = ProfileFile.fileName

    public let root: URL
    public let rules: RulesFile
    /// Quién es el titular, si el espacio tiene `PERFIL.md` (spec del perfil).
    public let profile: ProfileFile?

    public var rulesURL: URL { root.appendingPathComponent(Self.rulesFileName) }
    public var profileURL: URL { root.appendingPathComponent(Self.profileFileName) }

    /// Lo que la caché tiene en cuenta del espacio: las reglas y, si hay, el perfil. Sin perfil es el hash de las
    /// reglas de siempre, así que actualizar Tria no invalida la caché de nadie (spec del perfil, §3).
    public var contextHash: String {
        guard let profile else { return rules.hash }
        return Hashing.sha256("\(rules.hash)|\(profile.hash)")
    }
    public var inboxURL: URL { root.appendingPathComponent(rules.header.inbox, isDirectory: true) }
    public var duplicatesURL: URL { root.appendingPathComponent(rules.header.duplicates, isDirectory: true) }
    public var stateURL: URL { root.appendingPathComponent(Self.stateFolderName, isDirectory: true) }
    public var journalURL: URL { stateURL.appendingPathComponent("journal.jsonl") }
    public var cacheURL: URL { stateURL.appendingPathComponent("cache", isDirectory: true) }
    public var suggestionsURL: URL { stateURL.appendingPathComponent("suggestions.jsonl") }
    public var lockURL: URL { stateURL.appendingPathComponent("lock") }
    public var protectedPaths: ProtectedPaths { ProtectedPaths(rules.header.protected) }

    public static func open(at root: URL) throws -> Workspace {
        let resolved = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw WorkspaceError.rootNotFound(resolved.path) }
        let rulesURL = resolved.appendingPathComponent(rulesFileName)
        guard let data = FileManager.default.contents(atPath: rulesURL.path) else {
            throw WorkspaceError.rulesNotFound(resolved.path)
        }
        do {
            let rules = try RulesFile.parse(String(decoding: data, as: UTF8.self))
            return Workspace(root: resolved, rules: rules, profile: try loadProfile(at: resolved))
        } catch let error as RulesError {
            throw WorkspaceError.rules(error)
        }
    }

    /// Espacio con reglas de un fichero externo: permite evaluar un archivo real sin escribir en él.
    public static func open(at root: URL, rulesFile: URL) throws -> Workspace {
        let resolved = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw WorkspaceError.rootNotFound(resolved.path) }
        guard let data = FileManager.default.contents(atPath: rulesFile.path) else {
            throw WorkspaceError.rulesNotFound(rulesFile.path)
        }
        do {
            let rules = try RulesFile.parse(String(decoding: data, as: UTF8.self))
            return Workspace(root: resolved, rules: rules, profile: try loadProfile(at: resolved))
        } catch let error as RulesError {
            throw WorkspaceError.rules(error)
        }
    }

    /// Busca `TRIA.md` subiendo desde `start`, como hace git con `.git`.
    public static func discover(from start: URL) throws -> Workspace {
        var current = start.standardizedFileURL.resolvingSymlinksInPath()
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(rulesFileName).path) {
                return try open(at: current)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { throw WorkspaceError.rulesNotFound(start.path) }
            current = parent
        }
    }

    public static func initialize(at root: URL, rulesText: String) throws -> Workspace {
        let rulesURL = root.appendingPathComponent(rulesFileName)
        if FileManager.default.fileExists(atPath: rulesURL.path) { throw WorkspaceError.rulesAlreadyExist }
        do { _ = try RulesFile.parse(rulesText) } catch let error as RulesError { throw WorkspaceError.rules(error) }
        // Un PERFIL.md que no se puede leer se detecta antes de escribir nada: así no queda un espacio a medias.
        do { _ = try ProfileFile.read(in: root) } catch let error as ProfileError { throw WorkspaceError.profile(error) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(rulesText.utf8).write(to: rulesURL, options: .withoutOverwriting)
        let workspace = try open(at: root)
        try workspace.ensureStructure()
        return workspace
    }

    public func ensureStructure() throws {
        for url in [inboxURL, duplicatesURL, stateURL, cacheURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func reloaded() throws -> Workspace { try Workspace.open(at: root) }

    /// Escribe `PERFIL.md` y devuelve el espacio con el perfil nuevo.
    public func saveProfile(_ profile: Profile, language: TemplateLanguage) throws -> Workspace {
        try Data(ProfileFile.render(profile, language: language).utf8).write(to: profileURL, options: .atomic)
        return try reloaded()
    }

    /// `TRIA.md`, sus borradores y `PERFIL.md` en la raíz: son del espacio, no documentos.
    public static func isSpaceFile(_ relativePath: String) -> Bool {
        guard !relativePath.contains("/") else { return false }
        return relativePath.hasPrefix("TRIA") || relativePath.lowercased() == profileFileName.lowercased()
    }

    private static func loadProfile(at root: URL) throws -> ProfileFile? {
        do { return try ProfileFile.read(in: root) } catch let error as ProfileError { throw WorkspaceError.profile(error) }
    }

    public func relativePath(of url: URL) -> String? {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let candidates = [url.standardizedFileURL.path, url.standardizedFileURL.resolvingSymlinksInPath().path]
        for path in candidates where path.hasPrefix(rootPath) {
            return String(path.dropFirst(rootPath.count)).normalizedRelativePath
        }
        return nil
    }

    public func url(forRelative path: String) -> URL {
        root.appendingPathComponent(path.normalizedRelativePath)
    }

    /// Los ficheros de la bandeja: listos, en uso y carpetas que no se procesan. «En uso» es lo que aún no se puede
    /// leer: una copia en curso (con la fecha del Finder o modificada hace menos de `stableFor` segundos) o un fichero
    /// que solo está en la nube. Lo que está en uso no se abre ni se le calcula el hash: `plan` y `status` solo miran
    /// `ready`. `isDownloaded` solo se cambia en las pruebas.
    public func inboxFiles(stableFor: TimeInterval = 2, now: Date = Date(),
                           isDownloaded: (URL) -> Bool = Workspace.isDownloaded) throws -> InboxListing {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        let items = try FileManager.default.contentsOfDirectory(
            at: inboxURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var listing = InboxListing(ready: [], inUse: [], ignoredFolders: [])
        var futureDated: [(url: URL, size: Int?, modified: Date)] = []
        for item in items {
            let values = try item.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true {
                listing.ignoredFolders.append(item)
            } else if values.isRegularFile == true {
                let modified = values.contentModificationDate ?? .distantPast
                if !isDownloaded(item) {
                    // Solo está en la nube (iCloud Drive, Dropbox…): espera a que se descargue. Leerlo forzaría la
                    // descarga, y Tria nunca la fuerza (spec de la app, §7).
                    listing.inUse.append(item)
                } else if Self.isFinderCopyInProgress(modified) {
                    listing.inUse.append(item)
                } else if modified.timeIntervalSince(now) > stableFor {
                    futureDated.append((item, values.fileSize, modified))
                } else if now.timeIntervalSince(modified) < stableFor {
                    listing.inUse.append(item)
                } else {
                    listing.ready.append(item)
                }
            }
        }
        // Con fecha futura (reloj desajustado de un NAS) la fecha no dice nada: se exige el mismo tamaño y la misma
        // fecha tras `stableFor` segundos (spec §6.3, paso 1). Solo se espera si hay alguno.
        if !futureDated.isEmpty {
            Thread.sleep(forTimeInterval: stableFor)
            for candidate in futureDated {
                let fresh = try? URL(fileURLWithPath: candidate.url.path)
                    .resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let stable = fresh?.fileSize == candidate.size && fresh?.contentModificationDate == candidate.modified
                if stable { listing.ready.append(candidate.url) } else { listing.inUse.append(candidate.url) }
            }
        }
        let byName: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        listing.ready.sort(by: byName)
        listing.inUse.sort(by: byName)
        listing.ignoredFolders.sort(by: byName)
        return listing
    }

    /// `false` para un fichero que solo está en la nube: iCloud Drive con «Optimizar el almacenamiento», o un proveedor
    /// de ficheros como Dropbox u OneDrive. Solo mira los metadatos, así que no lo descarga. Los proveedores de ficheros
    /// marcan sus ficheros sin datos con `SF_DATALESS`; iCloud Drive, además, dice si su copia local está al día.
    public static func isDownloaded(_ url: URL) -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0, info.st_flags & datalessFlag != 0 { return false }
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else { return true }
        return values.ubiquitousItemDownloadingStatus == .current
    }

    /// `SF_DATALESS` de `<sys/stat.h>`: el contenido del fichero no está en el disco.
    static let datalessFlag: UInt32 = 0x4000_0000

    /// El Finder marca las copias en curso con fecha 24 de enero de 1984 hasta que terminan.
    static func isFinderCopyInProgress(_ modified: Date) -> Bool {
        let day = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: modified)
        return day.year == 1984 && day.month == 1 && day.day == 24
    }

    /// Ficheros archivados: todo menos la bandeja, los duplicados, `.tria/` y los ficheros del espacio.
    public func archiveFiles() throws -> [ArchiveFile] {
        try ArchiveScanner.files(in: root, excluding: [rules.header.inbox, rules.header.duplicates])
            .filter { !Self.isSpaceFile($0.relativePath) }
    }
}
