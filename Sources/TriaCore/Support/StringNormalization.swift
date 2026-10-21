import Foundation

extension String {
    /// Forma canónica compuesta (NFC). Los nombres que escribe el modelo son NFC; los del disco
    /// pueden llegar en NFD (SMB, ficheros antiguos).
    public var nfc: String { precomposedStringWithCanonicalMapping }

    /// Ruta relativa limpia: NFC, separador "/", sin "/" inicial ni final, sin componentes vacíos ni ".".
    public var normalizedRelativePath: String {
        nfc.split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." }
            .joined(separator: "/")
    }
}
