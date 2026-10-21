import Foundation

public struct JournalEvent: Codable, Sendable, Equatable {
    public enum Op: String, Codable, Sendable { case move, trash }
    public enum State: String, Codable, Sendable { case intent, done, failed, undone }

    public var id: String
    public var batch: String
    public var op: Op
    public var state: State
    public var from: String
    public var to: String
    public var sha256: String?
    public var confidence: Confidence?
    public var reason: String?
    public var provider: String?
    public var model: String?
    public var error: String?
    /// `true` si el usuario cambió la carpeta o el nombre propuestos antes de archivar; si no, no se escribe (spec de
    /// la app, §9, pieza 5). Las líneas sin este campo, como las de antes, cuentan como archivadas tal cual.
    public var corrected: Bool?
    /// Los tokens que costó leer el documento, si llegó al proveedor. Si no se sabe, no se escribe.
    public var usage: TokenUsage?
    public var ts: Date

    public init(id: String, batch: String, op: Op, state: State, from: String, to: String,
                sha256: String? = nil, confidence: Confidence? = nil, reason: String? = nil,
                provider: String? = nil, model: String? = nil, error: String? = nil,
                corrected: Bool? = nil, usage: TokenUsage? = nil, ts: Date = Date()) {
        self.id = id
        self.batch = batch
        self.op = op
        self.state = state
        self.from = from
        self.to = to
        self.sha256 = sha256
        self.confidence = confidence
        self.reason = reason
        self.provider = provider
        self.model = model
        self.error = error
        // `false` no se escribe: una línea sin corrección es igual que las de antes.
        self.corrected = corrected == true ? true : nil
        self.usage = usage
        self.ts = ts
    }
}

public struct JournalOperation: Sendable, Equatable {
    public var id: String
    public var batch: String
    public var op: JournalEvent.Op
    public var state: JournalEvent.State
    public var from: String
    public var to: String
    public var sha256: String?
    public var reason: String?
    public var confidence: Confidence?
    public var restoredTo: String?
    public var error: String?
    public var startedAt: Date
    public var updatedAt: Date
    /// El usuario cambió la propuesta antes de archivar. `false` si el registro no lo dice, como en los de antes.
    public var corrected: Bool = false
    /// Lo que costó leer el documento, si se sabe.
    public var usage: TokenUsage? = nil
    /// El modelo que leyó el documento, si lo leyó la IA.
    public var model: String? = nil
}

public struct BatchSummary: Sendable, Equatable {
    public var id: String
    public var startedAt: Date
    public var done: Int
    public var failed: Int
    public var undone: Int
    public var interrupted: Int
}

public struct ReconcileResult: Sendable, Equatable {
    public var id: String
    public var state: JournalEvent.State
}

/// Registro append-only `.tria/journal.jsonl` (spec §6.7). Una línea JSON por evento.
public struct Journal: Sendable {
    public let url: URL
    public let root: URL

    public init(workspace: Workspace) { self.init(url: workspace.journalURL, root: workspace.root) }

    public init(url: URL, root: URL) {
        self.url = url
        self.root = root
    }

    public static func newBatchID(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "b_\(formatter.string(from: now))_\(UUID().uuidString.prefix(4).lowercased())"
    }

    public static func newOperationID() -> String {
        "op_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    }

    public func absoluteURL(_ path: String) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
    }

    public func append(_ event: JournalEvent) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        var line = try Self.encoder.encode(event)
        line.append(0x0A)
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        // Si un cierre inesperado dejó la última línea a medias, se empieza en una línea nueva para no perder este evento.
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data([0x0A]) { line.insert(0x0A, at: 0) }
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: line)
    }

    public func events() throws -> [JournalEvent] {
        guard let data = FileManager.default.contents(atPath: url.path) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? Self.decoder.decode(JournalEvent.self, from: Data($0)) }
    }

    public func operations() throws -> [JournalOperation] {
        var order: [String] = []
        var byID: [String: JournalOperation] = [:]
        for event in try events() {
            guard var operation = byID[event.id] else {
                order.append(event.id)
                byID[event.id] = JournalOperation(
                    id: event.id, batch: event.batch, op: event.op, state: event.state, from: event.from,
                    to: event.to, sha256: event.sha256, reason: event.reason, confidence: event.confidence,
                    restoredTo: nil, error: event.error, startedAt: event.ts, updatedAt: event.ts,
                    corrected: event.corrected ?? false, usage: event.usage, model: event.model)
                continue
            }
            operation.state = event.state
            operation.updatedAt = event.ts
            if event.state == .undone {
                operation.restoredTo = event.to
            } else {
                if !event.to.isEmpty { operation.to = event.to }
                operation.error = event.error ?? operation.error
            }
            byID[event.id] = operation
        }
        return order.compactMap { byID[$0] }
    }

    public func batches() throws -> [BatchSummary] {
        var summaries: [String: BatchSummary] = [:]
        for operation in try operations() {
            var summary = summaries[operation.batch] ?? BatchSummary(
                id: operation.batch, startedAt: operation.startedAt, done: 0, failed: 0, undone: 0, interrupted: 0)
            summary.startedAt = min(summary.startedAt, operation.startedAt)
            switch operation.state {
            case .done: summary.done += 1
            case .failed: summary.failed += 1
            case .undone: summary.undone += 1
            case .intent: summary.interrupted += 1
            }
            summaries[operation.batch] = summary
        }
        return summaries.values.sorted { $0.startedAt > $1.startedAt }
    }

    /// Cierra las operaciones que quedaron en `intent` por un cierre inesperado.
    public func reconcile() throws -> [ReconcileResult] {
        var results: [ReconcileResult] = []
        for operation in try operations() where operation.state == .intent {
            let fm = FileManager.default
            let target = operation.to.isEmpty ? nil : absoluteURL(operation.to)
            let arrived = target.map { url in
                fm.fileExists(atPath: url.path)
                    && (operation.sha256 == nil || (try? Hashing.sha256(of: url)) == operation.sha256)
            } ?? false
            let state: JournalEvent.State = arrived ? .done : .failed
            let error: String? = arrived ? nil
                : (fm.fileExists(atPath: absoluteURL(operation.from).path) ? "interrupted" : "not found")
            try append(JournalEvent(id: operation.id, batch: operation.batch, op: operation.op, state: state,
                                    from: operation.from, to: arrived ? operation.to : "", error: error))
            results.append(ReconcileResult(id: operation.id, state: state))
        }
        return results
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
