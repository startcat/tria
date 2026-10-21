import Darwin
import Foundation

/// Ctrl-C en una pregunta de una tecla o en la pantalla completa: el comando acaba con 130 sin mover nada.
public struct TerminalInterrupt: Error, Equatable {
    public init() {}
}

public protocol Terminal: Sendable {
    var isInteractive: Bool { get }
    /// Qué se puede pintar, animar y preguntar aquí (spec CLI §2).
    var capabilities: TerminalCapabilities { get }
    func write(_ text: String)
    func error(_ text: String)
    func ask(_ prompt: String) -> String?
    func askSecret(_ prompt: String) -> String?
    /// Olvida un fin de entrada anterior antes de una pregunta de línea. En macOS `stdin` lo recuerda: tras un Ctrl-D,
    /// cada `ask` siguiente devolvería `nil` sin esperar.
    func resetEndOfInput()
    /// Empieza la animación de espera, en la salida de errores.
    func startActivity(_ title: String) -> any Activity
    /// Una pregunta de una tecla: en un terminal, sin Intro. Devuelve la tecla en minúscula, "" con Intro y `nil` si
    /// se acaba la entrada. Lanza `TerminalInterrupt` con Ctrl-C.
    func readKey(_ prompt: String, allowed: Set<Character>) throws -> String?
}

public struct StandardTerminal: Terminal {
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public var isInteractive: Bool { isatty(STDIN_FILENO) != 0 }

    /// Se mide cada vez: la ventana puede cambiar de tamaño mientras la IA lee.
    public var capabilities: TerminalCapabilities { TerminalCapabilities.current(environment: environment) }

    public func write(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }

    public func error(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }

    public func ask(_ prompt: String) -> String? {
        FileHandle.standardOutput.write(Data(prompt.utf8))
        return readLine()
    }

    public func resetEndOfInput() { clearerr(stdin) }

    /// Sin eco: la key nunca aparece en pantalla.
    public func askSecret(_ prompt: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard let result = readpassphrase(prompt, &buffer, buffer.count, 0) else { return nil }
        return String(cString: result)
    }

    public func startActivity(_ title: String) -> any Activity {
        let capabilities = self.capabilities
        let output: @Sendable (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
        guard capabilities.animates else { return PlainActivity(title: title, output: output) }
        return AnimatedActivity(title: title, style: Style(capabilities.errorColors), cursorFD: STDERR_FILENO,
                                width: { TerminalSize.current(fd: STDERR_FILENO)?.columns ?? 80 }, output: output)
    }

    /// En un terminal, una tecla sin Intro (spec CLI §4); sin él, una línea como siempre. Lo que no está en
    /// `allowed` se ignora. Intro devuelve "", y Ctrl-C lanza `TerminalInterrupt` con el terminal ya restaurado.
    public func readKey(_ prompt: String, allowed: Set<Character>) throws -> String? {
        guard capabilities.keys else { return ask(prompt) }
        FileHandle.standardOutput.write(Data(prompt.utf8))
        let answer: String?
        do {
            answer = try RawMode.run(fd: STDIN_FILENO) { () throws -> String? in
                let reader = KeyReader(fd: STDIN_FILENO)
                while true {
                    switch reader.next(timeout: -1) {
                    case .interrupt?:
                        throw TerminalInterrupt()
                    case .end?, nil:
                        return nil
                    case .enter?:
                        return ""
                    case .character(let character)?:
                        let key = character.lowercased().first ?? character
                        if allowed.contains(key) { return String(key) }
                    default:
                        break
                    }
                }
            }
        } catch {
            FileHandle.standardOutput.write(Data("\n".utf8))
            throw error
        }
        // Se enseña la tecla elegida, como si se hubiera escrito.
        FileHandle.standardOutput.write(Data(((answer ?? "") + "\n").utf8))
        return answer
    }
}
