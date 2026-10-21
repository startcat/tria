#if DEBUG
import Darwin
import Foundation
import Testing
import TriaKit
import TriaTestSupport
@testable import TriaCLI

/// El paso 26 de la checklist, menos los colores: el `tria` de Debug en un pseudoterminal, con `TRIA_QA=1` (sin red
/// ni keys). ⌃C en mitad de la lectura y de la revisión deja el terminal como estaba, y cambiar el tamaño rehace la
/// pantalla. En serie: cada una lanza un proceso y espera por él.
@Suite(.serialized) struct PseudoTerminalTests {
    static let window = TerminalSize(columns: 100, rows: 30)
    static let document = "99-Pendiente/escaneo.txt"
    static let invoice = QAMarker.proposal(folder: "7-Facturas/Recibidas", name: "Factura QA", type: "Factura")

    /// Un espacio con un documento con `marker` en la bandeja, y `tria sort` lanzado en un pseudoterminal con el entorno
    /// de la tanda QA.
    private func start(_ marker: QAMarker, in dir: TempDir) throws -> PTYProcess {
        try #require(TriaBinary.isBuilt, "No está \(TriaBinary.url.path): compílalo con `swift build` y vuelve a probar")
        _ = try WorkspaceFixture.make(in: dir)
        let document = try dir.write(Self.document, "Factura de papelería.\n\(marker.text)\n")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)],
                                              ofItemAtPath: document.path)
        let environment = [
            "TRIA_QA": "1", "TRIA_QA_ROOT": dir.url.appendingPathComponent("qa").path, "TRIA_LANG": "es",
            "ANTHROPIC_API_KEY": "qa", "XDG_CONFIG_HOME": dir.url.appendingPathComponent("cli-config").path,
            "HOME": dir.url.path, "TERM": "xterm-256color", "PATH": "/usr/bin:/bin",
        ]
        return try PTYProcess(executable: TriaBinary.url, arguments: ["sort", "--root", dir.url.path],
                              environment: environment, size: Self.window)
    }

    /// La última vez que se pone `on` (ocultar el cursor, la pantalla alternativa), después se quita con `off`.
    private func undone(_ text: String, on: String, off: String) -> Bool {
        guard let last = text.range(of: on, options: .backwards) else { return true }
        return text[last.upperBound...].contains(off)
    }

    /// El último fotograma de la revisión: desde el último «al principio de la pantalla».
    private func lastFrame(_ text: String) -> Substring {
        guard let start = text.range(of: "\u{1B}[H", options: .backwards) else { return "" }
        return text[start.lowerBound...]
    }

    /// La raya más larga del fotograma: la de abajo ocupa el ancho de la ventana menos 2.
    private func longestRule(_ frame: Substring) -> Int {
        var longest = 0, current = 0
        for character in frame {
            current = character == "─" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    @Test func ctrlCWhileReadingLeavesTheTerminalAsItWas() throws {
        let dir = try TempDir("tria-pty")
        let tty = try start(.slow(30, then: .doubt("lenta")), in: dir)
        let log = dir.url.appendingPathComponent("qa/estado/peticiones.jsonl")
        // La animación oculta el cursor y la petición ya ha llegado al proveedor falso, que tarda 30 s.
        try #require(tty.waitFor { $0.contains(AnimatedActivity.hideCursor)
                                   && FileManager.default.fileExists(atPath: log.path) },
                     "No empieza a leer: \(tty.text.debugDescription)")

        tty.send("\u{03}")
        let status = try #require(tty.waitForExit(), "⌃C no lo para: \(tty.text.debugDescription)")

        #expect(PTYProcess.killed(by: SIGINT, status), "estado \(status)")
        #expect(undone(tty.text, on: AnimatedActivity.hideCursor, off: AnimatedActivity.showCursor),
                "el cursor queda oculto: \(tty.text.debugDescription)")
        #expect(PTYProcess.sameMode(tty.mode, tty.initialMode))
        #expect(tty.mode.c_lflag & tcflag_t(ECHO) != 0, "lo que se escribe no se ve")
        #expect(!tty.text.contains("\u{1B}[?1049h"), "no hay pantalla completa mientras lee")
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent(Self.document).path))
    }

    @Test func ctrlCInTheFullScreenReviewLeavesTheTerminalAsItWas() throws {
        let dir = try TempDir("tria-pty")
        let tty = try start(Self.invoice, in: dir)
        try #require(tty.waitFor { $0.contains(TTYScreen.enterSequence) && lastFrame($0).contains("\u{1B}[J") },
                     "No abre la revisión: \(tty.text.debugDescription)")
        // En la revisión el terminal está en modo crudo: la prueba mira algo que sí cambia.
        #expect(tty.mode.c_lflag & tcflag_t(ICANON | ECHO | ISIG) == 0)

        tty.send("\u{03}")
        let status = try #require(tty.waitForExit(), "⌃C no lo para: \(tty.text.debugDescription)")

        #expect(PTYProcess.killed(by: SIGINT, status), "estado \(status)")
        #expect(undone(tty.text, on: "\u{1B}[?25l", off: "\u{1B}[?25h"), "el cursor queda oculto")
        #expect(undone(tty.text, on: "\u{1B}[?1049h", off: "\u{1B}[?1049l"), "queda la pantalla completa")
        #expect(PTYProcess.sameMode(tty.mode, tty.initialMode))
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent(Self.document).path),
                "⌃C no mueve nada")
    }

    @Test func resizingTheWindowRedrawsTheReview() throws {
        let dir = try TempDir("tria-pty")
        let tty = try start(Self.invoice, in: dir)
        try #require(tty.waitFor { $0.contains(TTYScreen.enterSequence) && lastFrame($0).contains("\u{1B}[J") },
                     "No abre la revisión: \(tty.text.debugDescription)")
        #expect(longestRule(lastFrame(tty.text)) == Self.window.columns - 2)

        let smaller = TerminalSize(columns: 70, rows: 20)
        tty.resize(to: smaller)
        let redrawn = tty.waitFor {
            let frame = lastFrame($0)
            return frame.contains("\u{1B}[J") && longestRule(frame) == smaller.columns - 2
        }
        #expect(redrawn, "No rehace la pantalla a 70 columnas: \(String(lastFrame(tty.text)).debugDescription)")

        tty.send("q")
        let status = try #require(tty.waitForExit(), "q no sale: \(tty.text.debugDescription)")
        // Sale sin mover nada: queda un pendiente, así que acaba con 1.
        #expect(PTYProcess.exited(with: 1, status), "estado \(status)")
        #expect(undone(tty.text, on: "\u{1B}[?1049h", off: "\u{1B}[?1049l"))
        #expect(PTYProcess.sameMode(tty.mode, tty.initialMode))
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent(Self.document).path))
    }
}
#endif
