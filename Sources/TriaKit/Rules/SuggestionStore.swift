import Foundation

public struct RuleSuggestion: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var section: String
    public var rule: String
    /// Qué corrección la originó (p. ej. "scan.pdf: 7-Facturas/Recibidas → 2-Contratos/Renting").
    public var context: String
    /// El nombre original del documento corregido (spec de Reglas, §4.4). `nil` en las de antes de guardarlo.
    public var document: String?
    /// La carpeta que proponía Tria.
    public var fromFolder: String?
    /// La carpeta que eligió el usuario.
    public var toFolder: String?

    public init(draft: RuleSuggestionDraft, context: String, document: String? = nil, fromFolder: String? = nil,
                toFolder: String? = nil, now: Date = Date()) {
        id = "sg_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        createdAt = now
        section = draft.section
        rule = draft.rule
        self.context = context
        self.document = document
        self.fromFolder = fromFolder
        self.toFolder = toFolder
    }
}

/// Sugerencias pendientes en `.tria/suggestions.jsonl` (spec §7.3).
public struct SuggestionStore: Sendable {
    public let url: URL

    public init(workspace: Workspace) { url = workspace.suggestionsURL }

    public func list() throws -> [RuleSuggestion] {
        guard let data = FileManager.default.contents(atPath: url.path) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? Self.decoder.decode(RuleSuggestion.self, from: Data($0)) }
    }

    public func add(_ suggestion: RuleSuggestion) throws {
        try write(try list() + [suggestion])
    }

    public func remove(id: String) throws {
        try write(try list().filter { $0.id != id })
    }

    private func write(_ suggestions: [RuleSuggestion]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        for suggestion in suggestions {
            data.append(try Self.encoder.encode(suggestion))
            data.append(0x0A)
        }
        try data.write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension Workspace {
    /// Añade la regla a `TRIA.md` (solo si el resultado sigue siendo válido) y devuelve el espacio recargado. Se añade
    /// sobre lo que haya en el disco, no sobre lo que se leyó al abrir: un cambio hecho fuera se conserva (spec de
    /// Reglas, §6.2). La viñeta va a su sección como la ve el editor (`RulesPatcher`, con `RulesDocument`): fuera de los
    /// bloques de código y con los saltos de línea del fichero. No toma el cerrojo: `sort` la llama con el suyo tomado.
    public func applySuggestion(_ suggestion: RuleSuggestion) throws -> Workspace {
        let current = try reloaded()
        let patched = RulesPatcher.insert(rule: suggestion.rule, section: suggestion.section, into: current.rules.raw)
        do { _ = try RulesFile.parse(patched) } catch let error as RulesError { throw WorkspaceError.rules(error) }
        try Data(patched.utf8).write(to: rulesURL, options: .atomic)
        return try current.reloaded()
    }
}
