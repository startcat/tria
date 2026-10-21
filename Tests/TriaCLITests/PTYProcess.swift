import Darwin
import Foundation
import TriaCLI

/// Un proceso en un pseudoterminal propio, como si corriera en Terminal.app pero sin ventana: es el líder de una sesión
/// nueva, el pseudoterminal es su terminal y está en primer plano. Así ⌃C le llega como `SIGINT` (o como tecla, en
/// modo crudo) y cambiar el tamaño, como `SIGWINCH`. Lo que escribe se queda en `text`.
///
/// Se lanza con `forkpty`: `posix_spawn` no puede darle el pseudoterminal como terminal de su sesión (en macOS hace
/// falta `TIOCSCTTY` en el hijo), y sin él ⌃C no sería una señal. Entre `fork` y `execve` el hijo solo hace llamadas al
/// sistema, con todo preparado antes: las pruebas corren en varios hilos.
///
/// El modo del terminal se lee por el lado maestro, que sigue respondiendo cuando el proceso ha acabado.
final class PTYProcess {
    let pid: pid_t
    /// El modo del terminal antes de que el proceso haga nada.
    let initialMode: termios
    private let master: Int32
    private var bytes = Data()
    private var status: Int32?

    struct Failure: Error, CustomStringConvertible {
        let what: String
        let code: Int32
        var description: String { "\(what): \(String(cString: strerror(code)))" }
    }

    init(executable: URL, arguments: [String], environment: [String: String], size: TerminalSize) throws {
        let argv = Self.cStrings([executable.path] + arguments)
        let envp = Self.cStrings(environment.map { "\($0.key)=\($0.value)" })
        defer {
            for list in [argv, envp] {
                var index = 0
                while let pointer = list[index] {
                    free(pointer)
                    index += 1
                }
                list.deallocate()
            }
        }
        var none = sigset_t()
        sigemptyset(&none)
        // Lo que el hijo deja como lo pondría un shell: sin señales bloqueadas ni ignoradas por las pruebas.
        let signals = [SIGINT, SIGTERM, SIGQUIT, SIGTSTP, SIGTTIN, SIGTTOU, SIGWINCH, SIGPIPE, SIGHUP]
        let descriptors = min(getdtablesize(), 65_536)
        var window = winsize(ws_row: UInt16(size.rows), ws_col: UInt16(size.columns), ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = -1
        let pid = forkpty(&master, nil, nil, &window)
        if pid == 0 {
            // El hijo: el pseudoterminal ya es su terminal y sus 0, 1 y 2.
            sigprocmask(SIG_SETMASK, &none, nil)
            for signo in signals { signal(signo, SIG_DFL) }
            var fd: Int32 = 3
            while fd < descriptors {
                close(fd)
                fd += 1
            }
            execve(argv[0], argv, envp)
            _exit(127)
        }
        guard pid > 0 else { throw Failure(what: "forkpty", code: errno) }
        var mode = termios()
        _ = tcgetattr(master, &mode)
        self.pid = pid
        self.master = master
        self.initialMode = mode
    }

    /// Una lista de C acabada en `nil`, preparada antes de `fork`.
    private static func cStrings(_ strings: [String]) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
        let list = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: strings.count + 1)
        for (index, string) in strings.enumerated() { list[index] = strdup(string) }
        list[strings.count] = nil
        return list
    }

    deinit {
        if status == nil {
            kill(pid, SIGKILL)
            var raw: Int32 = 0
            waitpid(pid, &raw, 0)
        }
        close(master)
    }

    /// Todo lo que ha escrito el proceso hasta ahora, con las secuencias de escape.
    var text: String { String(decoding: bytes, as: UTF8.self) }

    /// El modo del terminal ahora.
    var mode: termios {
        var value = termios()
        _ = tcgetattr(master, &value)
        return value
    }

    /// Lo que se teclea. ⌃C es "\u{03}".
    func send(_ keys: String) {
        let data = Array(keys.utf8)
        _ = data.withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
    }

    /// Cambia el tamaño de la ventana, como al arrastrar su esquina: `TIOCSWINSZ`, y el núcleo avisa con `SIGWINCH` al
    /// grupo en primer plano. Se manda también al proceso, por si acaso: dos avisos no cambian nada.
    func resize(to size: TerminalSize) {
        var window = winsize(ws_row: UInt16(size.rows), ws_col: UInt16(size.columns), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &window)
        kill(pid, SIGWINCH)
    }

    /// Lee lo que va escribiendo hasta que `condition` se cumple sobre todo lo escrito, o hasta `timeout`.
    func waitFor(timeout: Duration = .seconds(20), _ condition: (String) -> Bool) -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(text) {
            guard clock.now < deadline else { return false }
            if !readAvailable(waiting: 50), status != nil { return condition(text) }
        }
        return true
    }

    /// Espera a que acabe y lee lo que quede. El estado de `waitpid`, o `nil` si no acaba a tiempo.
    func waitForExit(timeout: Duration = .seconds(20)) -> Int32? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while status == nil, clock.now < deadline { _ = readAvailable(waiting: 50) }
        while readAvailable(waiting: 50) {}
        return status
    }

    /// Ha muerto por `signal`: el shell ve 128 + `signal` (130 con ⌃C).
    static func killed(by signal: Int32, _ status: Int32) -> Bool { status & 0x7F == signal }

    /// Ha acabado él solo, con `code`.
    static func exited(with code: Int32, _ status: Int32) -> Bool { status & 0x7F == 0 && (status >> 8) & 0xFF == code }

    /// El mismo modo: banderas y caracteres de control.
    static func sameMode(_ lhs: termios, _ rhs: termios) -> Bool {
        lhs.c_iflag == rhs.c_iflag && lhs.c_oflag == rhs.c_oflag && lhs.c_cflag == rhs.c_cflag
            && lhs.c_lflag == rhs.c_lflag
            && withUnsafeBytes(of: lhs.c_cc) { Array($0) } == withUnsafeBytes(of: rhs.c_cc) { Array($0) }
    }

    /// Lee lo que haya, esperando hasta `waiting` milisegundos. `true` si ha leído algo. De paso, mira si ha acabado.
    private func readAvailable(waiting milliseconds: Int32) -> Bool {
        var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
        var read = false
        if poll(&descriptor, 1, milliseconds) > 0, descriptor.revents & Int16(POLLIN) != 0 {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(master, &chunk, chunk.count)
            if count > 0 {
                bytes.append(contentsOf: chunk[0..<count])
                read = true
            }
        }
        if status == nil {
            var raw: Int32 = 0
            if waitpid(pid, &raw, WNOHANG) == pid { status = raw }
        }
        return read
    }
}

/// El `tria` de Debug que prueban las pruebas del pseudoterminal: `.build/debug/tria` de este paquete, que `swift test`
/// compila antes de correr las pruebas. Con otra carpeta de compilación (`--scratch-path`) no está ahí: la prueba falla
/// y lo dice.
enum TriaBinary {
    static let url = URL(fileURLWithPath: #filePath)   // …/Tests/TriaCLITests/PTYProcess.swift
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/debug/tria")

    static var isBuilt: Bool { FileManager.default.isExecutableFile(atPath: url.path) }
}
