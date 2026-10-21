import Foundation
import PDFKit

extension DocumentExtractor {
    func extractPDF(_ url: URL) throws -> ExtractedDocument {
        guard let document = PDFDocument(url: url) else { throw ExtractionError.unreadable("pdf") }
        if document.isLocked { throw ExtractionError.encrypted }
        guard document.pageCount > 0 else { throw ExtractionError.unreadable("pdf without pages") }

        let pages = (0..<min(limits.maxPages, document.pageCount)).compactMap { document.page(at: $0) }
        var texts = pages.map { $0.string ?? "" }
        var method = ExtractionMethod.textLayer
        if averageUsefulCharacters(texts) < limits.minUsefulCharactersPerPage {
            let recognized = try pages.map { page -> String in
                guard let image = ImageSupport.render(page, maxPixels: 2400) else { return "" }
                return try recognizer.recognizeText(in: image)
            }
            if averageUsefulCharacters(recognized) > averageUsefulCharacters(texts) {
                texts = recognized
                method = .ocr
            }
        }
        let needsImage = averageUsefulCharacters(texts) < limits.minUsefulCharactersPerPage
        let images = needsImage && limits.includeImages
            ? pages.prefix(limits.imagePages).compactMap {
                ImageSupport.render($0, maxPixels: limits.imageMaxPixels).flatMap(ImageSupport.jpegData)
            }
            : []
        return ExtractedDocument(text: Self.joinPages(texts, limit: limits.maxCharacters),
                                 pageCount: document.pageCount, method: method, needsImage: needsImage, images: images)
    }

    static func joinPages(_ texts: [String], limit: Int) -> String {
        tidy(texts.enumerated().map { "[page \($0.offset + 1)]\n\($0.element)" }.joined(separator: "\n\n"), limit: limit)
    }

    func averageUsefulCharacters(_ texts: [String]) -> Int {
        guard !texts.isEmpty else { return 0 }
        return texts.map(Self.usefulCharacters).reduce(0, +) / texts.count
    }
}
