import Foundation

/// Las piezas de una petición a la IA. Con la IA de Tria la app envía estas piezas al servidor y no un prompt; el
/// servidor monta la petición idéntica con este mismo código. `makeRequest()` es lo único que arma el texto: lo usan
/// `PromptBuilder`, `RulesAsker` y `RulesLearner` al enviar con clave propia, y `tria-api`.
public enum TriaRequestParts: Codable, Sendable, Equatable {
    case proposal(ProposalParts)
    case rulesChange(RulesChangeParts)
    case ruleSuggestion(SuggestionParts)

    /// La petición exacta de siempre, con `parts` puesto. Lanza si `TRIA.md` no se puede leer.
    public func makeRequest() throws -> LLMRequest {
        switch self {
        case .proposal(let parts): return parts.request(header: try RulesFile.parse(parts.rules).header, parts: self)
        case .rulesChange(let parts): return parts.request(header: try RulesFile.parse(parts.rules).header, parts: self)
        case .ruleSuggestion(let parts): return parts.request(parts: self)
        }
    }

    /// Lo mismo cuando `rules` ya está leído (`rules.raw` son las piezas): así quien construye la petición no relee.
    package func makeRequest(rules: RulesFile) -> LLMRequest {
        switch self {
        case .proposal(let parts): return parts.request(header: rules.header, parts: self)
        case .rulesChange(let parts): return parts.request(header: rules.header, parts: self)
        case .ruleSuggestion(let parts): return parts.request(parts: self)
        }
    }
}

/// Clasificar un documento (`PromptBuilder`).
public struct ProposalParts: Codable, Sendable, Equatable {
    /// `TRIA.md` tal cual.
    public var rules: String
    public var tree: String
    /// `PERFIL.md` tal cual.
    public var profile: String?
    public var originalFilename: String
    public var created: Date?
    public var modified: Date?
    public var text: String
    public var pageCount: Int?
    public var method: ExtractionMethod
    /// JPEG de las páginas.
    public var images: [Data]
    /// Por qué se rechazó la respuesta anterior: solo en el segundo intento.
    public var feedback: String?
    /// La zona horaria del cliente (`TimeZone.current.identifier`): las fechas del fichero se escriben en ella.
    public var timeZone: String

    public init(rules: String, tree: String, profile: String?, originalFilename: String, created: Date?, modified: Date?,
                text: String, pageCount: Int?, method: ExtractionMethod, images: [Data], feedback: String?,
                timeZone: String = TimeZone.current.identifier) {
        self.rules = rules
        self.tree = tree
        self.profile = profile
        self.originalFilename = originalFilename
        self.created = created
        self.modified = modified
        self.text = text
        self.pageCount = pageCount
        self.method = method
        self.images = images
        self.feedback = feedback
        self.timeZone = timeZone
    }

    fileprivate func request(header: RulesHeader, parts: TriaRequestParts) -> LLMRequest {
        let document = DocumentContext(
            originalFilename: originalFilename, created: created, modified: modified,
            extracted: ExtractedDocument(text: text, pageCount: pageCount, method: method,
                                         needsImage: !images.isEmpty, images: images))
        return LLMRequest(system: PromptBuilder.systemPrompt,
                          cachedContext: PromptBuilder.cachedContext(rules: rules, header: header, tree: tree,
                                                                     profile: profile),
                          userText: PromptBuilder.userText(document, feedback: feedback,
                                                 timeZone: TimeZone(identifier: timeZone) ?? .current),
                          images: images.map { LLMImage(jpeg: $0) },
                          schemaName: "tria_proposal", schema: Proposal.jsonSchema, parts: parts)
    }
}

/// «Pídeselo a Tria» (`RulesChangePrompt`).
public struct RulesChangeParts: Codable, Sendable, Equatable {
    public var rules: String
    public var tree: String
    public var profile: String?
    public var instruction: String

    public init(rules: String, tree: String, profile: String?, instruction: String) {
        self.rules = rules
        self.tree = tree
        self.profile = profile
        self.instruction = instruction
    }

    fileprivate func request(header: RulesHeader, parts: TriaRequestParts) -> LLMRequest {
        LLMRequest(system: RulesChangePrompt.systemPrompt,
                   cachedContext: RulesChangePrompt.cachedContext(rules: rules, header: header, tree: tree,
                                                                  profile: profile),
                   userText: RulesChangePrompt.userText(instruction),
                   schemaName: RulesChangePrompt.schemaName, schema: RulesChangePrompt.schema,
                   maxOutputTokens: RulesChangePrompt.maxOutputTokens, parts: parts)
    }
}

/// La sugerencia de regla tras una corrección (`RuleSuggestionPrompt`).
public struct SuggestionParts: Codable, Sendable, Equatable {
    public var rules: String
    public var proposedDestination: String
    public var proposedFilename: String
    public var originalFilename: String
    public var correctedDestination: String
    public var correctedFilename: String
    public var excerpt: String

    public init(rules: String, proposedDestination: String, proposedFilename: String, originalFilename: String,
                correctedDestination: String, correctedFilename: String, excerpt: String) {
        self.rules = rules
        self.proposedDestination = proposedDestination
        self.proposedFilename = proposedFilename
        self.originalFilename = originalFilename
        self.correctedDestination = correctedDestination
        self.correctedFilename = correctedFilename
        self.excerpt = excerpt
    }

    fileprivate func request(parts: TriaRequestParts) -> LLMRequest {
        LLMRequest(system: RuleSuggestionPrompt.systemPrompt, cachedContext: rules,
                   userText: RuleSuggestionPrompt.userText(self),
                   schemaName: RuleSuggestionPrompt.schemaName, schema: RuleSuggestionPrompt.schema,
                   maxOutputTokens: RuleSuggestionPrompt.maxOutputTokens, parts: parts)
    }
}
