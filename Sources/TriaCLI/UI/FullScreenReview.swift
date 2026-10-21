import Darwin
import Foundation
import TriaKit

/// Lo que la revisión a pantalla completa necesita del terminal. `TTYScreen` es el de verdad; las pruebas usan uno
/// falso.
public protocol ScreenIO: AnyObject {
    /// El tamaño de ahora. Se mira en cada vuelta y, si cambia, se redibuja (spec CLI §6).
    var size: TerminalSize { get }
    /// Pantalla alternativa, modo crudo y sin cursor.
    func enter() throws
    /// Vuelta a la pantalla normal. Se puede llamar más de una vez.
    func leave()
    func draw(_ lines: [String])
    /// La siguiente tecla, o `nil` si pasan `timeout` milisegundos sin ninguna.
    func nextKey(timeout: Int32) -> KeyPress?
}

/// Cómo acaba la revisión.
enum ReviewOutcome: Equatable {
    case apply([ApprovedItem], [SortCorrection])
    case cancelled
}

/// La sesión de la revisión a pantalla completa (spec CLI §5): dibuja, lee teclas y, con `e`, sale de la pantalla
/// para editar y vuelve. Ctrl-C la cierra sin aplicar nada.
struct FullScreenReview {
    /// Cada cuánto se mira si la ventana ha cambiado de tamaño, en milisegundos.
    static let tick: Int32 = 100

    let plan: SortPlan
    let header: ReviewHeader
    let env: CLIEnvironment
    let style: Style
    /// Pregunta carpeta y nombre fuera de la pantalla completa, como en la revisión por fichas. `nil` deja el
    /// documento como estaba.
    let edit: (SortItem, Set<String>) throws -> SortEdit?

    func run(on screen: any ScreenIO) throws -> ReviewOutcome {
        var state = ReviewState(plan: plan)
        try screen.enter()
        defer { screen.leave() }
        var drawn: (state: ReviewState, size: TerminalSize)?
        while true {
            let size = screen.size
            // Solo si algo ha cambiado: medir el detalle recorre todos los documentos.
            if drawn?.state != state || drawn?.size != size {
                state.scroll(visibleRows: ReviewScreen.listRows(state, size: size, env: env))
                screen.draw(ReviewScreen.lines(state, header: header, size: size, env: env, style: style))
                drawn = (state, size)
            }
            guard let key = screen.nextKey(timeout: Self.tick) else { continue }
            switch state.handle(key) {
            case .none:
                continue
            case .apply:
                return .apply(state.approved(), state.corrections())
            case .quit:
                return .cancelled
            case .interrupt:
                throw TerminalInterrupt()
            case .edit(let item):
                // Las preguntas van en modo normal: el modo crudo no se anida (ver `RawMode`).
                screen.leave()
                let result = try edit(item, state.reservedDestinations(excluding: item.id))
                try screen.enter()
                drawn = nil
                if let result { state.applyEdit(result, to: item.id) }
            }
        }
    }
}

/// El terminal de verdad: la pantalla alternativa en la salida estándar y las teclas de la entrada. Si llega una
/// señal con la pantalla abierta, `TerminalGuard` sale de ella y devuelve el modo; si el proceso se cae, lo hace
/// `CrashRestore`. Con `kill -TSTP` (en modo crudo Ctrl-Z no es una señal), sale de ella mientras está parado y, de
/// vuelta en primer plano (`fg`; tras `bg` sigue parado), vuelve a ella y la redibuja entera.
final class TTYScreen: ScreenIO, @unchecked Sendable {
    static let enterSequence = "\u{1B}[?1049h\u{1B}[?25l"
    static let leaveSequence = "\u{1B}[?25h\u{1B}[?1049l"

    private let reader = KeyReader(fd: STDIN_FILENO)
    private var raw: RawMode?
    private var guardID: Int?
    /// Lo que también usa la cola de las señales, con su cerrojo: si la pantalla está abierta, si está apartada por
    /// Ctrl-Z y el último fotograma, para redibujarlo al volver.
    private let lock = NSLock()
    private var open = false
    private var suspended = false
    private var frame: [String] = []

    var size: TerminalSize { TerminalSize.current(fd: STDOUT_FILENO) ?? TerminalSize(columns: 80, rows: 24) }

    func enter() throws {
        guard raw == nil else { return }
        // El modo crudo ya apunta su limpieza en `TerminalGuard` y en `CrashRestore`.
        raw = try RawMode(fd: STDIN_FILENO)
        reader.discardPending()
        // Primero quien deshace y luego la pantalla alternativa: nunca queda abierta sin nadie que la cierre. Las
        // limpiezas van de la última a la primera, así que con una señal se sale de la pantalla antes de devolver el
        // modo.
        CrashRestore.alternateScreen(true)
        CrashRestore.cursorHidden(on: STDOUT_FILENO)
        guardID = TerminalGuard.shared.register({ TTYScreen.write(TTYScreen.leaveSequence) },
                                                suspension: Suspension(pause: { [weak self] in self?.pause() },
                                                                       resume: { [weak self] in self?.resume() }))
        lock.withLock {
            open = true
            suspended = false
            Self.write(Self.enterSequence)
        }
    }

    func leave() {
        guard let raw else { return }
        lock.withLock {
            open = false
            Self.write(Self.leaveSequence)
        }
        if let guardID { TerminalGuard.shared.unregister(guardID) }
        guardID = nil
        CrashRestore.alternateScreen(false)
        CrashRestore.cursorShown()
        raw.restore()
        self.raw = nil
    }

    /// Cada fotograma entero: al principio de la pantalla, cada línea borrando lo que quedaba y, al final, lo de debajo.
    /// Con la pantalla apartada por Ctrl-Z, solo se guarda.
    func draw(_ lines: [String]) {
        lock.withLock {
            frame = lines
            if !suspended { Self.write(Self.render(lines)) }
        }
    }

    /// Ctrl-Z: sale de la pantalla alternativa y enseña el cursor; el modo lo devuelve `RawMode`.
    private func pause() {
        lock.withLock {
            guard open, !suspended else { return }
            suspended = true
            Self.write(Self.leaveSequence)
        }
    }

    /// Al seguir: vuelve a la pantalla alternativa, que llega en blanco, y la redibuja entera.
    private func resume() {
        lock.withLock {
            guard open, suspended else { return }
            suspended = false
            Self.write(Self.enterSequence + Self.render(frame))
        }
    }

    private static func render(_ lines: [String]) -> String {
        "\u{1B}[H" + lines.map { $0 + "\u{1B}[K" }.joined(separator: "\r\n") + "\u{1B}[J"
    }

    func nextKey(timeout: Int32) -> KeyPress? { reader.next(timeout: timeout) }

    private static func write(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }
}
