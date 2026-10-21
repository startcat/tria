import ArgumentParser
import Foundation
import TriaKit
import TriaTestSupport
@testable import TriaCLI

final class ScriptedTerminal: Terminal, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String]
    private var lines: [String] = []
    private var outputLines: [String] = []
    /// Tras un «^D», como `stdin` en macOS: las preguntas de línea devuelven `nil` hasta `resetEndOfInput()`.
    private var atEnd = false
    let isInteractive: Bool
    let capabilities: TerminalCapabilities

    init(answers: [String] = [], interactive: Bool = true, capabilities: TerminalCapabilities = .plain) {
        self.answers = answers
        self.isInteractive = interactive
        self.capabilities = capabilities
    }

    func write(_ text: String) { lock.withLock { lines.append(text); outputLines.append(text) } }
    func error(_ text: String) { lock.withLock { lines.append(text) } }
    /// "^D" es Ctrl-D en una pregunta de línea.
    func ask(_ prompt: String) -> String? {
        lock.withLock {
            lines.append(prompt)
            guard !atEnd else { return nil }
            let answer = answers.isEmpty ? nil : answers.removeFirst()
            if answer == "^D" {
                atEnd = true
                return nil
            }
            return answer
        }
    }
    func askSecret(_ prompt: String) -> String? { ask(prompt) }
    func resetEndOfInput() { lock.withLock { atEnd = false } }

    /// Las actividades quedan como líneas de la salida de errores: el título y la línea final.
    func startActivity(_ title: String) -> any Activity {
        error(title)
        return RecordedActivity { [weak self] line in self?.error(line) }
    }

    /// Las teclas se responden con las respuestas guionizadas; "^C" es Ctrl-C. En un terminal se leen del descriptor
    /// sin pasar por `stdin`, así que el fin de entrada de un «^D» no les afecta.
    func readKey(_ prompt: String, allowed: Set<Character>) throws -> String? {
        let answer = lock.withLock { () -> String? in
            lines.append(prompt)
            return answers.isEmpty ? nil : answers.removeFirst()
        }
        if answer == "^C" { throw TerminalInterrupt() }
        return answer
    }

    var transcript: String { lock.withLock { lines.joined(separator: "\n") } }
    /// Solo lo escrito en la salida estándar (sin errores ni avisos).
    var output: String { lock.withLock { outputLines.joined(separator: "\n") } }
}

/// La actividad de `ScriptedTerminal`: sin animación y con cero segundos, para que las pruebas sean deterministas.
final class RecordedActivity: Activity, @unchecked Sendable {
    private let lock = NSLock()
    private let record: @Sendable (String) -> Void
    private var finished = false

    init(record: @escaping @Sendable (String) -> Void) { self.record = record }

    var elapsedSeconds: Int { 0 }
    func update(_ text: String, progress: ActivityProgress?) {}
    func finish(_ line: String?) {
        let first = lock.withLock { () -> Bool in
            defer { finished = true }
            return !finished
        }
        if first, let line { record(line) }
    }
}

extension TerminalCapabilities {
    /// Colores de 256 en las dos salidas, sin animación ni teclas: para probar el estilo con `ScriptedTerminal`.
    static let colored = TerminalCapabilities(colors: .palette256, errorColors: .palette256, animates: false,
                                              keys: false, size: nil)
}

struct CLIHarness {
    let dir: TempDir
    let terminal: ScriptedTerminal
    let secrets: InMemorySecretStore
    let env: CLIEnvironment

    init(provider: ScriptedProvider? = nil, answers: [String] = [], interactive: Bool = true,
         key: String? = "sk-ant-test-key-123", capabilities: TerminalCapabilities = .plain,
         screen: (any ScreenIO & Sendable)? = nil) throws {
        dir = try TempDir("tria-cli")
        terminal = ScriptedTerminal(answers: answers, interactive: interactive, capabilities: capabilities)
        secrets = InMemorySecretStore(key.map { [.anthropic: $0] } ?? [:])
        let scripted = provider ?? ScriptedProvider { _ in "" }
        // Sin pantalla guionizada, una sin teclas: una prueba nunca abre el terminal de verdad.
        let fake: any ScreenIO & Sendable = screen ?? FakeScreen(keys: [])
        env = CLIEnvironment(environment: ["TRIA_LANG": "es"], currentDirectory: dir.url,
                             configURL: dir.url.appendingPathComponent(".config/tria/config.toml"),
                             secrets: secrets, terminal: terminal,
                             makeProvider: { _, _, _ in scripted }, lang: .es, makeScreen: { fake })
    }

    @discardableResult
    func run(_ arguments: [String]) async throws -> Int32 {
        try await CLIEnvironment.$current.withValue(env) {
            do {
                var command = try TriaCommand.parseAsRoot(arguments)
                if var asyncCommand = command as? AsyncParsableCommand { try await asyncCommand.run() } else { try command.run() }
                return 0
            } catch let exit as ExitCode {
                return exit.rawValue
            }
        }
    }
}

let draftJSON = """
{"inbox":"99-Pendiente","duplicates":"98-Duplicados","protected":[],"new_folders":"subfolders_only",
 "body":"# Reglas aprendidas\\n\\n## Carpetas\\n| Carpeta | Contenido |\\n|---|---|\\n| `Facturas/` | Facturas |\\n"}
"""

/// Una pantalla completa de mentira: teclas guionizadas (`nil` es una vuelta sin tecla) y tamaños que pueden cambiar.
/// Cuando se acaban las teclas, devuelve `.end`, que sale de la revisión.
final class FakeScreen: ScreenIO, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [KeyPress?]
    private var sizes: [TerminalSize]
    private var entered = false
    private var drawn: [[String]] = []
    private var log: [String] = []

    init(keys: [KeyPress?], sizes: [TerminalSize] = [TerminalSize(columns: 100, rows: 30)]) {
        self.keys = keys
        self.sizes = sizes
    }

    var frames: [[String]] { lock.withLock { drawn } }
    var events: [String] { lock.withLock { log } }

    var size: TerminalSize { lock.withLock { sizes.count > 1 ? sizes.removeFirst() : sizes[0] } }
    func enter() throws { lock.withLock { entered = true; log.append("enter") } }
    func leave() {
        lock.withLock {
            guard entered else { return }
            entered = false
            log.append("leave")
        }
    }
    func draw(_ lines: [String]) { lock.withLock { drawn.append(lines) } }
    func nextKey(timeout: Int32) -> KeyPress? { lock.withLock { keys.isEmpty ? .end : keys.removeFirst() } }
}

/// Un entorno sin efectos para pintar la ayuda en el idioma `lang`, como la vería quien tiene ese idioma.
func helpEnvironment(_ lang: Lang) -> CLIEnvironment {
    let dir = FileManager.default.temporaryDirectory
    return CLIEnvironment(environment: ["TRIA_LANG": lang.rawValue], currentDirectory: dir,
                          configURL: dir.appendingPathComponent("tria-ayuda/config.toml"),
                          secrets: InMemorySecretStore(), terminal: ScriptedTerminal(),
                          makeProvider: { _, _, _ in ScriptedProvider { _ in "" } }, lang: lang)
}
