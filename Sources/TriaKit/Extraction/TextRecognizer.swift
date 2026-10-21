import CoreGraphics
import Vision

public protocol TextRecognizer: Sendable {
    func recognizeText(in image: CGImage) throws -> String
}

/// OCR local con Vision. Vision no admite catalán en macOS 27: solo se pide `ca-ES` si el sistema lo ofrece.
public struct VisionTextRecognizer: TextRecognizer {
    public static let preferredLanguages = ["es-ES", "ca-ES", "en-US"]

    public init() {}

    public static func languages(supported: [String]) -> [String] {
        preferredLanguages.filter(supported.contains)
    }

    public func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let languages = Self.languages(supported: (try? request.supportedRecognitionLanguages()) ?? [])
        if !languages.isEmpty { request.recognitionLanguages = languages }
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
