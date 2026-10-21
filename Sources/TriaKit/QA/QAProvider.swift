#if DEBUG
import Foundation

/// El proveedor falso de la tanda QA (spec QA §4): no sale a la red y contesta según la marca `[QA …]` del documento
/// (ver `QAMarker`), como lo haría un proveedor de verdad. Solo existe en Debug; lo montan la versión QA de la app y
/// el CLI con `TRIA_QA=1`.
///
/// - Cada respuesta gasta 1000 tokens de entrada y 200 de salida y lleva el modelo que tiene puesto: el gasto, el
///   límite y Uso funcionan como con uno de verdad.
/// - Cada petición que llega al proveedor deja una línea en `log`: `{"fichero","marca","modelo"}`. Las que no salen
///   del Mac (sin conexión) no dejan ninguna.
/// - Si existe el fichero `offlineFlag`, contesta «sin conexión»: antes de enviar y al acabar la espera.
/// - Contesta clasificaciones (`tria_proposal`), reglas sugeridas (`tria_rule_suggestion`) y cambios de reglas
///   (`tria_rules_change`, ver `rulesChange`). Aprender reglas de una carpeta lo rechaza.
public struct QAProvider: LLMProvider {
    public let id: ProviderID
    public let model: String
    /// `peticiones.jsonl`; con `nil`, no apunta nada.
    public let log: URL?
    /// `sin-red`; con `nil`, siempre hay red.
    public let offlineFlag: URL?

    /// Lo que gasta cada respuesta.
    public static let usage = TokenUsage(inputTokens: 1000, outputTokens: 200)
    /// Lo que dice el proveedor al rechazar un documento (`[QA error=rechazo]`). La app enseña «HTTP 400: …».
    public static let rejectionMessage = "documento rechazado (QA)"
    /// La duda de un documento sin marca.
    public static let noMarkerDoubt = "Sin marca QA"
    /// La duda de una marca sin carpeta ni duda, como `[QA espera=2]` sola.
    public static let emptyMarkerDoubt = "Marca QA sin carpeta ni duda"
    /// El motivo de todas las respuestas.
    public static let reason = "Documento de prueba de la tanda QA."

    /// La sección y la regla de una sugerencia sin `regla` en su marca.
    public static let defaultSuggestionSection = "Casos especiales"
    public static let defaultSuggestionRule = "Los documentos de prueba de la tanda QA van donde diga la corrección."
    /// «Pídeselo a Tria» sin `regla` ni `negativa` en la marca.
    public static let noRulesChangeRefusal = "Sin marca QA de cambio de reglas"
    public static let defaultRulesChangeSummary = "Cambio de la tanda QA"
    public static let defaultNewSectionTitle = "Reglas de la tanda QA"

    public init(id: ProviderID, model: String, log: URL?, offlineFlag: URL?) {
        self.id = id
        self.model = model
        self.log = log
        self.offlineFlag = offlineFlag
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        if isOffline { throw LLMError.offline }
        let marker = QAMarker.find(in: request.userText)
        let attributes = marker?.attributes ?? [:]
        let file = Self.originalFilename(in: request.userText)
        // Sin conexión la petición no sale del Mac: no se apunta.
        let reachesProvider = attributes["error"] != "sin-conexion"
        if reachesProvider { try record(file: file, marker: marker?.text ?? "") }
        if let seconds = attributes["espera"].flatMap(Double.init), seconds > 0 {
            // Con un tope: `espera=inf` o un valor enorme no debe romper el `UInt64`.
            try await Task.sleep(nanoseconds: UInt64(min(seconds, 3600) * 1_000_000_000))
        }
        // La red también puede caer mientras «el proveedor» piensa.
        if !reachesProvider || isOffline { throw LLMError.offline }
        let text: String
        switch request.schemaName {
        case "tria_proposal":
            text = try Self.answer(attributes, found: marker != nil, provider: id, originalFilename: file)
        case "tria_rule_suggestion":
            try Self.throwIfError(attributes, provider: id)
            text = try Self.suggestion(attributes)
        case RulesAsker.schemaName:
            try Self.throwIfError(attributes, provider: id)
            text = try Self.rulesChange(attributes, request: request)
        default:
            throw LLMError.rejected(status: 400, message: "QA: sin respuesta falsa para \(request.schemaName)")
        }
        return LLMResponse(text: text, usage: Self.usage, model: model)
    }

    /// El JSON de `Proposal.jsonSchema` que daría un modelo, o el error que lanzaría un proveedor de verdad.
    static func answer(_ attributes: [String: String], found: Bool, provider: ProviderID,
                       originalFilename: String) throws -> String {
        try throwIfError(attributes, provider: provider)
        if let kind = attributes["error"] { return try pending(doubt: "Marca QA desconocida: error=\(kind)") }
        if let folder = attributes["carpeta"] {
            let confidence = Self.confidence(attributes["confianza"])
            // Como pide `PromptBuilder.systemPrompt`: sin confianza alta, una duda.
            let doubt = attributes["duda"]
                ?? (confidence == .high ? nil : "Confianza \(attributes["confianza"] ?? "baja") (marca QA).")
            let value: JSONValue = [
                "action": "file",
                "destination": .string(folder),
                "filename": .string(filename(attributes["nombre"], originalFilename: originalFilename)),
                "document_type": .string(attributes["tipo"] ?? "Documento"),
                "document_date": attributes["fecha"].map(JSONValue.string) ?? .null,
                "confidence": .string(confidence.rawValue),
                "reason": .string(reason),
                "doubt": doubt.map(JSONValue.string) ?? .null,
            ]
            return String(decoding: try value.encodedData(), as: UTF8.self)
        }
        if let doubt = attributes["duda"] { return try pending(doubt: doubt) }
        return try pending(doubt: found ? emptyMarkerDoubt : noMarkerDoubt)
    }

    /// Los fallos de un proveedor de verdad (`error=rechazo|negativa|cuota`), iguales en las tres peticiones
    /// (clasificación, sugerencia y cambio de reglas). `sin-conexion` ya se ha tratado antes.
    static func throwIfError(_ attributes: [String: String], provider: ProviderID) throws {
        switch attributes["error"] {
        case "rechazo"?: throw LLMError.rejected(status: 400, message: rejectionMessage)
        case "negativa"?: throw LLMError.refused
        case "cuota"?: throw LLMError.quotaExceeded(quotaMessage(provider))
        default: break
        }
    }

    /// Una regla sugerida (`tria_rule_suggestion`): la de `regla="…"` en la sección `titulo="…"` del documento.
    static func suggestion(_ attributes: [String: String]) throws -> String {
        let value: JSONValue = ["section": .string(attributes["titulo"] ?? defaultSuggestionSection),
                                "rule": .string(attributes["regla"] ?? defaultSuggestionRule)]
        return String(decoding: try value.encodedData(), as: UTF8.self)
    }

    /// Un cambio de reglas (`tria_rules_change`), según la marca de la petición:
    /// - `roto=si`: una respuesta que no es JSON;
    /// - `negativa="…"`: no hay cambio, con ese motivo;
    /// - `regla="…"`: una viñeta al final de la sección `seccion=sN` (la que llega en la petición), quitando antes la
    ///   línea `quita="…"` si está; sin `seccion`, en una sección nueva «## <titulo>». Con `carpeta-nueva="…"`, pide
    ///   crearla; `resumen="…"`, el resumen;
    /// - sin `regla` ni `negativa`, `noRulesChangeRefusal`.
    static func rulesChange(_ attributes: [String: String], request: LLMRequest) throws -> String {
        if attributes["roto"] != nil { return "Esto no es JSON (QA)" }
        if let refusal = attributes["negativa"] ?? (attributes["regla"] == nil ? noRulesChangeRefusal : nil) {
            let value: JSONValue = ["summary": "", "refusal": .string(refusal), "sections": [], "header": .null,
                                    "create_folders": []]
            return String(decoding: try value.encodedData(), as: UTF8.self)
        }
        let rule = attributes["regla"] ?? ""
        let id = attributes["seccion"] ?? "new"
        var lines: [String]
        if id == "new" {
            lines = ["## \(attributes["titulo"] ?? defaultNewSectionTitle)", ""]
        } else {
            // Una sección que no llega en la petición se contesta igual: el motor la rechaza.
            lines = (RulesAsker.sectionText(id, inContext: request.cachedContext) ?? "## Sección QA")
                .components(separatedBy: "\n")
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
            if let removing = attributes["quita"],
               let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == removing }) {
                lines.remove(at: index)
            }
        }
        lines.append("- \(rule)")
        let value: JSONValue = [
            "summary": .string(attributes["resumen"] ?? defaultRulesChangeSummary), "refusal": .null,
            "sections": [["id": .string(id), "text": .string(lines.joined(separator: "\n") + "\n")]],
            "header": .null,
            "create_folders": .array(attributes["carpeta-nueva"].map { [.string($0)] } ?? []),
        ]
        return String(decoding: try value.encodedData(), as: UTF8.self)
    }

    /// Lo que contesta un modelo que no sabe decidir: `action: pending`, con su duda.
    private static func pending(doubt: String) throws -> String {
        let value: JSONValue = [
            "action": "pending", "destination": "", "filename": "", "document_type": "Documento",
            "document_date": .null, "confidence": "low", "reason": .string(reason), "doubt": .string(doubt),
        ]
        return String(decoding: try value.encodedData(), as: UTF8.self)
    }

    /// «alta», «media» y «baja» (o «high», «medium» y «low»). Lo demás, baja.
    private static func confidence(_ value: String?) -> Confidence {
        switch value?.lowercased() {
        case "alta", "high": return .high
        case "media", "medium": return .medium
        default: return .low
        }
    }

    /// El nombre de la marca con la extensión del documento, como pide `PromptBuilder.systemPrompt`. Sin nombre, el
    /// del documento.
    private static func filename(_ name: String?, originalFilename: String) -> String {
        let ext = (originalFilename as NSString).pathExtension
        guard let name, !name.isEmpty else { return originalFilename }
        guard !ext.isEmpty, !name.lowercased().hasSuffix("." + ext.lowercased()) else { return name }
        return name + "." + ext
    }

    /// Lo que dice cada proveedor de verdad cuando la cuenta se queda sin saldo.
    static func quotaMessage(_ provider: ProviderID) -> String {
        switch provider {
        case .anthropic:
            return "Your credit balance is too low to access the Anthropic API. "
                + "Please go to Plans & Billing to upgrade or purchase credits."
        case .openai:
            return "You exceeded your current quota, please check your plan and billing details."
        }
    }

    /// El nombre que `PromptBuilder.userText` pone a cada documento («Original file name: …»).
    static func originalFilename(in userText: String) -> String {
        let prefix = "Original file name: "
        let line = userText.split(separator: "\n").first { $0.hasPrefix(prefix) }
        return line.map { String($0.dropFirst(prefix.count)) } ?? ""
    }

    private var isOffline: Bool {
        guard let offlineFlag else { return false }
        return FileManager.default.fileExists(atPath: offlineFlag.path)
    }

    /// Una línea por petición, con `O_APPEND` y una sola escritura: la app y el CLI pueden apuntar a la vez en el mismo
    /// fichero sin mezclar líneas.
    private func record(file: String, marker: String) throws {
        guard let log else { return }
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let entry: JSONValue = ["modelo": .string(model), "fichero": .string(file), "marca": .string(marker)]
        var line = try entry.encodedData()
        line.append(0x0A)
        let fd = open(log.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw QAProviderError.cannotLog(log.path) }
        defer { close(fd) }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { throw QAProviderError.cannotLog(log.path) }
    }
}

/// `QAProvider` no ha podido apuntar la petición: la prueba no podría comprobar qué se envió. El `Classifier` lo deja
/// como un rechazo del proveedor, que se ve en la app y en el CLI.
public enum QAProviderError: Error, Equatable, Sendable {
    case cannotLog(String)
}
#endif
