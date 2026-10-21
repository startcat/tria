import Darwin
import Foundation
import os

/// Lo que hace Ctrl-Z con algo que está a la vista: `pause` lo quita antes de que el proceso se pare, para que el shell
/// quede como estaba, y `resume` lo vuelve a poner al seguir (`fg`).
struct Suspension: Sendable {
    let pause: @Sendable () -> Void
    let resume: @Sendable () -> Void
}

/// Lo que hay que dejar como estaba en el terminal pase lo que pase: Ctrl-C, `kill` o una salida de golpe
/// (spec CLI §2, «Ctrl-C deja el terminal como estaba»). La animación, el modo crudo y la pantalla completa apuntan
/// aquí cómo deshacerse y se borran al acabar bien. También cómo apartarse mientras el proceso está parado (Ctrl-Z).
final class TerminalGuard: @unchecked Sendable {
    /// El del proceso: atrapa Ctrl-C (sale con 130), `SIGTERM` (143), Ctrl-Z y la salida del proceso.
    static let shared = TerminalGuard(installsHandlers: true)

    private let lock = NSLock()
    private let installsHandlers: Bool
    private var cleanups: [(id: Int, run: @Sendable () -> Void, suspension: Suspension?)] = []
    private var nextID = 0
    private var installed = false
    private var sources: [any DispatchSourceSignal] = []
    /// Se acaba de parar: la próxima entrega de `SIGTSTP` es la de esa misma parada (ver `stopRequested`).
    private var justStopped = false

    /// Cómo muere el proceso tras limpiar. Por defecto, por la propia señal con su acción por defecto: así un bucle de
    /// bash también se para (solo se para si el hijo muere por SIGINT). El shell sigue viendo 130 o 143.
    private let die: @Sendable (Int32) -> Void

    /// Cómo se para el proceso con Ctrl-Z. Vuelve cuando sigue y, con `untilForeground` (hay algo apartado que volver a
    /// poner), cuando además está en primer plano.
    private let stop: @Sendable (_ untilForeground: Bool) -> Void

    /// Las pruebas usan uno propio, sin manejadores, con un `die` que no mata el proceso y un `stop` que no lo para.
    init(installsHandlers: Bool = false, die: @escaping @Sendable (Int32) -> Void = TerminalGuard.dieBySignal,
         stop: @escaping @Sendable (_ untilForeground: Bool) -> Void = TerminalGuard.stopBySignal) {
        self.installsHandlers = installsHandlers
        self.die = die
        self.stop = stop
    }

    static let dieBySignal: @Sendable (Int32) -> Void = { signo in
        signal(signo, SIG_DFL)
        var only = sigset_t()
        sigemptyset(&only)
        sigaddset(&only, signo)
        pthread_sigmask(SIG_UNBLOCK, &only, nil)
        raise(signo)
        // Desde un hilo de Dispatch (la cola de las señales, o una tarea de Swift: Ctrl-C en la revisión a pantalla
        // completa), `raise` no puede mandar la señal al hilo y la manda al proceso, que la recibe un momento después en
        // otro hilo. Se le da tiempo a llegar: saliendo enseguida, a veces el proceso acababa con 130 sin morir por ella,
        // y un bucle de bash no se paraba.
        for _ in 0..<100 { usleep(10_000) }
        exit(128 + signo)   // por si la señal estuviera bloqueada en todos los hilos
    }

    /// Se para con la acción por defecto de `SIGTSTP`, como si no se atrapara (el shell lo ve parado como siempre), y
    /// vuelve de `raise` cuando el proceso sigue con `SIGCONT` (`fg`, `bg` o `kill -CONT`). Con `untilForeground`,
    /// espera además a estar en primer plano (ver `waitForForeground`). Todo ello, `interruptible`.
    static let stopBySignal: @Sendable (Bool) -> Void = { untilForeground in
        interruptible {
            signal(SIGTSTP, SIG_DFL)
            raise(SIGTSTP)
            signal(SIGTSTP, SIG_IGN)
            if untilForeground { waitForForeground(on: [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO]) }
        }
    }

    /// `body` con Ctrl-C y `SIGTERM` a su acción por defecto; después se vuelven a ignorar, para que las atienda la cola
    /// de las señales, que limpia antes de salir. Mientras el proceso está parado o espera al primer plano, esa cola está
    /// ocupada en `suspend` y no podría atenderlas: un `kill %1` (SIGTERM y SIGCONT) no lo acabaría. Lo que se ve ya está
    /// apartado, como lo quiere el shell, así que basta con morir por la señal: el shell ve 130 o 143, como siempre.
    static func interruptible(_ body: () -> Void) {
        let interrupts = [SIGINT, SIGTERM]
        for signo in interrupts { signal(signo, SIG_DFL) }
        defer { for signo in interrupts { signal(signo, SIG_IGN) } }
        body()
    }

    /// Espera a que el proceso esté en primer plano en su terminal (el primero de `fds` que lo sea). Tras `bg` o un
    /// `kill -CONT` sigue en segundo plano, y volver al modo crudo, a la pantalla alternativa o a la animación pintaría
    /// encima del shell. Se espera como espera cualquier programa: cambiar el modo del terminal (aquí, por el mismo que
    /// tiene) desde segundo plano para el proceso con `SIGTTOU` hasta el `fg`, y entonces sale bien.
    ///
    /// Los hilos de Dispatch tienen las señales bloqueadas, y con `SIGTTOU` bloqueada el kernel deja cambiar el modo
    /// desde segundo plano sin pararlo: por eso se desbloquea en este hilo solo mientras se espera. En un grupo de
    /// procesos huérfano (sin shell que lo pueda seguir) el kernel no lo para, sino que da `EIO`, y se sigue.
    static func waitForForeground(on fds: [Int32]) {
        guard let fd = fds.first(where: { isatty($0) == 1 }) else { return }
        var stopSignal = sigset_t()
        sigemptyset(&stopSignal)
        sigaddset(&stopSignal, SIGTTOU)
        var previous = sigset_t()
        pthread_sigmask(SIG_UNBLOCK, &stopSignal, &previous)
        defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
        var mode = termios()
        // Se lee cada vez: mientras estaba parado, el shell ha podido cambiar el modo. Al seguir, `EINTR`.
        repeat {
            guard tcgetattr(fd, &mode) == 0 else { return }
        } while tcsetattr(fd, TCSANOW, &mode) == -1 && errno == EINTR
    }

    /// Deshace lo pendiente y muere por `signo` (Ctrl-C, `SIGTERM`).
    func interrupt(_ signo: Int32) {
        runAll()
        die(signo)
    }

    /// Ctrl-Z: aparta lo que está a la vista (de lo último a lo primero, como las limpiezas) y se para. Al seguir, si
    /// había algo apartado, espera a estar en primer plano (tras `bg` sigue parado hasta el `fg`) y lo vuelve a poner
    /// (de lo primero a lo último). Las limpiezas siguen apuntadas.
    func suspend() {
        let active = lock.withLock { cleanups.compactMap(\.suspension) }
        for suspension in active.reversed() { suspension.pause() }
        stop(!active.isEmpty)
        for suspension in active { suspension.resume() }
        lock.withLock { justStopped = true }
    }

    /// `SIGTSTP` llegado por Dispatch (una o varias juntas). Mientras se atiende una, las demás esperan en la fuente y
    /// llegan juntas en la entrega siguiente: la que el proceso se manda en `suspend` para pararse (la fuente también la
    /// ve, aunque el kernel la descarte) y las que llegaron mientras se paraba o estaba parado, como un segundo
    /// `kill -TSTP`. Esa entrega no lo vuelve a parar: todas son la misma parada, y basta un `fg`.
    func stopRequested() {
        let sameStop = lock.withLock { () -> Bool in
            defer { justStopped = false }
            return justStopped
        }
        if !sameStop { suspend() }
    }

    /// Apunta una limpieza (y, si hace falta, qué hacer con Ctrl-Z) y devuelve su id, para quitarla cuando ya no haga
    /// falta.
    @discardableResult
    func register(_ cleanup: @escaping @Sendable () -> Void, suspension: Suspension? = nil) -> Int {
        let id = lock.withLock { () -> Int in
            nextID += 1
            cleanups.append((nextID, cleanup, suspension))
            return nextID
        }
        if installsHandlers { installIfNeeded() }
        return id
    }

    func unregister(_ id: Int) {
        lock.withLock { cleanups.removeAll { $0.id == id } }
    }

    /// Hace las limpiezas pendientes, de la última a la primera, una sola vez cada una.
    func runAll() {
        let pending = lock.withLock { () -> [@Sendable () -> Void] in
            defer { cleanups.removeAll() }
            return cleanups.reversed().map { $0.run }
        }
        for cleanup in pending { cleanup() }
    }

    private func installIfNeeded() {
        let first = lock.withLock { () -> Bool in
            defer { installed = true }
            return !installed
        }
        guard first else { return }
        CrashRestore.install()
        atexit { TerminalGuard.shared.runAll() }
        // Las señales se atienden en una cola de Dispatch, fuera del manejador: ahí sí se puede escribir y salir. Una
        // sola cola, en serie: un Ctrl-C justo después de `fg` espera a que se haya vuelto a poner todo.
        let queue = DispatchQueue(label: "cat.start.tria.signals")
        for signo in [SIGINT, SIGTERM, SIGTSTP] {
            signal(signo, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signo, queue: queue)
            if signo == SIGTSTP {
                source.setEventHandler { TerminalGuard.shared.stopRequested() }
            } else {
                source.setEventHandler { TerminalGuard.shared.interrupt(signo) }
            }
            source.resume()
            lock.withLock { sources.append(source) }
        }
    }
}

/// El último recurso si el proceso se cae (un `fatalError`, `SIGSEGV`…): devuelve el modo del terminal, sale de la
/// pantalla alternativa y enseña el cursor. El manejador solo lee memoria fija y usa llamadas seguras dentro de una
/// señal (`tcsetattr`, `write`).
enum CrashRestore {
    private struct State {
        var fd: Int32 = -1
        var saved = termios()
        var hasSaved = false
        var cursorFD: Int32 = -1
        var alternateScreen = false
    }

    // Sin comprobación de exclusividad: el manejador lo lee dentro de una señal, donde no puede haber `swift_beginAccess`.
    @exclusivity(unchecked) nonisolated(unsafe) private static var state = State()
    private static let writers = OSAllocatedUnfairLock()

    static func saveMode(_ mode: termios, of fd: Int32) {
        writers.withLockUnchecked {
            state.fd = fd
            state.saved = mode
            state.hasSaved = true
        }
    }

    static func forgetMode() { writers.withLockUnchecked { state.hasSaved = false } }
    static func cursorHidden(on fd: Int32) { writers.withLockUnchecked { state.cursorFD = fd } }
    static func cursorShown() { writers.withLockUnchecked { state.cursorFD = -1 } }
    static func alternateScreen(_ active: Bool) { writers.withLockUnchecked { state.alternateScreen = active } }

    /// Lo que hace el manejador de las señales de error. Las pruebas lo llaman directamente.
    static func restoreNow() {
        let current = state
        if current.hasSaved {
            var mode = current.saved
            _ = tcsetattr(current.fd, TCSANOW, &mode)
        }
        if current.alternateScreen { write(STDOUT_FILENO, "\u{1B}[?1049l") }
        if current.cursorFD >= 0 { write(current.cursorFD, "\u{1B}[?25h") }
    }

    static func install() {
        _ = state   // se inicializa antes de que la pueda leer una señal
        var action = sigaction()
        action.__sigaction_u.__sa_handler = { signo in
            CrashRestore.restoreNow()
            // Darwin no resetea SIGILL ni SIGTRAP con SA_RESETHAND (un trap de Swift es uno de los dos): se vuelve a la
            // acción por defecto a mano, o la señal se reentregaría sin fin.
            signal(signo, SIG_DFL)
            raise(signo)
        }
        action.sa_flags = SA_RESETHAND
        for signo in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE, SIGQUIT] { sigaction(signo, &action, nil) }
    }

    private static func write(_ fd: Int32, _ text: StaticString) {
        _ = Darwin.write(fd, text.utf8Start, text.utf8CodeUnitCount)
    }
}
