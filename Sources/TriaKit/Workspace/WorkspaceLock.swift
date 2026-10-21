import Darwin
import Foundation

/// Bloqueo de proceso en `.tria/lock` (spec §6.7). Funciona en volúmenes de red (no usa flock).
public final class WorkspaceLock: @unchecked Sendable {
    public let url: URL
    private var released = false

    private struct Info: Codable {
        var pid: Int32
        var host: String
        var since: Date
    }

    /// Quién tiene el bloqueo: el Mac, el proceso y desde cuándo. Si el fichero aún no se ha podido leer (otro proceso
    /// que acaba de crearlo), el Mac es «?» y el proceso, 0.
    public struct Holder: Equatable, Sendable {
        public let host: String
        public let pid: Int32
        public let since: Date

        /// Es este mismo proceso (este Mac y este pid): quien pregunta, no el CLI ni otro Mac.
        public var isThisProcess: Bool { host == WorkspaceLock.thisHost && pid == getpid() }
    }

    /// Lo que vale el fichero del bloqueo.
    private enum Standing {
        /// Lo tiene alguien.
        case held(Holder)
        /// Ya no vale (viejo, de un proceso muerto de este Mac, o ilegible y viejo) o no está: `acquire` lo retira.
        case stale
    }

    private init(url: URL) { self.url = url }

    public static func acquire(_ ws: Workspace, staleAfter: TimeInterval = 43_200) throws -> WorkspaceLock {
        try FileManager.default.createDirectory(at: ws.stateURL, withIntermediateDirectories: true)
        for attempt in 0..<2 {
            let fd = open(ws.lockURL.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
            if fd >= 0 {
                let info = Info(pid: getpid(), host: thisHost, since: Date())
                let data = try encoder.encode(info)
                _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
                close(fd)
                return WorkspaceLock(url: ws.lockURL)
            }
            guard errno == EEXIST, attempt == 0 else { break }
            switch standing(of: ws.lockURL, staleAfter: staleAfter) {
            case .held(let holder):
                throw WorkspaceError.locked(host: holder.host, pid: holder.pid, since: holder.since)
            case .stale:
                try? FileManager.default.removeItem(at: ws.lockURL)
                continue
            }
        }
        throw WorkspaceError.locked(host: "?", pid: 0, since: Date())
    }

    /// Quién tiene el bloqueo del espacio, si sigue valiendo: con las mismas reglas que `acquire` (un bloqueo viejo, el
    /// de un proceso muerto de este Mac o uno ilegible y viejo no cuentan). Solo lee: no toma, no escribe ni retira
    /// nada, así que mirarlo nunca se lo quita a quien lo tiene. `nil`: no hay bloqueo, o el que hay ya no vale.
    public static func holder(of ws: Workspace, staleAfter: TimeInterval = 43_200) -> Holder? {
        guard case .held(let holder) = standing(of: ws.lockURL, staleAfter: staleAfter) else { return nil }
        return holder
    }

    /// Las reglas del bloqueo, para `acquire` y `holder(of:)`. Solo lee el fichero.
    private static func standing(of url: URL, staleAfter: TimeInterval) -> Standing {
        let existing = FileManager.default.contents(atPath: url.path)
            .flatMap { try? decoder.decode(Info.self, from: $0) }
        guard let existing else {
            // Ilegible: puede ser de otro proceso que aún no lo ha escrito. Solo deja de valer si es viejo.
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate]
                as? Date ?? .distantPast
            return Date().timeIntervalSince(modified) < 10 ? .held(Holder(host: "?", pid: 0, since: modified)) : .stale
        }
        let sameHost = existing.host == thisHost
        let deadProcess = sameHost && kill(existing.pid, 0) != 0 && errno == ESRCH
        let tooOld = Date().timeIntervalSince(existing.since) > staleAfter
        if deadProcess || tooOld { return .stale }
        return .held(Holder(host: existing.host, pid: existing.pid, since: existing.since))
    }

    /// El nombre de este Mac, de `gethostname()`. `ProcessInfo.hostName` no sirve: depende de la red y, en una app con
    /// sandbox sin permiso de red, da «localhos»; el bloqueo de un proceso muerto de este Mac parecería de otro.
    static var thisHost: String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0 else { return ProcessInfo.processInfo.hostName }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public func release() {
        guard !released else { return }
        released = true
        try? FileManager.default.removeItem(at: url)
    }

    deinit { release() }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
