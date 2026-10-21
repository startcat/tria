import Foundation

/// Los textos con que se pide a la IA que corrija su respuesta tras un fallo de lectura. Los comparten el motor
/// (`Classifier`) y el servidor de la IA de Tria en su propio reintento, para que los dos digan exactamente lo mismo.
public enum ProposalFeedback {
    public static let truncated = "your answer was cut off; reply with the JSON object only"

    public static func unreadable(_ message: String) -> String {
        "the response could not be read (\(message))"
    }

    public static func invalidJSON(_ error: any Error) -> String {
        "your answer was not a valid JSON object for the schema (\(error))"
    }

    /// La realimentación recortada al tope del contrato (`TriaAPI.Limits.feedback`), que la mide en `Character`s: se
    /// corta entre grafemas, nunca a mitad de un carácter. Puede llevar lo que propuso el modelo (una ruta larguísima),
    /// y con la IA de Tria un segundo intento que pasara del tope lo rechazaría el servidor.
    public static func clamped(_ feedback: String) -> String {
        String(feedback.prefix(TriaAPI.Limits.feedback))
    }
}
