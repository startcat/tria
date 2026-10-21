import Foundation

/// Cuánto lleva una tarea con cifra conocida: «3/9».
public struct ActivityProgress: Sendable, Equatable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// La animación de espera (spec CLI §3). Va a la salida de errores.
///
/// Mientras una actividad corre, nada más debe escribir en el terminal (ni `write` ni `error`): la animación redibuja
/// la línea y lo que se mezcle quedaría pisado.
public protocol Activity: Sendable {
    /// Cambia el texto y, si se sabe, el progreso.
    func update(_ text: String, progress: ActivityProgress?)
    /// Quita la animación y deja `line` como línea final, si la hay. Solo cuenta la primera vez.
    func finish(_ line: String?)
    /// Segundos desde que empezó.
    var elapsedSeconds: Int { get }
}

/// El dibujo de un fotograma, como función pura (spec CLI §7).
enum ActivityFrame {
    static let spinner: [Character] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    static let interval = DispatchTimeInterval.milliseconds(80)
    static let barCells = 10

    /// «⠋ scan_0012.pdf ▕███░░░░░░░▏ 3/9 · 12 s», sin pasar de `width - 1` columnas: escribir en la última
    /// columna hace saltar de línea a algunos terminales. Si no cabe, primero se recorta el texto y luego se quita la
    /// barra.
    static func render(text: String, progress: ActivityProgress?, seconds: Int, tick: Int, width: Int,
                       style: Style) -> String {
        let spin = String(spinner[((tick % spinner.count) + spinner.count) % spinner.count])
        let limit = max(0, width - 1)
        var counts = "\(seconds) s"
        var bar: (filled: String, empty: String)?
        if let progress, progress.total > 0 {
            let done = min(max(progress.done, 0), progress.total)
            let filled = done * barCells / progress.total
            bar = (String(repeating: "█", count: filled), String(repeating: "░", count: barCells - filled))
            counts = "\(done)/\(progress.total) · \(seconds) s"
        }
        // Espacio para el spinner (2), la barra (" ▕" + celdas + "▏") y las cifras (espacio + texto).
        let minimumText = 8
        if bar != nil, 2 + minimumText + barCells + 3 + 1 + TextWidth.columns(counts) > limit { bar = nil }
        let fixed = 2 + (bar == nil ? 0 : barCells + 3) + 1 + TextWidth.columns(counts)
        let shown = TextWidth.truncateMiddle(TextWidth.singleLine(text), to: max(0, limit - fixed))
        var line = style.paint(spin, .accent) + " " + shown
        if let bar { line += " ▕" + style.paint(bar.filled, .accent) + bar.empty + "▏" }
        return line + " " + style.paint(counts, .muted)
    }
}

/// La animación de verdad: un temporizador redibuja la línea cada 80 ms en la salida de errores, sin cursor.
final class AnimatedActivity: Activity, @unchecked Sendable {
    static let hideCursor = "\u{1B}[?25l"
    static let showCursor = "\u{1B}[?25h"
    static let clearLine = "\r\u{1B}[2K"

    private let lock = NSLock()
    private let queue: DispatchQueue
    private let timer: any DispatchSourceTimer
    private let started = ContinuousClock.now
    private let style: Style
    private let width: @Sendable () -> Int
    private let output: @Sendable (String) -> Void
    private let terminalGuard: TerminalGuard
    private let cursorFD: Int32?
    private var text: String
    private var progress: ActivityProgress?
    private var tick = 0
    private var finished = false
    /// Parada con Ctrl-Z: no se dibuja hasta que el proceso sigue.
    private var paused = false
    private var guardID: Int?

    /// `cursorFD`: el descriptor donde se ha ocultado el cursor, para que `CrashRestore` lo enseñe si el proceso se
    /// cae. Las pruebas no lo pasan.
    init(title: String, style: Style, interval: DispatchTimeInterval = ActivityFrame.interval, cursorFD: Int32? = nil,
         terminalGuard: TerminalGuard = .shared, width: @escaping @Sendable () -> Int,
         output: @escaping @Sendable (String) -> Void) {
        // Primero todas las propiedades (una clase no puede leer las suyas antes), luego lo que se ve.
        let queue = DispatchQueue(label: "cat.start.tria.activity")
        text = title
        self.style = style
        self.width = width
        self.output = output
        self.terminalGuard = terminalGuard
        self.cursorFD = cursorFD
        self.queue = queue
        timer = DispatchSource.makeTimerSource(queue: queue)
        if let cursorFD { CrashRestore.cursorHidden(on: cursorFD) }
        // Primero la limpieza y luego ocultar el cursor, para que nunca quede oculto sin quien lo devuelva. La guarda
        // retiene la actividad (fuerte) hasta que `finish` o Ctrl-C la quitan; así una actividad soltada no deja el
        // cursor oculto. Con Ctrl-Z, el shell también recupera el cursor.
        guardID = terminalGuard.register({ [self] in clear() },
                                         suspension: Suspension(pause: { [self] in pause() },
                                                                resume: { [self] in resume() }))
        output(Self.hideCursor)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in self?.draw() }
        timer.resume()
    }

    var elapsedSeconds: Int { Int((ContinuousClock.now - started).components.seconds) }

    func update(_ text: String, progress: ActivityProgress?) {
        lock.withLock {
            self.text = text
            self.progress = progress
        }
    }

    func finish(_ line: String?) {
        guard stop() else { return }
        output(Self.clearLine + Self.showCursor + (line.map { $0 + "\n" } ?? ""))
        if let guardID { terminalGuard.unregister(guardID) }
        if cursorFD != nil { CrashRestore.cursorShown() }
    }

    /// Lo que hace Ctrl-C: borrar la línea y enseñar el cursor.
    private func clear() {
        guard stop() else { return }
        output(Self.clearLine + Self.showCursor)
        if cursorFD != nil { CrashRestore.cursorShown() }
    }

    /// Ctrl-Z: deja de dibujar, borra la línea y enseña el cursor, como Ctrl-C pero sin acabar.
    private func pause() {
        let pausing = lock.withLock { () -> Bool in
            guard !finished, !paused else { return false }
            paused = true
            return true
        }
        guard pausing else { return }
        queue.sync {}   // espera a un dibujo en curso
        output(Self.clearLine + Self.showCursor)
    }

    /// Al seguir (`fg`): vuelve a ocultar el cursor y a dibujar. Con el cerrojo, para que un `finish` a la vez enseñe
    /// el cursor después y no antes.
    private func resume() {
        lock.withLock {
            guard !finished, paused else { return }
            paused = false
            output(Self.hideCursor)
        }
    }

    /// Para el temporizador y espera a que acabe un dibujo en curso. Solo la primera vez devuelve `true`.
    private func stop() -> Bool {
        let first = lock.withLock { () -> Bool in
            defer { finished = true }
            return !finished
        }
        guard first else { return false }
        timer.cancel()
        queue.sync {}
        return true
    }

    private func draw() {
        let frame = lock.withLock { () -> String? in
            guard !finished, !paused else { return nil }
            defer { tick += 1 }
            return ActivityFrame.render(text: text, progress: progress, seconds: elapsedSeconds, tick: tick,
                                        width: width(), style: style)
        }
        if let frame { output(Self.clearLine + frame) }
    }
}

/// Sin animación (la salida de errores no es un terminal, `NO_COLOR` o `TERM=dumb`): el título y la línea final, cada
/// uno en su línea.
final class PlainActivity: Activity, @unchecked Sendable {
    private let lock = NSLock()
    private let started = ContinuousClock.now
    private let output: @Sendable (String) -> Void
    private var finished = false

    init(title: String, output: @escaping @Sendable (String) -> Void) {
        self.output = output
        output(TextWidth.singleLine(title) + "\n")
    }

    var elapsedSeconds: Int { Int((ContinuousClock.now - started).components.seconds) }

    func update(_ text: String, progress: ActivityProgress?) {}

    func finish(_ line: String?) {
        let first = lock.withLock { () -> Bool in
            defer { finished = true }
            return !finished
        }
        if first, let line { output(line + "\n") }
    }
}

extension Terminal {
    /// Mientras `work` corre no se debe escribir en el terminal por otra vía (ver `Activity`).
    /// Corre `work` con la animación y la quita aunque falle. `done` recibe el resultado y los segundos, y da la línea
    /// final.
    public func withActivity<T>(_ title: String, done: (T, Int) -> String? = { _, _ in nil },
                                _ work: (any Activity) async throws -> T) async throws -> T {
        let activity = startActivity(title)
        do {
            let value = try await work(activity)
            activity.finish(done(value, activity.elapsedSeconds))
            return value
        } catch {
            activity.finish(nil)
            throw error
        }
    }
}
