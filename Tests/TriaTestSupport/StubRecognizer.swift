import CoreGraphics
import TriaKit

public struct StubRecognizer: TextRecognizer {
    public let text: String
    public init(text: String) { self.text = text }
    public func recognizeText(in image: CGImage) throws -> String { text }
}
