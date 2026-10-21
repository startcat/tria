import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ImageSupport {
    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func resized(_ image: CGImage, maxPixels: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixels else { return image }
        let scale = Double(maxPixels) / Double(longest)
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = bitmap(width: width, height: height) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    static func render(_ page: PDFPage, maxPixels: Int) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = Double(maxPixels) / Double(max(bounds.width, bounds.height))
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard let context = bitmap(width: width, height: height) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

extension DocumentExtractor {
    func extractImage(_ url: URL) throws -> ExtractedDocument {
        guard let image = ImageSupport.loadImage(url) else { throw ExtractionError.unreadable(url.pathExtension.lowercased()) }
        let text = try recognizer.recognizeText(in: ImageSupport.resized(image, maxPixels: 2400))
        let needsImage = Self.usefulCharacters(text) < limits.minUsefulCharactersPerPage
        let images = needsImage && limits.includeImages
            ? [ImageSupport.jpegData(ImageSupport.resized(image, maxPixels: limits.imageMaxPixels))].compactMap { $0 }
            : []
        return ExtractedDocument(text: Self.tidy(text, limit: limits.maxCharacters), pageCount: 1,
                                 method: .ocr, needsImage: needsImage, images: images)
    }
}
