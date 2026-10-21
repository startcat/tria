import Foundation

public enum ExtractionMethod: String, Codable, Sendable {
    case textLayer = "text_layer"
    case ocr
    case converted
    case spreadsheet
    case plainText = "plain_text"
}

public struct ExtractedDocument: Sendable, Equatable {
    public var text: String
    public var pageCount: Int?
    public var method: ExtractionMethod
    /// No hay texto suficiente ni con OCR: se enviarán imágenes de página (spec §6.3, paso 2).
    public var needsImage: Bool
    /// JPEG de las primeras páginas, solo si `needsImage`.
    public var images: [Data]

    public init(text: String, pageCount: Int?, method: ExtractionMethod, needsImage: Bool = false, images: [Data] = []) {
        self.text = text
        self.pageCount = pageCount
        self.method = method
        self.needsImage = needsImage
        self.images = images
    }
}
