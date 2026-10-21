import Foundation
import Testing
@testable import TriaCLI

/// Lo que se escribe, en orden y a salvo de hilos.
private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func add(_ entry: String) { lock.withLock { entries.append(entry) } }
    var items: [String] { lock.withLock { entries } }
}

struct ActivityTests {
    @Test func aFrameHasTheSpinnerTheTextTheBarAndTheSeconds() {
        #expect(ActivityFrame.render(text: "scan_0012.pdf", progress: ActivityProgress(done: 3, total: 9), seconds: 12,
                                     tick: 0, width: 80, style: .plain) == "⠋ scan_0012.pdf ▕███░░░░░░░▏ 3/9 · 12 s")
        #expect(ActivityFrame.render(text: "Analizando 9 documentos de 99-Pendiente…", progress: nil, seconds: 0,
                                     tick: 1, width: 80, style: .plain)
                == "⠙ Analizando 9 documentos de 99-Pendiente… 0 s")
        #expect(ActivityFrame.render(text: "a", progress: nil, seconds: 0, tick: 10, width: 80, style: .plain)
                .hasPrefix("⠋"))
        #expect(ActivityFrame.render(text: "a", progress: ActivityProgress(done: 0, total: 0), seconds: 1, tick: 0,
                                     width: 80, style: .plain) == "⠋ a 1 s")
    }

    @Test func aNarrowWindowDropsTheBarAndCutsTheText() {
        let frame = ActivityFrame.render(text: "Factura Papeleria Mar - 2026-10-05.pdf",
                                         progress: ActivityProgress(done: 3, total: 9), seconds: 12, tick: 0,
                                         width: 30, style: .plain)
        #expect(!frame.contains("▕"))
        #expect(TextWidth.columns(frame) <= 29)
        #expect(frame.hasSuffix("3/9 · 12 s"))
    }

    @Test func aNameWithControlCharactersIsDrawnWithSpaces() {
        let frame = ActivityFrame.render(text: "a\u{1B}[2J\nb.pdf", progress: nil, seconds: 0, tick: 0, width: 80,
                                         style: .plain)
        #expect(frame == "⠋ a [2J b.pdf 0 s")
        let out = Log()
        PlainActivity(title: "Pensando una regla para a\nb.pdf…", output: { out.add($0) }).finish(nil)
        #expect(out.items == ["Pensando una regla para a b.pdf…\n"])
    }

    @Test func colorsGoToTheSpinnerTheBarAndTheCounts() {
        #expect(ActivityFrame.render(text: "a.pdf", progress: ActivityProgress(done: 1, total: 2), seconds: 3, tick: 0,
                                     width: 80, style: Style(.palette256))
                == "\u{1B}[38;5;166m⠋\u{1B}[39m a.pdf ▕\u{1B}[38;5;166m█████\u{1B}[39m░░░░░▏ \u{1B}[38;5;244m1/2 · 3 s\u{1B}[39m")
    }

    @Test func theAnimationDrawsFramesAndLeavesTheFinalLine() async throws {
        let guardian = TerminalGuard()
        let out = Log()
        let activity = AnimatedActivity(title: "Analizando 2 documentos de 99-Pendiente…", style: .plain,
                                        interval: .milliseconds(5), terminalGuard: guardian, width: { 80 },
                                        output: { out.add($0) })
        activity.update("alta.pdf", progress: ActivityProgress(done: 1, total: 2))
        try await Task.sleep(for: .milliseconds(60))
        activity.finish("✓ 2 documentos leídos en 0 s")
        let count = out.items.count
        try await Task.sleep(for: .milliseconds(30))
        #expect(out.items.count == count)                          // ya no dibuja más
        #expect(out.items.first == "\u{1B}[?25l")
        #expect(out.items.contains { $0.contains("alta.pdf ▕█████░░░░░▏ 1/2") })
        #expect(out.items.last == "\r\u{1B}[2K\u{1B}[?25h✓ 2 documentos leídos en 0 s\n")
        activity.finish("otra")
        guardian.runAll()
        #expect(out.items.count == count)                          // ni otro finish ni Ctrl-C repiten nada
    }

    @Test func ctrlCDuringTheAnimationClearsTheLineAndShowsTheCursor() async throws {
        let guardian = TerminalGuard()
        let out = Log()
        let activity = AnimatedActivity(title: "Leyendo", style: .plain, interval: .milliseconds(5),
                                        terminalGuard: guardian, width: { 80 }, output: { out.add($0) })
        try await Task.sleep(for: .milliseconds(20))
        guardian.runAll()                                          // lo que hace Ctrl-C antes de salir con 130
        let count = out.items.count
        try await Task.sleep(for: .milliseconds(20))
        #expect(out.items.last == "\r\u{1B}[2K\u{1B}[?25h")
        #expect(out.items.count == count)
        activity.finish("✓")
        #expect(out.items.count == count)
    }

    /// Ctrl-Z con la animación: el shell no se queda sin cursor ni con media línea; al seguir, vuelve a dibujar.
    @Test func ctrlZShowsTheCursorAndStopsDrawingUntilTheProcessContinues() async throws {
        let out = Log()
        let seen = Log()
        let guardian = TerminalGuard(stop: { _ in
            let before = out.items.count
            seen.add(out.items.last ?? "")
            usleep(40_000)                                         // parado: no se dibuja nada
            seen.add(out.items.count == before ? "quieto" : "dibuja")
            seen.add(String(out.items.count))
        })
        let activity = AnimatedActivity(title: "Leyendo", style: .plain, interval: .milliseconds(5),
                                        terminalGuard: guardian, width: { 80 }, output: { out.add($0) })
        try await Task.sleep(for: .milliseconds(20))
        guardian.suspend()
        #expect(Array(seen.items.prefix(2)) == ["\r\u{1B}[2K\u{1B}[?25h", "quieto"])
        let resumed = try #require(Int(seen.items[2]))
        #expect(out.items[resumed] == "\u{1B}[?25l")                // al seguir, el cursor se vuelve a ocultar
        try await Task.sleep(for: .milliseconds(30))
        #expect(out.items.count > resumed + 1)                     // y se sigue dibujando
        activity.finish("✓")
        #expect(out.items.last == "\r\u{1B}[2K\u{1B}[?25h✓\n")
    }

    @Test func withoutAnimationTheTitleAndTheFinalLineAreLines() {
        let out = Log()
        let activity = PlainActivity(title: "Analizando 2 documentos de 99-Pendiente…", output: { out.add($0) })
        activity.update("alta.pdf", progress: ActivityProgress(done: 1, total: 2))
        activity.finish("✓ 2 documentos leídos en 0 s")
        activity.finish("otra")
        #expect(out.items == ["Analizando 2 documentos de 99-Pendiente…\n", "✓ 2 documentos leídos en 0 s\n"])
    }

    @Test func theGuardRunsEachCleanupOnceFromTheLastOne() {
        let guardian = TerminalGuard()
        let log = Log()
        guardian.register { log.add("a") }
        let second = guardian.register { log.add("b") }
        guardian.register { log.add("c") }
        guardian.unregister(second)
        guardian.runAll()
        guardian.runAll()
        #expect(log.items == ["c", "a"])
    }

    @Test func theScriptedTerminalWritesActivitiesAsErrorLines() async throws {
        let terminal = ScriptedTerminal()
        let value = try await terminal.withActivity("Leyendo", done: { (value: Int, seconds: Int) in
            "✓ \(value) en \(seconds) s"
        }) { activity in
            activity.update("a.pdf", progress: ActivityProgress(done: 1, total: 1))
            return 7
        }
        #expect(value == 7)
        #expect(terminal.transcript == "Leyendo\n✓ 7 en 0 s")
        #expect(terminal.output.isEmpty)
    }

    @Test func anActivityIsClearedWhenTheWorkFails() async {
        let terminal = ScriptedTerminal()
        let work: (any Activity) async throws -> Int = { _ in throw CLIError("mal") }
        await #expect(throws: CLIError.self) { try await terminal.withActivity("Leyendo", work) }
        #expect(terminal.transcript == "Leyendo")
    }

    @Test func theScriptedTerminalAnswersKeysWithItsAnswers() throws {
        let terminal = ScriptedTerminal(answers: ["r", "", "^C"])
        #expect(try terminal.readKey("¿Qué hacemos? ", allowed: ["t", "a", "r", "n"]) == "r")
        #expect(try terminal.readKey("¿Qué hacemos? ", allowed: ["t"]) == "")
        #expect(throws: TerminalInterrupt.self) { try terminal.readKey("x", allowed: []) }
        #expect(try terminal.readKey("x", allowed: []) == nil)
    }

    @Test func theEnvironmentStyleFollowsTheTerminal() throws {
        #expect(try CLIHarness().env.style == .plain)
        let colored = try CLIHarness(capabilities: .colored).env
        #expect(colored.style == Style(.palette256) && colored.errorStyle == Style(.palette256))
    }
}

struct TerminalGuardSuspendTests {
    /// Al seguir, antes de volver a poner nada, espera a estar en primer plano: tras `bg` o un `kill -CONT` no se
    /// vuelve a la pantalla completa ni al modo crudo desde segundo plano.
    @Test func ctrlZPausesFromTheLastStopsAndResumesFromTheFirst() {
        let log = Log()
        let guardian = TerminalGuard(stop: { log.add($0 ? "para hasta el primer plano" : "para") })
        guardian.register({ log.add("limpia a") },
                          suspension: Suspension(pause: { log.add("quita a") }, resume: { log.add("pone a") }))
        guardian.register { log.add("limpia b") }
        guardian.register({ log.add("limpia c") },
                          suspension: Suspension(pause: { log.add("quita c") }, resume: { log.add("pone c") }))
        guardian.suspend()
        #expect(log.items == ["quita c", "quita a", "para hasta el primer plano", "pone a", "pone c"])
        guardian.runAll()                                          // siguen apuntadas: un Ctrl-C después aún limpia
        #expect(Array(log.items.suffix(3)) == ["limpia c", "limpia b", "limpia a"])
    }

    /// Sin nada apartado no hay nada que volver a poner: tras `bg` puede seguir en segundo plano.
    @Test func withNothingPutAsideItDoesNotWaitForTheForeground() {
        let log = Log()
        let guardian = TerminalGuard(stop: { log.add($0 ? "para hasta el primer plano" : "para") })
        guardian.register { log.add("limpia") }
        guardian.suspend()
        #expect(log.items == ["para"])
    }

    /// La fuente de Dispatch ve, en la entrega que sigue a la parada, el `SIGTSTP` con el que el proceso se para a sí
    /// mismo y los que llegaron mientras se paraba o estaba parado (un segundo `kill -TSTP`): ninguno lo vuelve a parar,
    /// así que basta un `fg`.
    @Test func whatArrivesWhileStoppingDoesNotStopItAgain() {
        let log = Log()
        let guardian = TerminalGuard(stop: { _ in log.add("para") })
        guardian.stopRequested()                                   // kill -TSTP
        guardian.stopRequested()                                   // el propio y otro kill -TSTP llegado entretanto
        #expect(log.items == ["para"])
        guardian.stopRequested()                                   // otro, ya después del `fg`
        #expect(log.items == ["para", "para"])
        guardian.stopRequested()                                   // el propio
        #expect(log.items == ["para", "para"])
    }
}

struct TerminalGuardSignalTests {
    @Test func interruptCleansUpBeforeDyingBySignal() {
        let log = Log()
        let guardian = TerminalGuard(die: { log.add("die \($0)") })
        guardian.register { log.add("limpia") }
        guardian.interrupt(SIGINT)
        #expect(log.items == ["limpia", "die \(SIGINT)"])
    }

    /// Parado o esperando al primer plano, la cola de las señales está ocupada en `suspend`: Ctrl-C y `SIGTERM` (un
    /// `kill %1` manda SIGTERM y SIGCONT) lo acaban por su acción por defecto. Después se vuelven a ignorar, para que
    /// los atienda la cola, que limpia antes de salir.
    /// Con `kill`, como desde fuera: va al proceso, no al hilo (los de Dispatch tienen las señales bloqueadas).
    @Test func whileStoppedCtrlCAndTermEndTheProcessByThemselves() async {
        await #expect(processExitsWith: .signal(SIGTERM)) {
            signal(SIGTERM, SIG_IGN)
            TerminalGuard.interruptible {
                kill(getpid(), SIGTERM)
                sleep(5)
            }
        }
        await #expect(processExitsWith: .signal(SIGINT)) {
            signal(SIGINT, SIG_IGN)
            TerminalGuard.interruptible {
                kill(getpid(), SIGINT)
                sleep(5)
            }
        }
        await #expect(processExitsWith: .success) {
            for signo in [SIGINT, SIGTERM] { signal(signo, SIG_IGN) }
            TerminalGuard.interruptible {}
            kill(getpid(), SIGINT)
            kill(getpid(), SIGTERM)
            usleep(200_000)
            exit(0)
        }
    }

    /// Un trap de Swift es SIGTRAP (arm64) o SIGILL (x86_64): el proceso debe caer por la señal, no quedarse en bucle.
    @Test func aTrapWithTheCrashHandlerDiesBySignalInsteadOfLooping() async {
        #if arch(arm64)
        let expected = SIGTRAP
        #else
        let expected = SIGILL
        #endif
        await #expect(processExitsWith: .signal(expected)) {
            alarm(5)   // si el manejador volviera a quedarse en bucle, SIGALRM lo corta en 5 s y la prueba falla
            CrashRestore.install()
            let values: [Int] = []
            _ = values[Int.random(in: 1...2)]
        }
    }
}
