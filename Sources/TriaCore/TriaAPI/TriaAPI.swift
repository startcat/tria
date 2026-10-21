import Foundation

/// El contrato entre la app de Mac y `tria-api` (la IA de Tria): los tipos de cada petición y respuesta, los topes de
/// tamaño y el codificador JSON, que es siempre el mismo en los dos lados. Claves JSON en inglés y en `camelCase`.
///
/// Rutas (todas bajo `https://api.tria.lyn.cat`; la ficha de sesión va en `Authorization: Bearer <token>`):
/// - `POST /v1/sesion` (`SessionRequest` → `SessionResponse`), `POST /v1/compras` (`PurchasesRequest` → `PurchasesResponse`);
/// - `POST /v1/clasificar` (`CompleteRequest` con `.proposal`) y `POST /v1/reglas` (`.rulesChange` y `.ruleSuggestion`),
///   las dos → `CompleteResponse`;
/// - `GET /v1/estado` (→ `BuyerStatus`), `GET /v1/datos` (→ `BuyerData`) y `DELETE /v1/datos`;
/// - `POST /apple/notificaciones` (App Store Server Notifications, solo del servidor de Apple).
///
/// Los fallos viajan como `ErrorBody` con el estado HTTP que decida el servidor.
public enum TriaAPI {
    public static let version = "v1"

    public enum Environment: String, Codable, Sendable, Equatable {
        case sandbox, production
    }

    /// El saldo y los límites del comprador, tal como los ve la app.
    public struct BuyerStatus: Codable, Sendable, Equatable {
        public var unlocked: Bool
        /// Huecos de prueba que quedan (sin desbloqueo).
        public var trialRemaining: Int
        /// Documentos de paquetes que quedan.
        public var balance: Int
        public var documentsToday: Int
        public var documentsDailyLimit: Int
        /// «Pídeselo a Tria» que quedan hoy.
        public var rulesChangesLeft: Int
        public var suggestionsLeft: Int
        public var environment: Environment

        public init(unlocked: Bool, trialRemaining: Int, balance: Int, documentsToday: Int, documentsDailyLimit: Int,
                    rulesChangesLeft: Int, suggestionsLeft: Int, environment: Environment) {
            self.unlocked = unlocked
            self.trialRemaining = trialRemaining
            self.balance = balance
            self.documentsToday = documentsToday
            self.documentsDailyLimit = documentsDailyLimit
            self.rulesChangesLeft = rulesChangesLeft
            self.suggestionsLeft = suggestionsLeft
            self.environment = environment
        }
    }

    public struct SessionRequest: Codable, Sendable, Equatable {
        /// El `AppTransaction` firmado (JWS).
        public var appTransaction: String

        public init(appTransaction: String) {
            self.appTransaction = appTransaction
        }
    }

    public struct SessionResponse: Codable, Sendable, Equatable {
        public var token: String
        public var expiresAt: Date
        public var status: BuyerStatus

        public init(token: String, expiresAt: Date, status: BuyerStatus) {
            self.token = token
            self.expiresAt = expiresAt
            self.status = status
        }
    }

    public struct PurchasesRequest: Codable, Sendable, Equatable {
        /// Transacciones firmadas (JWS).
        public var transactions: [String]

        public init(transactions: [String]) {
            self.transactions = transactions
        }
    }

    public struct CreditedTransaction: Codable, Sendable, Equatable {
        public var transactionId: String
        public var productId: String
        public var documents: Int
        /// La transacción ya estaba abonada: no se vuelve a sumar.
        public var alreadyCredited: Bool

        public init(transactionId: String, productId: String, documents: Int, alreadyCredited: Bool) {
            self.transactionId = transactionId
            self.productId = productId
            self.documents = documents
            self.alreadyCredited = alreadyCredited
        }
    }

    public struct PurchasesResponse: Codable, Sendable, Equatable {
        public var credited: [CreditedTransaction]
        public var status: BuyerStatus

        public init(credited: [CreditedTransaction], status: BuyerStatus) {
            self.credited = credited
            self.status = status
        }
    }

    public struct CompleteRequest: Codable, Sendable, Equatable {
        public var parts: TriaRequestParts
        /// Un identificador al azar por petición lógica (`UUID().uuidString`), hasta `Limits.requestId` caracteres. La
        /// app lo pone una vez y lo reutiliza sin cambiarlo en los reintentos de transporte y en el reenvío tras renovar
        /// la sesión; una petición nueva (también el segundo intento con `feedback`) lleva otro. El servidor lo apunta
        /// al cobrar: una entrega repetida con el mismo `requestId` y el mismo contenido en 15 minutos no se vuelve a
        /// cobrar. `nil` en una app de antes: el JSON sin la clave se sigue leyendo, y entonces se cobra como siempre.
        public var requestId: String?

        public init(parts: TriaRequestParts, requestId: String? = nil) {
            self.parts = parts
            self.requestId = requestId
        }
    }

    public struct CompleteResponse: Codable, Sendable, Equatable {
        /// La respuesta del modelo, tal cual.
        public var text: String
        public var usage: TokenUsage
        public var model: String
        /// Esta lectura restó del saldo o de la prueba.
        public var charged: Bool
        public var status: BuyerStatus

        public init(text: String, usage: TokenUsage, model: String, charged: Bool, status: BuyerStatus) {
            self.text = text
            self.usage = usage
            self.model = model
            self.charged = charged
            self.status = status
        }
    }

    /// Una compra procesada, tal como la guarda el servidor («Tus datos»).
    public struct PurchaseRecord: Codable, Sendable, Equatable {
        public var transactionId: String
        public var productId: String
        public var documents: Int
        public var creditedAt: Date
        /// Cuándo reembolsó Apple la compra, si lo hizo.
        public var refundedAt: Date?

        public init(transactionId: String, productId: String, documents: Int, creditedAt: Date, refundedAt: Date?) {
            self.transactionId = transactionId
            self.productId = productId
            self.documents = documents
            self.creditedAt = creditedAt
            self.refundedAt = refundedAt
        }
    }

    /// Lo que el servidor sabe de un comprador («Tus datos»).
    public struct BuyerData: Codable, Sendable, Equatable {
        public var appTransactionId: String
        public var environment: Environment
        public var createdAt: Date
        public var status: BuyerStatus
        public var purchases: [PurchaseRecord]
        public var trialDocuments: Int
        public var requestsLast90Days: Int
        /// Documentos por día, con la clave «AAAA-MM-DD» (día de `Europe/Madrid`).
        public var documentsByDay: [String: Int]

        public init(appTransactionId: String, environment: Environment, createdAt: Date, status: BuyerStatus,
                    purchases: [PurchaseRecord], trialDocuments: Int, requestsLast90Days: Int,
                    documentsByDay: [String: Int]) {
            self.appTransactionId = appTransactionId
            self.environment = environment
            self.createdAt = createdAt
            self.status = status
            self.purchases = purchases
            self.trialDocuments = trialDocuments
            self.requestsLast90Days = requestsLast90Days
            self.documentsByDay = documentsByDay
        }
    }

    /// El `rawValue` es lo que viaja en `ErrorBody.code` y lo que lleva `LLMError.serviceLimit`.
    public enum ErrorCode: String, Codable, Sendable, Equatable {
        case sessionInvalid, sessionExpired, purchaseInvalid, trialEnded, balanceEmpty, dailyLimit
        case rulesNotAllowed, rulesLimit, tooLarge, noValidAnswer, modelUnavailable, refused
    }

    public struct ErrorBody: Codable, Sendable, Equatable {
        public var code: ErrorCode
        public var message: String
        public var status: BuyerStatus?

        public init(code: ErrorCode, message: String, status: BuyerStatus? = nil) {
            self.code = code
            self.message = message
            self.status = status
        }
    }

    /// Los topes de tamaño, con margen sobre `ExtractionLimits` y `FolderTreeOptions`. Los textos se miden en
    /// `Character`s (grafemas, como el motor), las imágenes en bytes, y `body` es el cuerpo entero de la petición, en bytes.
    /// Al final, los topes diarios por comprador, que no son de tamaño.
    public enum Limits {
        public static let rules = 128 * 1024
        public static let profile = 32 * 1024
        public static let tree = 256 * 1024
        public static let text = 16_000
        public static let images = 2
        public static let imageBytes = 1_500_000
        public static let filename = 512
        public static let feedback = 2_000
        public static let instruction = 4_000
        public static let excerpt = 16_000
        public static let timeZone = 64
        public static let requestId = 64
        public static let body = 6 * 1024 * 1024

        /// «Pídeselo a Tria» por comprador y día (día de `Europe/Madrid`): cambios de Reglas (`.rulesChange`) y
        /// sugerencias tras una corrección (`.ruleSuggestion`), cada uno con su cuenta. Pasado el tope, `rulesLimit`.
        public static let rulesChangesPerDay = 50
        public static let suggestionsPerDay = 50
    }

    /// Una pieza de la petición pasa de su tope. Lleva `ErrorCode.tooLarge` y nombra la pieza.
    public struct LimitError: Error, Sendable, Equatable, CustomStringConvertible {
        public var code: ErrorCode { .tooLarge }
        /// La pieza que sobra, por su nombre en el contrato (`text`, `images`, `images[1]`...).
        public var piece: String
        public var limit: Int
        public var actual: Int

        public init(piece: String, limit: Int, actual: Int) {
            self.piece = piece
            self.limit = limit
            self.actual = actual
        }

        public var message: String { "«\(piece)» es demasiado grande (\(actual); el tope es \(limit))." }
        public var description: String { message }

        /// El cuerpo de error que devuelve el servidor.
        public func body(status: BuyerStatus? = nil) -> ErrorBody {
            ErrorBody(code: code, message: message, status: status)
        }
    }

    /// Comprueba los topes; lanza `TriaAPI.LimitError` (código `ErrorCode.tooLarge`) con la pieza que sobra. Los textos se
    /// miden en `Character`s, la misma unidad con que el motor recorta el texto.
    public static func check(_ parts: TriaRequestParts) throws {
        switch parts {
        case .proposal(let p):
            try require("rules", p.rules, Limits.rules)
            try require("tree", p.tree, Limits.tree)
            try require("profile", p.profile, Limits.profile)
            try require("originalFilename", p.originalFilename, Limits.filename)
            try require("text", p.text, Limits.text)
            try require("feedback", p.feedback, Limits.feedback)
            try require("timeZone", p.timeZone, Limits.timeZone)
            try bound("images", p.images.count, Limits.images)
            for (index, image) in p.images.enumerated() {
                try bound("images[\(index)]", image.count, Limits.imageBytes)
            }
        case .rulesChange(let p):
            try require("rules", p.rules, Limits.rules)
            try require("tree", p.tree, Limits.tree)
            try require("profile", p.profile, Limits.profile)
            try require("instruction", p.instruction, Limits.instruction)
        case .ruleSuggestion(let p):
            try require("rules", p.rules, Limits.rules)
            try require("proposedDestination", p.proposedDestination, Limits.filename)
            try require("proposedFilename", p.proposedFilename, Limits.filename)
            try require("originalFilename", p.originalFilename, Limits.filename)
            try require("correctedDestination", p.correctedDestination, Limits.filename)
            try require("correctedFilename", p.correctedFilename, Limits.filename)
            try require("excerpt", p.excerpt, Limits.excerpt)
        }
    }

    /// Lo mismo con la petición entera: las piezas y el `requestId`.
    public static func check(_ request: CompleteRequest) throws {
        try check(request.parts)
        try require("requestId", request.requestId, Limits.requestId)
    }

    private static func require(_ piece: String, _ value: String?, _ limit: Int) throws {
        guard let value else { return }
        try bound(piece, value.count, limit)
    }

    private static func bound(_ piece: String, _ actual: Int, _ limit: Int) throws {
        if actual > limit { throw LimitError(piece: piece, limit: limit, actual: actual) }
    }

    // MARK: JSON

    /// El codificador del contrato. Son funciones y no `static let` para no compartir un objeto mutable entre hilos
    /// (Swift 6); cada llamada da uno nuevo y todos se comportan igual. Fechas en ISO 8601 en UTC **con fracciones de
    /// segundo** (`2026-10-19T08:30:00.123Z`, milisegundos: `expiresAt` y las fechas del fichero los conservan),
    /// `Data` en base64 y claves ordenadas (salida estable).
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        encoder.dataEncodingStrategy = .base64
        return encoder
    }

    /// El decodificador del contrato: lee lo que escribe `makeEncoder()`, y también fechas ISO 8601 sin fracciones.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Fecha ISO 8601 no válida: \(string)")
        }
        decoder.dataDecodingStrategy = .base64
        return decoder
    }
}
