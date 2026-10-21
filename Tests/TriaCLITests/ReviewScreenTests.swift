import Foundation
import Testing
@testable import TriaCLI
@testable import TriaKit

private let header = ReviewHeader(workspace: "Despacho", model: "claude-haiku-5-5", cost: "0,0200 USD")

struct ReviewScreenTests {
    @Test func theScreenLooksLikeTheSketch() throws {
        let env = try CLIHarness().env
        let lines = ReviewScreen.lines(ReviewState(plan: UIFixtures.plan(UIFixtures.mockup)), header: header,
                                       size: TerminalSize(columns: 100, rows: 24), env: env, style: .plain)
        #expect(lines.count == 14)                                  // 5 filas, 5 de marco y 4 de detalle
        #expect(lines[0].hasPrefix(" Tria · Despacho") && lines[0].hasSuffix("claude-haiku-5-5 · ≈ 0,0200 USD"))
        #expect(lines[1] == " " + String(repeating: "─", count: 98))
        #expect(lines[2] == " ▸ [✓] ●  " + TextWidth.pad("scan_0012.pdf", to: 16)
                + "  → 2-Facturas Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf")
        #expect(lines[3] == "   [✓] ●  " + TextWidth.pad("scan_0013.pdf", to: 16)
                + "  → 2-Facturas Recibidas/…/3T/Factura Imprenta Litoral - 2026-09-12.pdf")
        #expect(lines[4] == "   [ ] ●  " + TextWidth.pad("nota.pdf", to: 16)
                + "  ? No queda claro qué es: parece una nota suelta.")
        #expect(lines[5] == "   [✓] ≡  " + TextWidth.pad("descarga (2).pdf", to: 16)
                + "  duplicado de 5-Bancos/descarga.pdf")
        #expect(lines[6] == "          " + TextWidth.pad("IMG_4471.jpg", to: 16)
                + "  pendiente: no se ha podido leer (no text)")
        #expect(lines[8] == " scan_0012.pdf · confianza alta")
        #expect(lines[9] == " → 2-Facturas Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf")
        #expect(lines[10] == " Factura de Papelería Mar del 5 de octubre.")
        #expect(lines[11] == "")                                    // el detalle mide lo que pide nota.pdf, con su duda
        #expect(lines[13] == " ↑↓ moverse  espacio marcar  a solo alta  e editar  p papelera  ↩ aplicar 3  q salir")
    }

    @Test func colorsMarkTheCursorTheChecksAndTheDestinations() throws {
        let env = try CLIHarness().env
        let lines = ReviewScreen.lines(ReviewState(plan: UIFixtures.plan(UIFixtures.mockup)), header: header,
                                       size: TerminalSize(columns: 100, rows: 24), env: env, style: Style(.palette256))
        #expect(lines[2].contains("\u{1B}[38;5;166m▸\u{1B}[39m"))
        #expect(lines[2].contains("\u{1B}[38;5;65m[✓]\u{1B}[39m"))
        #expect(lines[2].contains("\u{1B}[38;5;166m→ 2-Facturas"))
        #expect(lines[4].contains("\u{1B}[38;5;136m? No queda claro"))
    }

    @Test func everyLineFitsTheWindow() throws {
        let env = try CLIHarness().env
        let long = UIFixtures.proposal("Factura Café 東京 ☕ con un nombre larguísimo de verdad.pdf",
                                       "7-Facturas/Recibidas/Una carpeta con un nombre muy largo/Factura Café 東京 ☕.pdf",
                                       reason: String(repeating: "Una razón que no se acaba nunca. ", count: 8))
        let deep = UIFixtures.proposal("hondo.pdf", String(repeating: "Carpeta con un nombre bastante largo/", count: 4)
                                       + "Factura con un nombre también muy largo - 2026-10-05.pdf", confidence: .medium,
                                       doubt: String(repeating: "Una duda larga. ", count: 10))
        let base = ReviewState(plan: UIFixtures.plan(UIFixtures.mockup + [long, deep]))
        for columns in [60, 61, 80, 100, 140] {
            for rows in [12, 13, 20, 40] {
                for style in [Style.plain, Style(.trueColor)] {
                    let size = TerminalSize(columns: columns, rows: rows)
                    var review = base
                    for _ in base.items {                           // el cursor pasa por cada fila y su detalle
                        review.scroll(visibleRows: ReviewScreen.listRows(review, size: size, env: env))
                        let lines = ReviewScreen.lines(review, header: header, size: size, env: env, style: style)
                        #expect(lines.count <= rows)
                        #expect(lines.allSatisfy { TextWidth.columns($0) < columns })
                        _ = review.handle(.down)
                    }
                }
            }
        }
    }

    @Test func anEmptyListDrawsNoIndicatorsAndThreeBlankDetailLines() throws {
        let env = try CLIHarness().env
        let review = ReviewState(plan: UIFixtures.plan([]))
        let size = TerminalSize(columns: 80, rows: 24)
        let lines = ReviewScreen.lines(review, header: header, size: size, env: env, style: .plain)
        #expect(lines.count <= size.rows)
        #expect(!lines.contains { $0.hasSuffix("↑") || $0.hasSuffix("↓") })
        #expect(lines[3...5] == ["", "", ""])
    }

    @Test func theHelpCountFollowsTheMarks() throws {
        let env = try CLIHarness().env
        let size = TerminalSize(columns: 100, rows: 24)
        func help(_ review: ReviewState) -> String? {
            ReviewScreen.lines(review, header: header, size: size, env: env, style: .plain).last
        }
        var review = ReviewState(plan: UIFixtures.plan(UIFixtures.mockup))
        #expect(help(review)?.contains("aplicar 3") == true)
        for _ in 0..<2 { _ = review.handle(.down) }
        _ = review.handle(.space)                                   // nota.pdf
        #expect(help(review)?.contains("aplicar 4") == true)
        _ = review.handle(.space)
        #expect(help(review)?.contains("aplicar 3") == true)
        _ = review.handle(.character("a"))
        #expect(help(review)?.contains("aplicar 2") == true)
        for _ in 0..<1 { _ = review.handle(.down) }
        _ = review.handle(.character("p"))                          // descarga (2).pdf a la Papelera
        #expect(help(review)?.contains("aplicar 3") == true)
        let narrow = TerminalSize(columns: 60, rows: 14)
        #expect(ReviewScreen.lines(review, header: header, size: narrow, env: env, style: .plain).last
                == " ↑↓ · espacio · a · e · p · ↩ aplicar 3 · q salir")
    }

    /// Lo que se aprueba se ve entero: el destino se parte después de una «/», con la sangría bajo la flecha, y debajo
    /// van la duda y el motivo, de qué es duplicado o por qué está pendiente.
    @Test func theDetailShowsTheWholeDestinationAndWhatThereIsToKnow() throws {
        let env = try CLIHarness().env
        let deep = UIFixtures.proposal("scan_0012.pdf", "7-Facturas/Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf")
        var review = ReviewState(plan: UIFixtures.plan([deep] + UIFixtures.mockup.dropFirst()))
        let size = TerminalSize(columns: 60, rows: 16)
        func detail() -> [String] {
            let lines = ReviewScreen.lines(review, header: header, size: size, env: env, style: .plain)
            #expect(lines.count == 14 && lines[7] == lines[12])     // 5 filas, la raya, 4 de detalle y la raya
            return Array(lines[8...11])
        }
        #expect(detail() == [" scan_0012.pdf · confianza alta", " → 7-Facturas/Recibidas/2026/4T/",
                             "   Factura Papeleria Mar - 2026-10-05.pdf", " Factura de Papelería Mar del 5 de octubre."])
        for _ in 0..<2 { _ = review.handle(.down) }
        #expect(detail() == [" nota.pdf · confianza baja", " → 6-Varios/Nota.pdf",
                             " ? No queda claro qué es: parece una nota suelta.", " Una nota escrita a mano."])
        _ = review.handle(.down)
        #expect(detail() == [" descarga (2).pdf", " → 98-Duplicados/descarga (2).pdf",
                             " duplicado de 5-Bancos/descarga.pdf", ""])
        _ = review.handle(.down)
        #expect(detail() == [" IMG_4471.jpg", " pendiente: no se ha podido leer (no text)", "", ""])
    }

    @Test func aReasonThatDoesNotFitEndsWithAnEllipsis() throws {
        let env = try CLIHarness().env
        let reason = String(repeating: "Una razón larga que ocupa varias líneas. ", count: 6)
        let review = ReviewState(plan: UIFixtures.plan([UIFixtures.proposal("a.pdf", "7-Facturas/Recibidas/A.pdf",
                                                                            reason: reason)]))
        let lines = ReviewScreen.lines(review, header: header, size: TerminalSize(columns: 60, rows: 14), env: env,
                                       style: .plain)
        let wrapped = TextWidth.wrap(reason, width: 58)
        #expect(lines.count == 10)                                  // el detalle llega al tope: 4 líneas
        #expect(Array(lines[4...7]) == [" a.pdf · confianza alta", " → 7-Facturas/Recibidas/A.pdf", " " + wrapped[0],
                                        " " + wrapped[1] + "…"])
    }

    /// Si el destino no cabe en el tope del detalle, se acorta solo el nombre del fichero; las carpetas, nunca. Si ni
    /// ellas caben, el detalle crece y la lista se queda con menos filas.
    @Test func aDestinationThatDoesNotFitShortensOnlyTheFileName() throws {
        let env = try CLIHarness().env
        let size = TerminalSize(columns: 60, rows: 12)
        let long = UIFixtures.proposal("a.pdf", "7-Facturas/Recibidas/Proveedores de material de oficina/2026/4T/"
                                       + "Factura de material de oficina y papelería del cuarto trimestre - 2026-10-05.pdf")
        var lines = ReviewScreen.lines(ReviewState(plan: UIFixtures.plan([long] + UIFixtures.mockup)), header: header,
                                       size: size, env: env, style: .plain)
        #expect(lines.count == 12)                                  // la lista conserva sus 4 filas
        #expect(lines[8] == " → 7-Facturas/Recibidas/Proveedores de material de oficina/")
        #expect(lines[9].hasPrefix("   2026/4T/Factura de material") && lines[9].contains("…"))
        #expect(lines[9].hasSuffix("2026-10-05.pdf") && TextWidth.columns(lines[9]) < 60)

        let folders = String(repeating: "Carpeta con un nombre bastante largo/", count: 4)
        let deeper = UIFixtures.proposal("b.pdf", folders + "B.pdf")
        lines = ReviewScreen.lines(ReviewState(plan: UIFixtures.plan([deeper] + UIFixtures.mockup)), header: header,
                                   size: size, env: env, style: .plain)
        #expect(lines.count == 12 && lines[4].hasSuffix(" ↓"))       // la lista se queda con 2 filas
        #expect(Array(lines[6...9]) == [" → Carpeta con un nombre bastante largo/"]
                + Array(repeating: "   Carpeta con un nombre bastante largo/", count: 2)
                + ["   Carpeta con un nombre bastante largo/B.pdf"])
    }

    @Test func aDuplicateShowsWhatItRepeatsInFull() throws {
        let env = try CLIHarness().env
        let original = "4-Correo/Extractos bancarios del segundo semestre/2026/extracto de cuenta corriente.txt"
        let review = ReviewState(plan: UIFixtures.plan([UIFixtures.duplicate("extracto (2).txt", of: original)]))
        let lines = ReviewScreen.lines(review, header: header, size: TerminalSize(columns: 60, rows: 16), env: env,
                                       style: .plain)
        let note = TextWidth.wrap("duplicado de " + original, width: 58)
        #expect(note.count == 2)
        #expect(Array(lines[4...7]) == [" extracto (2).txt", " → 98-Duplicados/extracto (2).txt"] + note.map { " " + $0 })
    }

    /// Un salto de línea o un Esc en lo que dice la IA o en un nombre no llegan al terminal: serían otra línea o una
    /// orden para el terminal.
    @Test func controlCharactersNeverReachTheTerminal() throws {
        let env = try CLIHarness().env
        let nasty = UIFixtures.proposal("fac\ntura\u{1B}[2J.pdf", "6-Varios/Nota.pdf", confidence: .low,
                                        reason: "línea 1\nlínea 2\u{1B}[31m roja", doubt: "una\tduda\u{9B}2J")
        var review = ReviewState(plan: UIFixtures.plan([nasty, UIFixtures.duplicate("b\u{7}.pdf", of: "5-Bancos/\u{1B}b.pdf")]))
        let size = TerminalSize(columns: 80, rows: 16)
        for _ in 0..<2 {
            let lines = ReviewScreen.lines(review, header: header, size: size, env: env, style: .plain)
            #expect(lines.count <= size.rows)
            #expect(!lines.contains { $0.unicodeScalars.contains(where: isControl) })
            #expect(lines.contains { $0.contains("fac tura [2J.pdf") })
            _ = review.handle(.down)
        }
    }

    /// El nombre del espacio se mide ya limpio: la cabecera ni se pasa de ancho ni recorta el modelo.
    @Test func theHeaderMeasuresTheCleanFolderName() throws {
        let env = try CLIHarness().env
        let odd = ReviewHeader(workspace: "Des\u{1B}pacho", model: "claude-haiku-5-5", cost: nil)
        let lines = ReviewScreen.lines(ReviewState(plan: UIFixtures.plan(UIFixtures.mockup)), header: odd,
                                       size: TerminalSize(columns: 60, rows: 16), env: env, style: .plain)
        #expect(lines[0].hasPrefix(" Tria · Des pacho "))
        #expect(lines[0].hasSuffix(" claude-haiku-5-5"))
        #expect(TextWidth.columns(lines[0]) == 59)
    }

    @Test func aTinyWindowDoesNotBreakTheScreen() throws {     // la ventana se encoge con la revisión abierta
        let env = try CLIHarness().env
        let lines = ReviewScreen.lines(ReviewState(plan: UIFixtures.plan(UIFixtures.mockup)), header: header,
                                       size: TerminalSize(columns: 10, rows: 3), env: env, style: .plain)
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { TextWidth.columns($0) < 10 })
    }

    @Test func aLongListScrollsAndShowsThereIsMore() throws {
        let env = try CLIHarness().env
        let many = (1...30).map { UIFixtures.proposal("doc \($0).pdf", "7-Facturas/Recibidas/Doc \($0).pdf") }
        var review = ReviewState(plan: UIFixtures.plan(many))
        for _ in 0..<10 { _ = review.handle(.down) }
        let size = TerminalSize(columns: 60, rows: 12)
        review.scroll(visibleRows: ReviewScreen.listRows(review, size: size, env: env))
        let lines = ReviewScreen.lines(review, header: header, size: size, env: env, style: .plain)
        #expect(lines.count == 12)
        #expect(lines[1].hasSuffix(" ↑") && lines[6].hasSuffix(" ↓"))
        #expect(lines[2].contains("doc 8.pdf"))
        #expect(lines[5].contains("▸") && lines[5].contains("doc 11.pdf"))
    }

    @Test func narrowWindowsCutPathsInTheMiddleAndShortenTheHelp() throws {
        let env = try CLIHarness().env
        let lines = ReviewScreen.lines(ReviewState(plan: UIFixtures.plan(UIFixtures.mockup)), header: header,
                                       size: TerminalSize(columns: 60, rows: 14), env: env, style: .plain)
        #expect(lines[2].contains("…") && lines[2].hasSuffix("2026-10-05.pdf"))
        #expect(lines.last == " ↑↓ · espacio · a · e · p · ↩ aplicar 3 · q salir")
    }

    @Test func aTrashedDuplicateAndAnEditShowWhereTheyGo() throws {
        let env = try CLIHarness().env
        var review = ReviewState(plan: UIFixtures.plan(UIFixtures.mockup))
        for _ in 0..<3 { _ = review.handle(.down) }
        _ = review.handle(.character("p"))
        let lines = ReviewScreen.lines(review, header: header, size: TerminalSize(columns: 100, rows: 24), env: env,
                                       style: .plain)
        #expect(lines[5].contains("[×] ≡") && lines[5].hasSuffix("→ Papelera"))
        #expect(lines[9] == " → Papelera")
    }
}

/// C0 (con Esc, saltos de línea y tabuladores), DEL y C1.
func isControl(_ scalar: Unicode.Scalar) -> Bool { scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) }
