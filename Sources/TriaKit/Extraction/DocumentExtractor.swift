import Foundation

/// Convierte un fichero en texto, siempre en local (spec §5.1). Nunca clasifica por el nombre:
/// si no puede leer, lanza un error y el documento queda pendiente.
public struct DocumentExtractor: Sendable {
    public let limits: ExtractionLimits
    public let recognizer: any TextRecognizer

    public init(limits: ExtractionLimits = .init(), recognizer: any TextRecognizer = VisionTextRecognizer()) {
        self.limits = limits
        self.recognizer = recognizer
    }

    public static let pdfExtensions: Set<String> = ["pdf"]
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp"]
    public static let richTextExtensions: Set<String> = ["doc", "docx", "rtf", "odt"]
    public static let spreadsheetExtensions: Set<String> = ["xlsx"]
    public static let plainTextExtensions: Set<String> = ["csv", "txt", "md"]
    public static var supportedExtensions: Set<String> {
        pdfExtensions.union(imageExtensions).union(richTextExtensions).union(spreadsheetExtensions).union(plainTextExtensions)
    }

    public func extract(_ url: URL) throws -> ExtractedDocument {
        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else { throw ExtractionError.unsupportedFormat(ext) }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else { throw ExtractionError.unreadable("empty file") }

        if Self.pdfExtensions.contains(ext) { return try extractPDF(url) }
        if Self.imageExtensions.contains(ext) { return try extractImage(url) }
        if Self.richTextExtensions.contains(ext) { return try extractRichText(url) }
        if Self.spreadsheetExtensions.contains(ext) { return try extractSpreadsheet(url) }
        return try extractPlainText(url)
    }

    public static func usefulCharacters(_ text: String) -> Int {
        text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }

    public static func tidy(_ text: String, limit: Int) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(limit))
    }
}
