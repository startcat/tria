import Darwin

/// Cuántos colores se pintan.
public enum ColorDepth: Sendable, Equatable {
    case none, palette256, trueColor
}

/// Columnas y filas de la ventana del terminal.
public struct TerminalSize: Sendable, Equatable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    /// El tamaño de la ventana del terminal de `fd`, o `nil` si no es un terminal.
    public static func current(fd: Int32) -> TerminalSize? {
        var size = winsize()
        guard ioctl(fd, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 else { return nil }
        return TerminalSize(columns: Int(size.ws_col), rows: Int(size.ws_row))
    }
}

/// Qué se puede hacer en este terminal (spec CLI §2): lo bonito, solo en un terminal de verdad.
public struct TerminalCapabilities: Sendable, Equatable {
    /// Colores de la salida estándar.
    public var colors: ColorDepth
    /// Colores de la salida de errores: avisos y la línea final de la animación.
    public var errorColors: ColorDepth
    /// La animación de espera, en la salida de errores.
    public var animates: Bool
    /// Preguntas de una tecla sin Intro: la entrada y la salida son un terminal.
    public var keys: Bool
    /// Tamaño de la ventana, si la salida es un terminal.
    public var size: TerminalSize?

    public init(colors: ColorDepth, errorColors: ColorDepth, animates: Bool, keys: Bool, size: TerminalSize?) {
        self.colors = colors
        self.errorColors = errorColors
        self.animates = animates
        self.keys = keys
        self.size = size
    }

    /// Texto plano, sin animaciones ni teclas sueltas: scripts, tuberías y pruebas.
    public static let plain = TerminalCapabilities(colors: .none, errorColors: .none, animates: false, keys: false, size: nil)

    /// Por debajo, la revisión es por fichas (spec CLI §6).
    public static let minimumFullScreen = TerminalSize(columns: 60, rows: 12)

    /// La revisión a pantalla completa: teclas sueltas y una ventana de 60 × 12 como mínimo.
    public var fullScreen: Bool {
        guard keys, let size else { return false }
        return size.columns >= Self.minimumFullScreen.columns && size.rows >= Self.minimumFullScreen.rows
    }

    /// Las reglas de la spec (§2), con el entorno y los terminales inyectados.
    public static func detect(environment: [String: String], stdin: Bool, stdout: Bool, stderr: Bool,
                              size: TerminalSize?) -> TerminalCapabilities {
        let dumb = environment["TERM"] == "dumb"
        let noColor = !(environment["NO_COLOR"] ?? "").isEmpty
        let forced = environment["CLICOLOR_FORCE"].map { !$0.isEmpty && $0 != "0" } ?? false
        let wide = ["truecolor", "24bit"].contains(environment["COLORTERM"]?.lowercased() ?? "")
        let depth: ColorDepth = wide ? .trueColor : .palette256
        func colors(_ terminal: Bool) -> ColorDepth {
            if noColor { return .none }
            if forced { return depth }
            return terminal && !dumb ? depth : .none
        }
        return TerminalCapabilities(colors: colors(stdout), errorColors: colors(stderr),
                                    animates: stderr && !dumb && !noColor, keys: stdin && stdout && !dumb,
                                    size: stdout ? size : nil)
    }

    /// Las de este proceso, medidas ahora: la ventana puede cambiar de tamaño mientras la IA lee.
    public static func current(environment: [String: String]) -> TerminalCapabilities {
        detect(environment: environment, stdin: isatty(STDIN_FILENO) != 0, stdout: isatty(STDOUT_FILENO) != 0,
               stderr: isatty(STDERR_FILENO) != 0, size: TerminalSize.current(fd: STDOUT_FILENO))
    }
}
