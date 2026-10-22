import Foundation

public struct SortItem: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case proposal(Proposal, FilingAction)
        case duplicate(original: String, FilingAction)
        case pending(Proposal?, PendingReason)
    }

    public var file: URL
    public var relativePath: String
    public var sha256: String
    public var kind: Kind
    public var method: ExtractionMethod?
    /// El usuario ya deshizo este mismo fichero (mismo hash): el modo automático no lo vuelve a aplicar.
    public var undoneBefore = false
    /// Lo que costó leer el documento: ahora o, si la propuesta sale de la caché, cuando se leyó. `nil` si no llegó al
    /// proveedor (pendiente por extracción, cifrado, ilegible, repetido o pausado).
    public var readUsage: TokenUsage? = nil
    /// La propuesta sale de la caché: esta lectura no ha gastado nada en él.
    public var fromCache: Bool = false
    /// Quién leyó el documento: el proveedor (`ProviderID.rawValue`) y el modelo de esta lectura, o `nil` si en ella no
    /// llegó al proveedor. Si sale de la caché, los de su entrada, que pueden ser otros que los de ahora; también en un
    /// pendiente que nunca llegó a la IA (cifrado, sin texto): son los de la lectura que lo guardó. Es lo que se anota
    /// en el registro al archivarlo.
    public var readProvider: String? = nil
    public var readModel: String? = nil
    public var id: String { relativePath }
}

public struct SortPlan: Sendable, Equatable {
    public var items: [SortItem]
    public var inUse: [URL]
    public var ignoredFolders: [URL]
    public var usage: TokenUsage
    public var provider: ProviderID
    public var model: String
    /// Por qué se paró el lote antes de acabar: un fallo pasajero o un límite de la IA de Tria. Lo que quedó sin leer
    /// está pendiente (`.offline`, `.paused`) y no se guardó en la caché; lo leído antes, y lo que estaba en vuelo, sí.
    public var interruption: LLMError?
    public var reconciled: [ReconcileResult]
    public var cost: Double? { Pricing.cost(usage, model: model) }
    /// Documentos enviados al proveedor en esta lectura (no cuenta los de la caché).
    public var sentDocuments: Int { items.filter { !$0.fromCache && $0.readUsage != nil }.count }
    /// Documentos que `admit` ha dejado en espera: no se han enviado al proveedor.
    public var heldDocuments: Int {
        items.filter { if case .pending(_, .held) = $0.kind { return true } else { return false } }.count
    }
}

public enum SortProgress: Sendable, Equatable {
    case started(total: Int)
    case document(done: Int, total: Int, name: String)
}

public struct StatusItem: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case unprocessed
        case inUse
        case duplicate(original: String)
        case proposed(Proposal, destination: String)
        case pending(Proposal?, PendingReason)
    }

    public var file: URL
    public var relativePath: String
    public var state: State
    /// El hash con el que se ha buscado la propuesta (el de `DuplicateFinder`). `nil` si está en uso o no se ha
    /// podido leer. Quien archive desde aquí debe usar este hash, no calcularlo otra vez: si el fichero cambia
    /// después, el Executor lo deja en la bandeja.
    public var sha256: String? = nil
    /// El usuario ya deshizo este mismo fichero (mismo hash), como `SortItem.undoneBefore`.
    public var undoneBefore = false
    /// Lo que costó leer el documento, de la entrada de la caché de su propuesta. `nil` si no hay propuesta en caché.
    public var readUsage: TokenUsage? = nil
    /// Quién lo leyó y cuándo: el proveedor, el modelo y la fecha de esa misma entrada, como `SortItem.readProvider`.
    public var readProvider: String? = nil
    public var readModel: String? = nil
    public var readAt: Date? = nil
}

private actor StopSignal {
    private(set) var error: LLMError?
    func set(_ error: LLMError) { if self.error == nil { self.error = error } }
}

/// Orquesta un lote: duplicados → extracción → clasificación (en paralelo) → plan. Aplicar es aparte (spec §6.3).
public struct SortPipeline: Sendable {
    public let workspace: Workspace
    public let provider: any LLMProvider
    public let extractor: DocumentExtractor
    public let concurrency: Int
    public let useCache: Bool
    public let onRequest: (@Sendable (LLMRequest) -> Void)?
    /// Se pregunta por la huella (sha256) de cada documento justo antes de enviarlo al proveedor; si devuelve `false`,
    /// queda en espera (`.held`). No se pregunta por duplicados, ilegibles, sin texto ni los que salen de la caché.
    public let admit: (@Sendable (_ sha256: String) async -> Bool)?

    public init(workspace: Workspace, provider: any LLMProvider, extractor: DocumentExtractor = DocumentExtractor(),
                concurrency: Int = 4, useCache: Bool = true, onRequest: (@Sendable (LLMRequest) -> Void)? = nil,
                admit: (@Sendable (_ sha256: String) async -> Bool)? = nil) {
        self.workspace = workspace
        self.provider = provider
        self.extractor = extractor
        self.concurrency = max(1, concurrency)
        self.useCache = useCache
        self.onRequest = onRequest
        self.admit = admit
    }

    public func plan(progress: (@Sendable (SortProgress) -> Void)? = nil) async throws -> SortPlan {
        let reconciled = try Journal(workspace: workspace).reconcile()
        let listing = try workspace.inboxFiles()
        let files = listing.ready
        let duplicates = try DuplicateFinder(workspace: workspace).scan(files)
        let classifier = Classifier(provider: provider, workspace: workspace, tree: try workspace.folderTree(),
                                    onRequest: onRequest)
        // Una sola mirada a la carpeta de la caché para todo el lote. Lo que se guarde mientras va a su clave exacta,
        // que se lee del disco.
        let cacheIndex = useCache && !files.isEmpty ? ProposalCache(workspace: workspace).index() : nil
        let stop = StopSignal()
        progress?(.started(total: files.count))

        var results: [Int: (SortItem, TokenUsage)] = [:]
        try await withThrowingTaskGroup(of: (Int, SortItem, TokenUsage).self) { group in
            var next = 0
            func enqueue(_ index: Int) {
                let url = files[index]
                group.addTask {
                    let (item, usage) = try await process(url, sha: duplicates.hashes[url] ?? "",
                                                          original: duplicates.originals[url],
                                                          unreadable: duplicates.unreadable[url],
                                                          classifier: classifier, cacheIndex: cacheIndex, stop: stop)
                    return (index, item, usage)
                }
            }
            // La caché de prompts del proveedor: la primera llamada escribe el prefijo común (reglas y perfil) y las
            // siguientes lo leen, que cuesta una décima. Si arrancan todas a la vez, todas lo escriben. Por eso, hasta
            // que acabe la primera lectura que llama de verdad al modelo (`usage` distinto de cero) va una sola en
            // vuelo; las que salen de la caché local, los duplicados y los ilegibles no calientan nada y no esperan.
            var inFlight = 0
            var warm = concurrency == 1
            func fill() {
                while next < files.count, inFlight < (warm ? concurrency : 1) {
                    enqueue(next)
                    next += 1
                    inFlight += 1
                }
            }
            fill()
            while let (index, item, usage) = try await group.next() {
                inFlight -= 1
                if usage != .zero { warm = true }
                results[index] = (item, usage)
                progress?(.document(done: results.count, total: files.count, name: item.file.lastPathComponent))
                fill()
            }
        }

        var items = files.indices.compactMap { results[$0]?.0 }
        let undone = try Self.undoneHashes(workspace)
        for index in items.indices where !items[index].sha256.isEmpty && undone.contains(items[index].sha256) {
            items[index].undoneBefore = true
        }
        reserveDestinations(&items)
        return SortPlan(items: items, inUse: listing.inUse, ignoredFolders: listing.ignoredFolders,
                        usage: results.values.map { $0.1 }.reduce(.zero, +), provider: provider.id,
                        model: provider.model, interruption: await stop.error, reconciled: reconciled)
    }

    public func apply(_ items: [ApprovedItem], batch: String = Journal.newBatchID()) -> ApplyReport {
        Executor(workspace: workspace).apply(items, batch: batch)
    }

    /// Lo que se aplica de un documento tal como se propuso. El registro anota el proveedor y el modelo que lo leyeron,
    /// no los que estén puestos ahora.
    public static func approvedItem(for item: SortItem) -> ApprovedItem? {
        switch item.kind {
        case .proposal(let proposal, let action):
            return ApprovedItem(action: action, sha256: item.sha256, confidence: proposal.confidence,
                                reason: proposal.reason, provider: item.readProvider, model: item.readModel,
                                usage: item.readUsage)
        case .duplicate(let original, let action):
            return ApprovedItem(action: action, sha256: item.sha256, reason: "duplicate of \(original)")
        case .pending:
            return nil
        }
    }

    /// Modo automático: solo confianza alta y duplicados exactos (spec §6.6).
    public static func automaticItems(_ plan: SortPlan) -> [ApprovedItem] {
        plan.items.compactMap { item in
            guard !item.undoneBefore else { return nil }
            switch item.kind {
            case .proposal(let proposal, _) where proposal.confidence == .high:
                return approvedItem(for: item)
            case .duplicate:
                return approvedItem(for: item)
            default:
                return nil
            }
        }
    }

    /// Estado de la bandeja sin llamar a la IA: usa la caché y los duplicados.
    public static func status(workspace: Workspace, now: Date = Date(), provider: ProviderID? = nil,
                              model: String? = nil) throws -> [StatusItem] {
        let listing = try workspace.inboxFiles(now: now)
        let duplicates = try DuplicateFinder(workspace: workspace).scan(listing.ready)
        let undone = try undoneHashes(workspace)
        let cache = ProposalCache(workspace: workspace)
        // Una sola mirada a la carpeta de la caché para toda la bandeja, no una por documento.
        let cacheIndex = listing.ready.isEmpty ? nil : cache.index()
        var items = listing.inUse.map {
            StatusItem(file: $0, relativePath: workspace.relativePath(of: $0) ?? $0.lastPathComponent, state: .inUse)
        }
        for url in listing.ready {
            let relative = workspace.relativePath(of: url) ?? url.lastPathComponent
            let state: StatusItem.State
            var read: CacheEntry?
            if let original = duplicates.originals[url] {
                state = .duplicate(original: original)
            } else if let sha = duplicates.hashes[url],
                      let entry = cachedEntry(cache, index: cacheIndex, sha: sha, workspace: workspace,
                                              provider: provider, model: model) {
                switch entry.outcome {
                case .proposed(let proposal, _):
                    // Se revalida como hará sort: el destino puede haber cambiado o dejado de ser válido.
                    let validation = Validator(workspace: workspace).validate(proposal, originalFilename: url.lastPathComponent)
                    if case .success(let destination) = validation {
                        state = .proposed(proposal, destination: destination)
                        read = entry
                    } else {
                        state = .unprocessed
                    }
                case .pending(let proposal, let reason):
                    state = .pending(proposal, reason)
                    read = entry
                }
            } else {
                state = .unprocessed
            }
            let sha = duplicates.hashes[url]
            items.append(StatusItem(file: url, relativePath: relative, state: state, sha256: sha,
                                    undoneBefore: sha.map(undone.contains) ?? false, readUsage: read?.usage,
                                    readProvider: read?.provider, readModel: read?.model, readAt: read?.createdAt))
        }
        return items
    }

    /// Hashes de lo que el usuario ha deshecho: el modo automático no lo vuelve a aplicar (spec §6.6).
    private static func undoneHashes(_ workspace: Workspace) throws -> Set<String> {
        Set(try Journal(workspace: workspace).operations().filter { $0.state == .undone }.compactMap(\.sha256))
    }

    /// Con proveedor y modelo, la entrada que sort tendría en cuenta (`ProposalCache.reusable`); sin ellos, la última
    /// guardada. La de su misma clave se enseña aunque sort la vaya a leer otra vez (un rechazo del proveedor: la app
    /// ofrece «Reintentar»). De otro proveedor o modelo solo llega lo que sort reutilizaría.
    private static func cachedEntry(_ cache: ProposalCache, index: ProposalCache.Index?, sha: String,
                                    workspace: Workspace, provider: ProviderID?, model: String?) -> CacheEntry? {
        guard let provider, let model else { return cache.latest(sha256: sha, in: index) }
        return cache.reusable(sha256: sha, rulesHash: workspace.contextHash, provider: provider, model: model, in: index)
    }

    // MARK: - Privado

    private func process(_ url: URL, sha: String, original: String?, unreadable: String?, classifier: Classifier,
                         cacheIndex: ProposalCache.Index?, stop: StopSignal) async throws -> (SortItem, TokenUsage) {
        let relative = workspace.relativePath(of: url) ?? url.lastPathComponent
        let validator = Validator(workspace: workspace)
        func item(_ kind: SortItem.Kind, _ method: ExtractionMethod? = nil, readUsage: TokenUsage? = nil,
                  fromCache: Bool = false, readProvider: String? = nil, readModel: String? = nil) -> SortItem {
            SortItem(file: url, relativePath: relative, sha256: sha, kind: kind, method: method, readUsage: readUsage,
                     fromCache: fromCache, readProvider: readProvider, readModel: readModel)
        }

        if let unreadable { return (item(.pending(nil, .unreadable(unreadable))), .zero) }

        if let original {
            let destination = validator.duplicateDestination(originalFilename: url.lastPathComponent)
            return (item(.duplicate(original: original, FilingAction(kind: .duplicate, source: relative,
                                                                     destination: destination))), .zero)
        }

        let cache = ProposalCache(workspace: workspace)
        let rulesHash = workspace.contextHash
        let key = ProposalCache.key(sha256: sha, rulesHash: rulesHash, provider: provider.id, model: provider.model)
        // Lo leído con otro proveedor o modelo también vale, si las reglas son las mismas (`ProposalCache.reusable`).
        if useCache,
           let entry = cache.reusable(sha256: sha, rulesHash: rulesHash, provider: provider.id, model: provider.model,
                                      in: cacheIndex),
           let kind = reuse(entry.outcome, fromAnotherModel: entry.key != key, url: url, relative: relative,
                            validator: validator) {
            // Sale de la caché: ahora no gasta nada, pero lleva lo que costó leerlo entonces y quién lo leyó, para el
            // registro.
            return (item(kind, entry.method, readUsage: entry.usage, fromCache: true, readProvider: entry.provider,
                         readModel: entry.model), .zero)
        }

        if let error = await stop.error { return (item(.pending(nil, Self.pendingReason(for: error))), .zero) }

        func remember(_ outcome: ClassificationOutcome, _ method: ExtractionMethod?, _ usage: TokenUsage) {
            try? cache.save(CacheEntry(key: key, sha256: sha, rulesHash: rulesHash, fileName: url.lastPathComponent,
                                       outcome: outcome, method: method, usage: usage, provider: provider.id.rawValue,
                                       model: provider.model, createdAt: Date()))
        }

        let extracted: ExtractedDocument
        do {
            extracted = try extractor.extract(url)
        } catch let error as ExtractionError {
            let reason: PendingReason
            switch error {
            case .unsupportedFormat(let ext): reason = .unsupported(ext)
            case .encrypted: reason = .encrypted
            case .unreadable(let detail): reason = .unreadable(detail)
            }
            remember(.pending(nil, reason), nil, .zero)
            return (item(.pending(nil, reason)), .zero)
        } catch {
            // Cualquier otro fallo al leer (permisos, E/S, Vision) deja este documento pendiente; el lote sigue.
            return (item(.pending(nil, .unreadable(error.localizedDescription))), .zero)
        }

        // Si no hay nada que leer, no se clasifica: nunca se decide por el nombre (spec §3, principio 1).
        guard extracted.hasReadableContent else {
            remember(.pending(nil, .unreadable("no text")), extracted.method, .zero)
            return (item(.pending(nil, .unreadable("no text")), extracted.method), .zero)
        }

        // En espera: ni se envía ni se recuerda, para que la próxima lectura lo envíe de verdad.
        if let admit, !(await admit(sha)) { return (item(.pending(nil, .held), extracted.method), .zero) }

        // Si el lote se paró mientras se extraía el texto o se preguntaba a `admit`, este ya no se envía.
        if let error = await stop.error {
            return (item(.pending(nil, Self.pendingReason(for: error)), extracted.method), .zero)
        }

        do {
            let (outcome, usage) = try await classifier.classify(DocumentContext.from(url: url, extracted: extracted))
            remember(outcome, extracted.method, usage)
            return (item(kind(for: outcome, relative: relative), extracted.method, readUsage: usage,
                         readProvider: provider.id.rawValue, readModel: provider.model), usage)
        } catch let error as LLMError where Self.stopsTheBatch(error) {
            // Ni se guarda en la caché: la próxima lectura lo envía otra vez.
            await stop.set(error)
            return (item(.pending(nil, Self.pendingReason(for: error)), extracted.method), .zero)
        }
    }

    /// Lo que para el lote sin tirar lo leído: un fallo pasajero (spec §10) o un límite del servicio de la IA de Tria
    /// (sin saldo, el límite del día, la prueba acabada). Las lecturas en vuelo acaban y se guardan, no empieza ninguna
    /// más y `SortPlan.interruption` dice por qué. Un límite llega en milisegundos y las lecturas buenas tardan segundos:
    /// si cortara el lote, cancelaría lecturas que el servidor ya había admitido y cobrado. Los demás fatales (la clave,
    /// la cuota) sí cortan el lote: son de la cuenta, y las lecturas en vuelo fallarían igual.
    private static func stopsTheBatch(_ error: LLMError) -> Bool {
        if case .serviceLimit = error { return true }
        return error.isTransient
    }

    private func reuse(_ outcome: ClassificationOutcome, fromAnotherModel: Bool, url: URL, relative: String,
                       validator: Validator) -> SortItem.Kind? {
        switch outcome {
        case .proposed(let proposal, _):
            guard case .success(let destination) = validator.validate(proposal, originalFilename: url.lastPathComponent)
            else { return nil }
            return .proposal(proposal, FilingAction(kind: .file, source: relative, destination: destination))
        case .pending(_, let reason) where reason.readsAgain(fromAnotherModel: fromAnotherModel):
            return nil
        case .pending(let proposal, let reason):
            return .pending(proposal, reason)
        }
    }

    private func kind(for outcome: ClassificationOutcome, relative: String) -> SortItem.Kind {
        switch outcome {
        case .proposed(let proposal, let destination):
            return .proposal(proposal, FilingAction(kind: .file, source: relative, destination: destination))
        case .pending(let proposal, let reason):
            return .pending(proposal, reason)
        }
    }

    private static func pendingReason(for error: LLMError) -> PendingReason {
        switch error {
        case .offline: return .offline
        case .rateLimited: return .paused("rate limited")
        case .unavailable(let message): return .paused(message)
        case .serviceLimit(let code): return .paused(code)
        default: return .paused(String(describing: error))
        }
    }

    /// Dos documentos del lote no pueden compartir destino en la vista previa (el Executor lo vuelve a comprobar).
    private func reserveDestinations(_ items: inout [SortItem]) {
        var reserved = Set<String>()
        for index in items.indices {
            switch items[index].kind {
            case .proposal(let proposal, var action):
                action.destination = Collision.uniqueRelativePath(action.destination, root: workspace.root, reserved: reserved)
                reserved.insert(action.destination)
                items[index].kind = .proposal(proposal, action)
            case .duplicate(let original, var action):
                action.destination = Collision.uniqueRelativePath(action.destination, root: workspace.root, reserved: reserved)
                reserved.insert(action.destination)
                items[index].kind = .duplicate(original: original, action)
            case .pending:
                break
            }
        }
    }
}
