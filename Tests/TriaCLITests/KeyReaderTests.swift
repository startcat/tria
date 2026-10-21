import ArgumentParser
import Darwin
import Foundation
import Testing
@testable import TriaCLI

struct KeyDecoderTests {
    @Test func arrowsEnterSpaceAndLettersAreKeys() {
        let bytes = Array("\u{1B}[A\u{1B}[B\u{1B}OC\u{1B}[D\r \nkj".utf8)
        #expect(KeyDecoder.decode(bytes).keys == [.up, .down, .right, .left, .enter, .space, .enter,
                                                  .character("k"), .character("j")])
    }

    @Test func ctrlCAndCtrlDAreNotLetters() {
        #expect(KeyDecoder.decode([0x03, 0x04]).keys == [.interrupt, .end])
    }

    @Test func aLoneEscapeWaitsForTheRest() {
        let half = KeyDecoder.decode([0x1B])
        #expect(half.keys.isEmpty && half.rest == [0x1B])
        #expect(KeyDecoder.decode([0x1B], atEnd: true).keys == [.escape])
        let split = KeyDecoder.decode(Array("j\u{1B}[".utf8))
        #expect(split.keys == [.character("j")] && split.rest == Array("\u{1B}[".utf8))
        #expect(KeyDecoder.decode(split.rest + Array("A".utf8)).keys == [.up])
    }

    @Test func escapeFollowedByALetterIsEscapeAndTheLetter() {
        #expect(KeyDecoder.decode(Array("\u{1B}q".utf8)).keys == [.escape, .character("q")])
    }

    @Test func modifiedArrowsAndUnknownSequencesDoNotLeak() {
        #expect(KeyDecoder.decode(Array("\u{1B}[1;5A\u{1B}[3~x".utf8)).keys == [.up, .character("x")])
    }

    @Test func malformedInputDoesNotSwallowKeys() {
        #expect(KeyDecoder.decode([0x1B, 0x5B, 0x03, 0x41]).keys == [.escape, .interrupt, .character("A")])
        #expect(KeyDecoder.decode([0xC3, 0x41]).keys == [.character("A")])
        #expect(KeyDecoder.decode([0x1B, 0x4F, 0x03]).keys == [.escape, .interrupt])
    }

    @Test func accentedLettersArriveWhole() {
        #expect(KeyDecoder.decode(Array("ñé".utf8)).keys == [.character("ñ"), .character("é")])
        let cut = KeyDecoder.decode([0xC3])
        #expect(cut.keys.isEmpty && cut.rest == [0xC3])
        #expect(KeyDecoder.decode([0xC3], atEnd: true).keys.isEmpty)
    }
}

/// Un pseudoterminal para probar el modo crudo sin un terminal de verdad.
private final class PseudoTerminal: @unchecked Sendable {
    let master: Int32
    let slave: Int32

    init() throws {
        master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0, let name = ptsname(master) else {
            throw TerminalError.notATerminal
        }
        slave = open(name, O_RDWR | O_NOCTTY)
        guard slave >= 0 else { throw TerminalError.notATerminal }
    }

    /// Escribe como si se tecleara.
    func type(_ text: String) { type(Array(text.utf8)) }
    func type(_ bytes: [UInt8]) { _ = bytes.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } }

    var mode: termios {
        var mode = termios()
        tcgetattr(slave, &mode)
        return mode
    }

    deinit {
        close(slave)
        close(master)
    }
}

/// Lo que se ve desde dentro de `stop`, mientras el proceso estaría parado.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    func add(_ value: Bool) { lock.withLock { values.append(value) } }
    var items: [Bool] { lock.withLock { values } }
}

private func isRaw(_ mode: termios) -> Bool { mode.c_lflag & tcflag_t(ICANON | ECHO | ISIG) == 0 }
private func isCooked(_ mode: termios) -> Bool {
    mode.c_lflag & tcflag_t(ICANON) != 0 && mode.c_lflag & tcflag_t(ISIG) != 0
}

/// En serie: `CrashRestore` es uno para todo el proceso.
@Suite(.serialized) struct RawModeTests {
    @Test func rawModeIsRestoredWhenDone() throws {
        let pty = try PseudoTerminal()
        try #require(isCooked(pty.mode))
        let mode = try RawMode(fd: pty.slave, terminalGuard: TerminalGuard())
        #expect(isRaw(pty.mode))
        mode.restore()
        #expect(isCooked(pty.mode))
        mode.restore()   // dos veces no hace daño
        #expect(isCooked(pty.mode))
    }

    @Test func forgettingToRestoreStillRestores() throws {
        let pty = try PseudoTerminal()
        do { _ = try RawMode(fd: pty.slave, terminalGuard: TerminalGuard()) }
        #expect(isCooked(pty.mode))
    }

    @Test func aGuardRunRestoresTheTerminalLikeCtrlC() throws {
        let pty = try PseudoTerminal()
        let guardian = TerminalGuard()
        let mode = try RawMode(fd: pty.slave, terminalGuard: guardian)
        #expect(isRaw(pty.mode))
        guardian.runAll()   // lo que hace Ctrl-C (o SIGTERM) antes de salir
        #expect(isCooked(pty.mode))
        withExtendedLifetime(mode) {}
    }

    /// Ctrl-Z (o `kill -TSTP`) en modo crudo: parado, el shell recupera su modo; al seguir, vuelve el crudo.
    @Test func ctrlZLeavesRawModeWhileStoppedAndComesBackToIt() throws {
        let pty = try PseudoTerminal()
        let cookedWhileStopped = Seen()
        let guardian = TerminalGuard(stop: { _ in cookedWhileStopped.add(isCooked(pty.mode)) })
        let mode = try RawMode(fd: pty.slave, terminalGuard: guardian)
        guardian.suspend()
        #expect(cookedWhileStopped.items == [true])
        #expect(isRaw(pty.mode))
        mode.restore()
        guardian.suspend()                                         // ya restaurado: no vuelve al modo crudo
        #expect(isCooked(pty.mode))
    }

    /// En primer plano vuelve enseguida (un pseudoterminal que no es el del proceso cuenta como tal), sin tocar el modo
    /// y dejando bloqueadas en el hilo las señales que lo estaban. Sin terminal, también.
    @Test func waitingForTheForegroundInTheForegroundReturnsAtOnce() throws {
        let pty = try PseudoTerminal()
        let mode = try RawMode(fd: pty.slave, terminalGuard: TerminalGuard())
        defer { mode.restore() }
        var blocked = sigset_t()
        sigemptyset(&blocked)
        sigaddset(&blocked, SIGTTOU)
        var before = sigset_t()
        pthread_sigmask(SIG_BLOCK, &blocked, &before)
        defer { pthread_sigmask(SIG_SETMASK, &before, nil) }
        var pipeEnds: [Int32] = [0, 0]
        try #require(pipe(&pipeEnds) == 0)
        defer { close(pipeEnds[0]); close(pipeEnds[1]) }
        TerminalGuard.waitForForeground(on: [pipeEnds[0], pty.slave])
        #expect(isRaw(pty.mode))
        var after = sigset_t()
        pthread_sigmask(SIG_BLOCK, nil, &after)
        #expect(sigismember(&after, SIGTTOU) == 1)                 // como estaba en el hilo
        TerminalGuard.waitForForeground(on: [pipeEnds[0]])
    }

    @Test func aCrashRestoresTheSavedMode() throws {
        let pty = try PseudoTerminal()
        let mode = try RawMode(fd: pty.slave, terminalGuard: TerminalGuard())
        #expect(isRaw(pty.mode))
        CrashRestore.restoreNow()   // lo que hace el manejador de SIGABRT, SIGSEGV…
        #expect(isCooked(pty.mode))
        mode.restore()
    }

    @Test func keysTypedBeforeTheScreenOpensAreDropped() throws {   // un Intro mientras la IA lee no aplica nada
        let pty = try PseudoTerminal()
        pty.type("\r")
        usleep(20_000)
        let mode = try RawMode(fd: pty.slave, terminalGuard: TerminalGuard())
        defer { mode.restore() }
        #expect(KeyReader(fd: pty.slave).next(timeout: 100) == nil)
    }

    @Test func theReaderTurnsTypedBytesIntoKeys() throws {
        let pty = try PseudoTerminal()
        let mode = try RawMode(fd: pty.slave, terminalGuard: TerminalGuard())
        defer { mode.restore() }
        let reader = KeyReader(fd: pty.slave)
        pty.type("\u{1B}[Aj ñ")
        #expect(reader.next(timeout: 500) == .up)
        #expect(reader.next(timeout: 500) == .character("j"))
        #expect(reader.next(timeout: 500) == .space)
        #expect(reader.next(timeout: 500) == .character("ñ"))
        pty.type([0x1B])
        #expect(reader.next(timeout: 500) == .escape)
        pty.type([0x03])
        #expect(reader.next(timeout: 500) == .interrupt)
        #expect(reader.next(timeout: 50) == nil)
    }

    @Test func aBrokenByteDoesNotEndTheWait() throws {
        let pty = try PseudoTerminal()
        let mode = try RawMode(fd: pty.slave, terminalGuard: TerminalGuard())
        defer { mode.restore() }
        let reader = KeyReader(fd: pty.slave)
        pty.type([0xE9])
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { pty.type("t") }
        // Límite holgado: en una máquina cargada (la CI) la «t» puede tardar; si el byte roto cortara la espera, el
        // resultado sería `nil` enseguida, y si no, llega en cuanto se escribe.
        #expect(reader.next(timeout: 5_000) == .character("t"))
        pty.type([0xE9])
        #expect(reader.next(timeout: 150) == nil)   // un límite finito sí acaba
    }

    @Test func runRestoresWhenTheBodyThrows() throws {
        let pty = try PseudoTerminal()
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try RawMode.run(fd: pty.slave, terminalGuard: TerminalGuard()) { () throws -> Void in
                #expect(isRaw(pty.mode))
                throw Boom()
            }
        }
        #expect(isCooked(pty.mode))
    }

    @Test func notATerminalIsAnError() throws {
        var pipeEnds: [Int32] = [0, 0]
        try #require(pipe(&pipeEnds) == 0)
        defer { close(pipeEnds[0]); close(pipeEnds[1]) }
        #expect(throws: TerminalError.notATerminal) { try RawMode(fd: pipeEnds[0], terminalGuard: TerminalGuard()) }
    }
}

/// Un subcomando de prueba cuya pregunta de una tecla se contesta con Ctrl-C.
private struct AskKeyCommand: TriaSubcommand {
    static let configuration = CommandConfiguration(commandName: "ask-key-test")
    func execute(_ env: CLIEnvironment) async throws {
        _ = try env.terminal.readKey("¿Qué hacemos? ", allowed: ["t"])
    }
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

struct InterruptHookTests {
    @Test func aCtrlCAnswerCallsOnInterruptAndExits130() async throws {
        let harness = try CLIHarness(answers: ["^C"])
        let calls = Calls()
        var env = harness.env
        env.onInterrupt = { calls.add() }
        let code = await CLIEnvironment.$current.withValue(env) { () -> Int32 in
            do {
                let command = AskKeyCommand()
                try await command.run()
                return 0
            } catch let exit as ExitCode {
                return exit.rawValue
            } catch {
                return -1
            }
        }
        #expect(calls.value == 1)
        #expect(code == 130)
    }
}
