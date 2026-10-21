import Foundation

public enum FilenameSanitizer {
    public static let maxBytes = 255

    private static let knownExtensions: Set<String> = [
        "pdf", "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp",
        "doc", "docx", "rtf", "odt", "xlsx", "xls", "csv", "txt", "md",
    ]

    /// El nombre tiene una extensión de documento conocida ("Factura.pdf").
    static func hasDocumentExtension(_ name: String) -> Bool {
        knownExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Limpia el nombre propuesto y fuerza la extensión original tal cual (spec §6.5, invariante 5).
    public static func sanitize(_ proposed: String, originalFilename: String) -> String? {
        let originalExtension = (originalFilename as NSString).pathExtension
        var name = proposed.nfc
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        name = String(String.UnicodeScalarView(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") || name.hasPrefix(" ") { name.removeFirst() }

        let proposedExtension = (name as NSString).pathExtension
        if !proposedExtension.isEmpty,
           proposedExtension.lowercased() == originalExtension.lowercased()
            || knownExtensions.contains(proposedExtension.lowercased()) {
            name = (name as NSString).deletingPathExtension
        }
        var base = name.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        guard !base.isEmpty else { return nil }

        let suffix = originalExtension.isEmpty ? "" : ".\(originalExtension)"
        while (base + suffix).utf8.count > maxBytes { base.removeLast() }
        return base + suffix
    }
}
