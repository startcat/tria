import Foundation

/// Lo que costará, más o menos, leer documentos antes de enviarlos. La app lo enseña antes de un lote grande (spec de
/// la app, §3, `SpendMeter`) y `tria eval` antes de empezar. Es la cuenta que hacía `Evaluator`: las reglas más un
/// margen fijo de caracteres por petición, a unos 4 caracteres por token, y una respuesta de unos 300 tokens.
public enum ReadEstimate {
    /// Caracteres que se suman a las reglas en cada petición (el resto del contexto y el documento).
    static let marginCharacters = 6_000 + 4_000
    static let outputTokens = 300

    /// Tokens estimados por documento con estas reglas (la misma cuenta que usaba `Evaluator`).
    public static func tokensPerDocument(rulesCharacters: Int) -> (input: Int, output: Int) {
        (Pricing.estimatedTokens(characters: rulesCharacters + marginCharacters), outputTokens)
    }

    /// Coste aproximado de leer `documents` documentos en este espacio; `nil` si el modelo no tiene precio.
    public static func cost(documents: Int, workspace: Workspace, model: String) -> Double? {
        let perDocument = tokensPerDocument(rulesCharacters: workspace.rules.raw.count)
        return Pricing.estimateCost(inputTokens: perDocument.input * documents,
                                    outputTokens: perDocument.output * documents, model: model)
    }
}
