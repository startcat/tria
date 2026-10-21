import Foundation

public struct LearnSample: Sendable, Equatable {
    public var relativePath: String
    public var excerpt: String
}

public struct LearnPlan: Sendable, Equatable {
    public var root: URL
    public var tree: String
    public var samples: [LearnSample]
    public var estimatedInputTokens: Int
    public var estimatedOutputTokens: Int

    public func estimatedCost(model: String) -> Double? {
        Pricing.estimateCost(inputTokens: estimatedInputTokens, outputTokens: estimatedOutputTokens, model: model)
    }
}

public struct RuleSuggestionDraft: Codable, Sendable, Equatable {
    public var section: String
    public var rule: String

    public init(section: String, rule: String) {
        self.section = section
        self.rule = rule
    }
}

public enum LearnError: Error, Equatable, Sendable {
    case emptyFolder
    case invalidDraft(String)
}

/// Una sugerencia de regla que no se puede usar: el motivo y lo que costó, que se paga igual y suma al gasto.
public struct LearnFailure: Error, Equatable, Sendable {
    public var reason: LearnError
    public var usage: TokenUsage

    public init(reason: LearnError, usage: TokenUsage) {
        self.reason = reason
        self.usage = usage
    }
}

/// Genera borradores de reglas: a partir de una carpeta (spec §7.2) o de una corrección (spec §7.3).
public struct RulesLearner: Sendable {
    public let provider: any LLMProvider
    public let extractor: DocumentExtractor

    public static let sampleExtractor = DocumentExtractor(
        limits: ExtractionLimits(maxPages: 1, maxCharacters: 1500, includeImages: false))

    public init(provider: any LLMProvider, extractor: DocumentExtractor = RulesLearner.sampleExtractor) {
        self.provider = provider
        self.extractor = extractor
    }

    public func plan(root: URL, sampleSize: Int = 20) throws -> LearnPlan {
        let files = try ArchiveScanner.files(in: root, maxDepth: 4)
            .filter { !Workspace.isSpaceFile($0.relativePath) }
        guard !files.isEmpty else { throw LearnError.emptyFolder }

        var groups = Dictionary(grouping: files) { ($0.relativePath as NSString).deletingLastPathComponent }
            .mapValues { $0.sorted { $0.modified > $1.modified } }
        let folders = groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var picked: [ArchiveFile] = []
        while picked.count < sampleSize, groups.values.contains(where: { !$0.isEmpty }) {
            for folder in folders where picked.count < sampleSize {
                if let next = groups[folder]?.first {
                    picked.append(next)
                    groups[folder]?.removeFirst()
                }
            }
        }

        let samples = picked.map { file in
            LearnSample(relativePath: file.relativePath,
                        excerpt: (try? extractor.extract(file.url).text) ?? "(could not be read)")
        }
        let tree = try FolderTree.render(root: root, skipping: [], protected: ProtectedPaths([]),
                                         options: FolderTreeOptions(examplesPerFolder: 5))
        let characters = Self.learnSystemPrompt(.es).count + tree.count + samples.map { $0.excerpt.count + 80 }.reduce(0, +)
        return LearnPlan(root: root, tree: tree, samples: samples,
                         estimatedInputTokens: Pricing.estimatedTokens(characters: characters),
                         estimatedOutputTokens: 3000)
    }

    public func draft(_ plan: LearnPlan, language: TemplateLanguage) async throws -> (text: String, usage: TokenUsage) {
        let samples = plan.samples.map { "## \($0.relativePath)\n\($0.excerpt)" }.joined(separator: "\n\n")
        let request = LLMRequest(system: Self.learnSystemPrompt(language),
                                 cachedContext: "# Archive folder tree\n\n\(plan.tree)",
                                 userText: "# Sample documents\n\n\(samples)",
                                 schemaName: "tria_rules_draft", schema: Self.draftSchema, maxOutputTokens: 8000)
        let response = try await provider.complete(request)

        struct Draft: Decodable {
            var inbox: String
            var duplicates: String
            var protected: [String]
            var new_folders: String
            var body: String
        }
        guard let start = response.text.firstIndex(of: "{"), let end = response.text.lastIndex(of: "}"),
              let draft = try? JSONDecoder().decode(Draft.self, from: Data(response.text[start...end].utf8)) else {
            throw LearnError.invalidDraft("not JSON")
        }
        let header = RulesHeader(inbox: draft.inbox, duplicates: draft.duplicates, protected: draft.protected,
                                 newFolders: NewFoldersPolicy(rawValue: draft.new_folders) ?? .subfoldersOnly)
        let text = RulesFile.render(header: header, body: draft.body)
        do { _ = try RulesFile.parse(text) } catch { throw LearnError.invalidDraft(String(describing: error)) }
        return (text, response.usage)
    }

    /// Pide una regla que habría acertado la corrección. Si la respuesta llega pero no se entiende, lanza
    /// `LearnFailure` con lo pagado; lo que falla antes (sin red, clave mala) lo lanza el proveedor tal cual.
    public func suggestRule(rules: RulesFile, original: Proposal, originalFilename: String,
                            correctedDestination: String, correctedFilename: String,
                            excerpt: String) async throws -> (RuleSuggestionDraft, TokenUsage) {
        let parts = SuggestionParts(
            rules: rules.raw, proposedDestination: original.destination, proposedFilename: original.filename,
            originalFilename: originalFilename, correctedDestination: correctedDestination,
            correctedFilename: correctedFilename, excerpt: excerpt)
        // `makeRequest()` es throwing para todas las piezas (las de clasificar leen `TRIA.md`); esta no lanza.
        let request = try TriaRequestParts.ruleSuggestion(parts).makeRequest()
        let response = try await provider.complete(request)
        guard let start = response.text.firstIndex(of: "{"), let end = response.text.lastIndex(of: "}"),
              let draft = try? JSONDecoder().decode(RuleSuggestionDraft.self, from: Data(response.text[start...end].utf8))
        else { throw LearnFailure(reason: .invalidDraft("not JSON"), usage: response.usage) }
        return (draft, response.usage)
    }

    static func learnSystemPrompt(_ language: TemplateLanguage) -> String {
        let name = language == .es ? "Spanish" : "Catalan"
        let inbox = language == .es ? "99-Pendiente" : "99-Pendent"
        let duplicates = language == .es ? "98-Duplicados" : "98-Duplicats"
        let sections = language == .es
            ? "\"## Carpetas\", \"## Nomenclatura\" and \"## Casos especiales\""
            : "\"## Carpetes\", \"## Nomenclatura\" and \"## Casos especials\""
        return """
        You write filing rules (TRIA.md) for an existing document archive, so that an assistant can later file new \
        documents the same way. You receive the folder tree (with example file names) and short excerpts of sample \
        documents. Write in \(name).

        - inbox: the existing folder that works as an inbox (names like "Pendiente", "Inbox", "Entrada", "99-…"); \
        if none exists, "\(inbox)".
        - duplicates: an existing duplicates folder, or "\(duplicates)".
        - protected: folders that look like closed packages that must never change (for example year/quarter \
        folders copied as a block); empty if unsure.
        - new_folders: "subfolders_only" unless the archive clearly needs something else.
        - body: Markdown starting with "# <title>", then \(sections). Carpetas: a table folder | content. \
        Nomenclatura: a table type | pattern | example, deduced from the existing file names. Casos especiales: \
        bullet rules for ambiguous cases. Describe what you see; do not invent folders.
        """
    }

    static var suggestionSystemPrompt: String { RuleSuggestionPrompt.systemPrompt }

    static let draftSchema: JSONValue = [
        "type": "object",
        "additionalProperties": false,
        "required": ["inbox", "duplicates", "protected", "new_folders", "body"],
        "properties": [
            "inbox": ["type": "string"],
            "duplicates": ["type": "string"],
            "protected": ["type": "array", "items": ["type": "string"]],
            "new_folders": ["type": "string", "enum": ["never", "subfolders_only", "anywhere"]],
            "body": ["type": "string"],
        ],
    ]

    static var suggestionSchema: JSONValue { RuleSuggestionPrompt.schema }
}
