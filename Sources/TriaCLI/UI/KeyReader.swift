import Darwin
import Foundation

/// Una tecla suelta (spec CLI §3, `KeyReader`).
public enum KeyPress: Equatable, Sendable {
    case up, down, left, right, enter, space, escape, backspace
    /// Ctrl-C: en modo crudo no llega como señal sino como tecla.
    case interrupt
    /// La entrada se ha acabado: Ctrl-D o el terminal se ha cerrado.
    case end
    case character(Character)
}

/// El descriptor no es un terminal: no hay modo crudo.
enum TerminalError: Error, Equatable {
    case notATerminal
}

/// Traduce los bytes del terminal a teclas, como función pura. Lo que queda a medias (media flecha, media letra) se
/// devuelve en `rest` para la lectura siguiente.
enum KeyDecoder {
    /// `atEnd`: no va a llegar nada más ahora. Un Esc suelto es la tecla Esc, y lo que quede a medias se descarta.
    static func decode(_ bytes: [UInt8], atEnd: Bool = false) -> (keys: [KeyPress], rest: [UInt8]) {
        var keys: [KeyPress] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case 0x03:
                keys.append(.interrupt)
                index += 1
            case 0x04:
                keys.append(.end)
                index += 1
            case 0x0D, 0x0A:
                keys.append(.enter)
                index += 1
            case 0x20:
                keys.append(.space)
                index += 1
            case 0x7F, 0x08:
                keys.append(.backspace)
                index += 1
            case 0x1B:
                guard index + 1 < bytes.count else {
                    if atEnd {
                        keys.append(.escape)
                        index += 1
                        continue
                    }
                    return (keys, Array(bytes[index...]))
                }
                let introducer = bytes[index + 1]
                guard introducer == UInt8(ascii: "[") || introducer == UInt8(ascii: "O") else {
                    keys.append(.escape)   // Esc seguido de otra tecla: las dos cuentan
                    index += 1
                    continue
                }
                // CSI («\e[1;5A», «\e[3~») o SS3 («\eOC», un solo byte final). Un byte fuera de lo esperado corta la
                // secuencia: cuenta como Esc y se sigue leyendo desde él, sin tragarse una tecla como Ctrl-C.
                let isCSI = introducer == UInt8(ascii: "[")
                var end = index + 2
                var malformed = false
                if isCSI {
                    while end < bytes.count, (0x20...0x3F).contains(bytes[end]) { end += 1 }
                }
                if end < bytes.count, !(0x40...0x7E).contains(bytes[end]) { malformed = true }
                if malformed {
                    keys.append(.escape)
                    index = end
                    continue
                }
                guard end < bytes.count else {
                    if atEnd {
                        keys.append(.escape)
                        index += 1
                        continue
                    }
                    return (keys, Array(bytes[index...]))
                }
                switch bytes[end] {
                case UInt8(ascii: "A"): keys.append(.up)
                case UInt8(ascii: "B"): keys.append(.down)
                case UInt8(ascii: "C"): keys.append(.right)
                case UInt8(ascii: "D"): keys.append(.left)
                default: break   // F1, Supr…: no se usan
                }
                index = end + 1
            case 0x00..<0x20:
                index += 1   // otros controles: no se usan
            default:
                let length = byte < 0x80 ? 1 : byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
                let available = min(length, bytes.count - index)
                // Cada byte de continuación ha de ser 10xxxxxx; si no, solo se descarta el byte inicial.
                guard bytes[(index + 1)..<(index + available)].allSatisfy({ (0x80...0xBF).contains($0) }) else {
                    index += 1
                    continue
                }
                guard available == length else {
                    return atEnd ? (keys, []) : (keys, Array(bytes[index...]))
                }
                if let text = String(bytes: bytes[index..<(index + length)], encoding: .utf8), let character = text.first {
                    keys.append(.character(character))
                }
                index += length
            }
        }
        return (keys, [])
    }
}

/// Lee teclas de un descriptor en modo crudo. Espera con `poll`, con límite, para que quien lo usa pueda redibujar
/// entre tecla y tecla.
final class KeyReader {
    /// Cuánto se espera al resto de una secuencia: una flecha llega en tres bytes y un Esc solo, en uno.
    static let escapeWait: Int32 = 30

    private let fd: Int32
    private var buffer: [UInt8] = []
    private var queued: [KeyPress] = []

    init(fd: Int32) { self.fd = fd }

    /// La siguiente tecla, o `nil` si pasan `timeout` milisegundos sin ninguna (-1: sin límite).
    func next(timeout: Int32) -> KeyPress? {
        let start = DispatchTime.now().uptimeNanoseconds
        // Lo que queda del límite; con un byte suelto descartado hay que volver a esperar, no rendirse.
        func remaining() -> Int32 {
            guard timeout >= 0 else { return -1 }
            let elapsed = Int64((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            return Int32(max(0, Int64(timeout) - elapsed))
        }
        while queued.isEmpty {
            if buffer.isEmpty {
                guard wait(remaining()) else { return nil }
                guard readAvailable() else { return .end }
                decode(atEnd: false)
            } else if wait(Self.escapeWait), readAvailable() {
                decode(atEnd: false)
            } else {
                decode(atEnd: true)
                if queued.isEmpty, timeout >= 0, remaining() == 0 { return nil }
            }
        }
        return queued.removeFirst()
    }

    /// Olvida lo leído y aún no entregado: al volver a la pantalla completa después de editar.
    func discardPending() {
        buffer.removeAll()
        queued.removeAll()
    }

    private func decode(atEnd: Bool) {
        let result = KeyDecoder.decode(buffer, atEnd: atEnd)
        queued += result.keys
        buffer = result.rest
    }

    private func wait(_ timeout: Int32) -> Bool {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        while true {
            let ready = poll(&descriptor, 1, timeout)
            if ready < 0 && errno == EINTR { continue }   // una señal por medio: se sigue esperando
            return ready > 0
        }
    }

    private func readAvailable() -> Bool {
        var chunk = [UInt8](repeating: 0, count: 64)
        let count = read(fd, &chunk, chunk.count)
        guard count > 0 else { return false }
        buffer += chunk[0..<count]
        return true
    }
}

/// Modo crudo: sin eco, sin esperar a Intro y con Ctrl-C como una tecla más. Siempre se restaura (spec CLI §2):
/// - al acabar, con `restore()` o al soltarlo;
/// - con una señal, por `TerminalGuard`;
/// - si el proceso se cae, por `CrashRestore`.
///
/// No se anida: `CrashRestore` guarda un único modo, así que un segundo `RawMode` mientras hay otro activo perdería el
/// original en una caída.
final class RawMode: @unchecked Sendable {
    let fd: Int32
    private let saved: termios
    private let raw: termios
    private let terminalGuard: TerminalGuard
    private let lock = NSLock()
    private var active = true
    private var guardID = 0

    /// Entra en modo crudo y descarta lo que se tecleó antes: un Intro mientras la IA leía no puede aplicar nada.
    init(fd: Int32, terminalGuard: TerminalGuard = .shared) throws {
        var original = termios()
        guard tcgetattr(fd, &original) == 0 else { throw TerminalError.notATerminal }
        var raw = original
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
        withUnsafeMutableBytes(of: &raw.c_cc) { characters in
            characters[Int(VMIN)] = 1
            characters[Int(VTIME)] = 0
        }
        self.fd = fd
        self.saved = original
        self.raw = raw
        self.terminalGuard = terminalGuard
        CrashRestore.saveMode(original, of: fd)
        // TCSANOW + tcflush en vez de TCSAFLUSH: este espera a que se vacíe la salida, y si el eco de lo tecleado antes
        // no lo lee nadie (un pseudoterminal, un terminal colgado) se quedaría esperando para siempre.
        guard tcsetattr(fd, TCSANOW, &raw) == 0 else {
            CrashRestore.forgetMode()
            throw TerminalError.notATerminal
        }
        tcflush(fd, TCIFLUSH)
        // Con Ctrl-Z, el shell recupera su modo mientras el proceso está parado, y al seguir vuelve el crudo.
        guardID = terminalGuard.register({ [weak self] in self?.restore() },
                                         suspension: Suspension(pause: { [weak self] in self?.apply(\.saved) },
                                                                resume: { [weak self] in self?.apply(\.raw) }))
    }

    deinit { restore() }

    /// Vuelve al modo de antes. Solo cuenta la primera vez.
    func restore() {
        let first = lock.withLock { () -> Bool in
            defer { active = false }
            return active
        }
        guard first else { return }
        var original = saved
        _ = tcsetattr(fd, TCSANOW, &original)
        CrashRestore.forgetMode()
        terminalGuard.unregister(guardID)
    }

    /// Pone uno de los dos modos, si aún no se ha restaurado.
    private func apply(_ mode: KeyPath<RawMode, termios>) {
        lock.withLock {
            guard active else { return }
            var value = self[keyPath: mode]
            _ = tcsetattr(fd, TCSANOW, &value)
        }
    }

    /// `body` en modo crudo; al salir, por donde sea, se restaura.
    static func run<T>(fd: Int32, terminalGuard: TerminalGuard = .shared, _ body: () throws -> T) throws -> T {
        let mode = try RawMode(fd: fd, terminalGuard: terminalGuard)
        defer { mode.restore() }
        return try body()
    }
}
