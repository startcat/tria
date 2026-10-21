import Foundation

extension ExtractedDocument {
    /// Hay algo que leer: texto útil (sin contar las marcas de página) o imágenes de página.
    /// Si no, el documento no se clasifica (spec §3, principio 1).
    public var hasReadableContent: Bool {
        if !images.isEmpty { return true }
        let withoutMarkers = text.replacingOccurrences(of: #"\[page \d+\]"#, with: "", options: .regularExpression)
        return DocumentExtractor.usefulCharacters(withoutMarkers) > 0
    }
}

public enum ExtractionError: Error, Equatable, Sendable {
    case unsupportedFormat(String)
    case encrypted
    case unreadable(String)
}

public struct ExtractionLimits: Sendable, Equatable {
    public var maxPages: Int
    public var maxCharacters: Int
    public var minUsefulCharactersPerPage: Int
    public var imagePages: Int
    public var imageMaxPixels: Int
    public var includeImages: Bool

    public init(maxPages: Int = 3, maxCharacters: Int = 12_000, minUsefulCharactersPerPage: Int = 100,
                imagePages: Int = 2, imageMaxPixels: Int = 1568, includeImages: Bool = true) {
        self.maxPages = maxPages
        self.maxCharacters = maxCharacters
        self.minUsefulCharactersPerPage = minUsefulCharactersPerPage
        self.imagePages = imagePages
        self.imageMaxPixels = imageMaxPixels
        self.includeImages = includeImages
    }
}
