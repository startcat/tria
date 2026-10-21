/// Para qué es un texto: lo que se mueve, lo hecho, las dudas, los errores, lo secundario o lo que se resalta.
public enum StyleRole: Sendable, CaseIterable {
    case accent, success, warning, danger, muted, strong
}

/// Pinta texto con la paleta de la app (spec CLI §2). Sin colores devuelve el texto tal cual.
/// Solo cambia el color del texto (y la negrita), y lo devuelve al de antes: un color y la negrita se pueden
/// combinar, pero no dos colores, uno dentro del otro.
public struct Style: Sendable, Equatable {
    public let depth: ColorDepth

    public init(_ depth: ColorDepth) { self.depth = depth }

    public static let plain = Style(.none)

    public func paint(_ text: String, _ role: StyleRole) -> String {
        guard depth != .none, !text.isEmpty else { return text }
        if role == .strong { return "\u{1B}[1m" + text + "\u{1B}[22m" }
        let (red, green, blue, index) = Self.palette(role)
        let start = depth == .trueColor ? "\u{1B}[38;2;\(red);\(green);\(blue)m" : "\u{1B}[38;5;\(index)m"
        return start + text + "\u{1B}[39m"
    }

    /// Un tono entre el token claro y el oscuro de la app, para que se lea con cualquier fondo, y su equivalente en
    /// la paleta de 256 colores.
    private static func palette(_ role: StyleRole) -> (Int, Int, Int, Int) {
        switch role {
        case .accent: return (211, 90, 49, 166)
        case .success: return (102, 145, 83, 65)
        case .warning: return (164, 124, 32, 136)
        case .danger: return (177, 80, 61, 131)
        case .muted: return (137, 120, 99, 244)
        case .strong: return (0, 0, 0, 0)
        }
    }
}
