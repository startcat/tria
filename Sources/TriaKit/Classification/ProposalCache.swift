import Foundation

public struct CacheEntry: Codable, Sendable, Equatable {
    public var key: String
    public var sha256: String
    /// Las reglas con las que se leyó (`Workspace.contextHash`). `nil` en las entradas de antes de guardarlo.
    public var rulesHash: String?
    public var fileName: String
    public var outcome: ClassificationOutcome
    public var method: ExtractionMethod?
    public var usage: TokenUsage
    public var provider: String
    public var model: String
    public var createdAt: Date

    /// `rulesHash` es obligatorio: una entrada nueva sin él nunca valdría para otro modelo. `nil` solo para simular las
    /// de antes.
    public init(key: String, sha256: String, rulesHash: String?, fileName: String, outcome: ClassificationOutcome,
                method: ExtractionMethod?, usage: TokenUsage, provider: String, model: String, createdAt: Date) {
        self.key = key
        self.sha256 = sha256
        self.rulesHash = rulesHash
        self.fileName = fileName
        self.outcome = outcome
        self.method = method
        self.usage = usage
        self.provider = provider
        self.model = model
        self.createdAt = createdAt
    }
}

/// Propuestas en `.tria/cache/<sha256>_<clave>.json`. Repetir una ejecución no gasta tokens. La clave cambia con las
/// reglas, el proveedor o el modelo (spec §6.4), pero lo leído con otro proveedor o modelo se reutiliza mientras no
/// cambien las reglas (`reusable`).
public struct ProposalCache: Sendable {
    public let directory: URL

    public init(workspace: Workspace) { self.init(directory: workspace.cacheURL) }
    public init(directory: URL) { self.directory = directory }

    public static func key(sha256: String, rulesHash: String, provider: ProviderID, model: String) -> String {
        Hashing.sha256("\(sha256)|\(rulesHash)|\(provider.rawValue)|\(model)")
    }

    public func load(sha256: String, key: String) -> CacheEntry? {
        decode(directory.appendingPathComponent("\(sha256)_\(key).json"))
    }

    public func save(_ entry: CacheEntry) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(entry).write(to: directory.appendingPathComponent("\(entry.sha256)_\(entry.key).json"),
                                             options: .atomic)
    }

    /// Solo para las pruebas: se llama cada vez que se lista la carpeta de la caché.
    @TaskLocal static var onListing: (@Sendable () -> Void)?

    /// Los ficheros de la caché agrupados por documento (`sha256`), de una sola mirada a la carpeta. Quien busca muchos
    /// documentos a la vez (`SortPipeline.status`, `plan`) lo hace una vez y lo pasa a `reusable`: así no lista la
    /// carpeta por cada documento. Lo que se guarde después no está en él, pero va a la clave exacta, que se lee del disco.
    public struct Index: Sendable {
        fileprivate let files: [String: [String]]
    }

    public func index() -> Index {
        Self.onListing?()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var files: [String: [String]] = [:]
        for name in names where name.hasSuffix(".json") {
            guard let separator = name.firstIndex(of: "_") else { continue }
            files[String(name[..<separator]), default: []].append(name)
        }
        return Index(files: files)
    }

    /// La entrada con la que leer `sha256` sin preguntar a la IA: la primera que se reutilizaría.
    /// 1. La de su clave, si es una lectura buena: ni un fallo ni una negativa del modelo
    ///    (`PendingReason.readsAgain(fromAnotherModel: true)`).
    /// 2. Si no, la más reciente leída con las mismas reglas (`rulesHash`) por otro proveedor o modelo, saltando las que
    ///    se vuelven a leer: ni un fallo ni la negativa del propio modelo tapan una lectura buena.
    /// 3. Si no hay ninguna, la de su clave tal cual: así se ve en qué quedó (la app ofrece «Reintentar») y la negativa
    ///    del propio modelo se respeta, sin volver a pedirla.
    ///
    /// Una entrada sin `rulesHash` (de antes) solo vale por su clave: no se sabe con qué reglas se leyó. Si al final se
    /// reutiliza (el destino puede haber dejado de valer) lo decide quien la pide. Sin `index`, lista la carpeta.
    public func reusable(sha256: String, rulesHash: String, provider: ProviderID, model: String,
                         in index: Index? = nil) -> CacheEntry? {
        let key = Self.key(sha256: sha256, rulesHash: rulesHash, provider: provider, model: model)
        let exact = load(sha256: sha256, key: key)
        if let exact, !exact.readsAgain(fromAnotherModel: true) { return exact }
        let other = entries(sha256: sha256, in: index ?? self.index())
            .filter { $0.key != key && $0.rulesHash == rulesHash && !$0.readsAgain(fromAnotherModel: true) }
            .max { $0.createdAt < $1.createdAt }
        return other ?? exact
    }

    /// La última entrada guardada del documento, de cualquier regla, proveedor o modelo. Sin `index`, lista la carpeta.
    public func latest(sha256: String, in index: Index? = nil) -> CacheEntry? {
        entries(sha256: sha256, in: index ?? self.index()).max { $0.createdAt < $1.createdAt }
    }

    /// Todas las entradas de un documento que hay en el índice. Solo abre los ficheros de ese documento.
    private func entries(sha256: String, in index: Index) -> [CacheEntry] {
        (index.files[sha256] ?? []).compactMap { decode(directory.appendingPathComponent($0)) }
    }

    private func decode(_ url: URL) -> CacheEntry? {
        FileManager.default.contents(atPath: url.path).flatMap { try? Self.decoder.decode(CacheEntry.self, from: $0) }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension PendingReason {
    /// Si una lectura que acabó así se vuelve a hacer en vez de reutilizarse de la caché:
    /// - sin conexión, en pausa o rechazada por el proveedor, siempre, con el proveedor y el modelo de ahora;
    /// - si el modelo se negó a clasificarlo (`.refused`), solo cuando fue otro proveedor o modelo: el actual lo intenta
    ///   una vez, y su propia negativa se respeta (no se vuelve a pedir en cada lectura).
    public func readsAgain(fromAnotherModel: Bool) -> Bool {
        switch self {
        case .offline, .paused, .providerError, .held: return true
        case .refused: return fromAnotherModel
        default: return false
        }
    }
}

extension CacheEntry {
    /// Como `PendingReason.readsAgain(fromAnotherModel:)`; una propuesta nunca se vuelve a leer por sí misma.
    func readsAgain(fromAnotherModel: Bool) -> Bool {
        guard case .pending(_, let reason) = outcome else { return false }
        return reason.readsAgain(fromAnotherModel: fromAnotherModel)
    }
}
