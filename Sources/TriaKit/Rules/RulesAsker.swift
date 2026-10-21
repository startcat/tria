import Foundation

public enum RulesAskResult: Equatable, Sendable {
    case change(RulesChange)
    /// El modelo explica por qué no lo hace.
    case refused(String)
}

/// Por qué un cambio pedido a Tria no se puede proponer (spec de Reglas, §4.2). Nada se ha tocado.
public enum RulesAskError: Error, Equatable, Sendable {
    /// La respuesta no es JSON o no cumple el esquema.
    case invalidResponse(String)
    case unknownSection(String)
    case repeatedSection(String)
    /// El `text` de esa sección no es una sola sección que empiece por «## ».
    case notOneSection(String)
    /// El `TRIA.md` resultante no se puede leer.
    case invalidRules(RulesError)
    case inboxChanged
    case duplicatesChanged
    /// La cabecera nueva protegería la bandeja o la carpeta de duplicados.
    case inboxProtected
    case duplicatesProtected
    case unsafeFolder(String)
    /// Una carpeta que se crearía dentro de una protegida (o que lo es).
    case protectedFolder(String)
    case folderExists(String)
    case repeatedFolder(String)
    /// La respuesta deja `TRIA.md` como estaba.
    case noChange
}

/// Una respuesta del modelo que no se puede proponer: el motivo y lo que costó, que se paga igual y suma al gasto.
public struct RulesAskFailure: Error, Equatable, Sendable {
    public var reason: RulesAskError
    public var usage: TokenUsage

    public init(reason: RulesAskError, usage: TokenUsage) {
        self.reason = reason
        self.usage = usage
    }
}

/// «Pídeselo a Tria» (spec de Reglas, §4.2): una frase del usuario se convierte en un cambio de `TRIA.md` que se enseña
/// antes de aplicarlo. Envía la petición, `TRIA.md` con sus secciones numeradas, el árbol de carpetas y `PERFIL.md`;
/// ningún documento. El prompt y el esquema son fijos y viven en `RulesChangePrompt` (TriaCore), como los de
/// `RulesLearner` en `RuleSuggestionPrompt`, para que `tria-api` los use igual.
public struct RulesAsker: Sendable {
    public let provider: any LLMProvider

    public static let schemaName = RulesChangePrompt.schemaName
    static let maxOutputTokens = RulesChangePrompt.maxOutputTokens
    static let estimatedOutputTokens = 1500

    public init(provider: any LLMProvider) { self.provider = provider }

    public func ask(_ instruction: String, in workspace: Workspace) async throws -> (RulesAskResult, TokenUsage) {
        let response = try await provider.complete(try Self.request(instruction, in: workspace))
        do {
            return (try Self.result(response.text, in: workspace), response.usage)
        } catch let error as RulesAskError {
            throw RulesAskFailure(reason: error, usage: response.usage)
        }
    }

    /// Lo que costará, aproximado, con `model`; `nil` si el modelo no tiene precio.
    public func estimatedCost(for workspace: Workspace, model: String) -> Double? {
        let context = (try? Self.cachedContext(for: workspace)) ?? workspace.rules.raw
        // La petición no se sabe aún: unos 300 caracteres.
        let characters = Self.systemPrompt.count + context.count + 300
        return Pricing.estimateCost(inputTokens: Pricing.estimatedTokens(characters: characters),
                                    outputTokens: Self.estimatedOutputTokens, model: model)
    }

    public static func request(_ instruction: String, in workspace: Workspace) throws -> LLMRequest {
        let parts = RulesChangeParts(rules: workspace.rules.raw, tree: try workspace.folderTree(),
                                     profile: workspace.profile?.raw, instruction: instruction)
        return TriaRequestParts.rulesChange(parts).makeRequest(rules: workspace.rules)
    }

    // MARK: - Lo que se envía

    public static var systemPrompt: String { RulesChangePrompt.systemPrompt }

    public static var schema: JSONValue { RulesChangePrompt.schema }

    /// El contexto de `workspace`: sus piezas (`TRIA.md`, árbol y perfil) pasan por `RulesChangePrompt`.
    static func cachedContext(for workspace: Workspace) throws -> String {
        RulesChangePrompt.cachedContext(rules: workspace.rules.raw, header: workspace.rules.header,
                                        tree: try workspace.folderTree(), profile: workspace.profile?.raw)
    }

    static func userText(_ instruction: String) -> String { RulesChangePrompt.userText(instruction) }

    /// El texto de la sección `id` tal como va en el contexto, sin su salto final; `nil` si no está. Lo usa el
    /// proveedor de la tanda QA para contestar con la sección entera.
    static func sectionText(_ id: String, inContext context: String) -> String? {
        guard let open = context.range(of: "<<<SECTION \(id)\n"),
              let close = context.range(of: "\nSECTION \(id)>>>", range: open.upperBound..<context.endIndex) else {
            return nil
        }
        return String(context[open.upperBound..<close.lowerBound])
    }

    // MARK: - Lo que vuelve

    private struct Answer: Decodable {
        struct Section: Decodable {
            var id: String
            var text: String
        }

        struct Header: Decodable {
            var new_folders: String
            var protected: [String]
            /// El esquema no los pide: si llegan y son otros, el cambio no se propone.
            var inbox: String?
            var duplicates: String?
        }

        var summary: String
        var refusal: String?
        var sections: [Section]
        var header: Header?
        var create_folders: [String]
    }

    /// Lo que comprueba el motor antes de proponer el cambio (spec de Reglas, §4.2): las secciones, la cabecera, que
    /// `TRIA.md` se pueda leer con la misma bandeja y los mismos duplicados, y las carpetas.
    static func result(_ text: String, in workspace: Workspace) throws -> RulesAskResult {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let answer = try? JSONDecoder().decode(Answer.self, from: Data(text[start...end].utf8)) else {
            throw RulesAskError.invalidResponse(String(text.prefix(200)))
        }
        if let refusal = answer.refusal?.trimmingCharacters(in: .whitespacesAndNewlines), !refusal.isEmpty {
            return .refused(refusal)
        }
        let original = RulesDocument.parse(workspace.rules.raw)
        var document = original
        var replaced = Set<String>()
        for section in answer.sections {
            let id = section.id.trimmingCharacters(in: .whitespaces)
            let body: String
            do { body = try RulesChange.oneSection(section.text) } catch { throw RulesAskError.notOneSection(id) }
            if id == "new" {
                document = document.appending(body)
                continue
            }
            guard original.section(id) != nil else { throw RulesAskError.unknownSection(id) }
            guard replaced.insert(id).inserted else { throw RulesAskError.repeatedSection(id) }
            document = document.replacing(id, with: body) ?? document
        }
        let current = workspace.rules.header
        if let header = answer.header {
            if let inbox = header.inbox, inbox.normalizedRelativePath != current.inbox { throw RulesAskError.inboxChanged }
            if let duplicates = header.duplicates, duplicates.normalizedRelativePath != current.duplicates {
                throw RulesAskError.duplicatesChanged
            }
            guard let policy = NewFoldersPolicy(rawValue: header.new_folders) else {
                throw RulesAskError.invalidResponse("new_folders: \(header.new_folders)")
            }
            // Una cabecera igual a la de ahora no se reescribe: se conservan sus comentarios.
            if let newHeader = current.updating(newFolders: policy, protected: header.protected) {
                // Ni la bandeja ni duplicados pueden quedar protegidas: Tria ya no podría dejar nada en ellas.
                if newHeader.protectsInbox { throw RulesAskError.inboxProtected }
                if newHeader.protectsDuplicates { throw RulesAskError.duplicatesProtected }
                document = document.replacingFrontmatter(RulesFile.render(header: newHeader, body: ""))
            }
        }
        let rules: RulesFile
        do { rules = try RulesFile.parse(document.text) } catch let error as RulesError {
            throw RulesAskError.invalidRules(error)
        }
        guard rules.header.inbox == current.inbox else { throw RulesAskError.inboxChanged }
        guard rules.header.duplicates == current.duplicates else { throw RulesAskError.duplicatesChanged }
        let folders = try checkedFolders(answer.create_folders, protected: ProtectedPaths(rules.header.protected),
                                         in: workspace)
        let summary = answer.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return .change(try RulesChange.make(from: workspace, to: document, createFolders: folders, summary: summary))
        } catch RulesChangeError.noChange {
            throw RulesAskError.noChange
        } catch RulesChangeError.invalidRules(let error) {
            throw RulesAskError.invalidRules(error)
        } catch RulesChangeError.unclosedCodeBlock {
            // Lo de antes deja un bloque de código abierto (un TRIA.md escrito a mano) y se tragaría la sección: no
            // queda como una sola. Las del modelo ya cierran los suyos (`oneSection`): suele ser una sección nueva.
            let lost = document.firstLostSection() ?? original.sections.count
            throw RulesAskError.notOneSection(lost < original.sections.count ? "s\(lost + 1)" : "new")
        }
    }

    /// Las carpetas que se crearán (spec de Reglas, §4.2, punto 3): rutas relativas seguras dentro del espacio, fuera
    /// de `.tria`, de la bandeja, de duplicados y de lo que queda protegido (`protected`, la cabecera ya cambiada), que
    /// no existen todavía y no se repiten.
    static func checkedFolders(_ paths: [String], protected: ProtectedPaths,
                               in workspace: Workspace) throws -> [String] {
        var seen = Set<String>()
        var folders: [String] = []
        for raw in paths {
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines).normalizedRelativePath
            let key = path.lowercased()
            guard PathSafety.isSafeRelative(raw), !path.isEmpty,
                  !workspace.isReserved(path),
                  workspace.containedURL(forRelative: path) != nil else {
                throw RulesAskError.unsafeFolder(raw)
            }
            guard !protected.contains(path) else { throw RulesAskError.protectedFolder(path) }
            guard seen.insert(key).inserted else { throw RulesAskError.repeatedFolder(path) }
            guard !FileManager.default.fileExists(atPath: workspace.url(forRelative: path).path) else {
                throw RulesAskError.folderExists(path)
            }
            folders.append(path)
        }
        return folders
    }
}
