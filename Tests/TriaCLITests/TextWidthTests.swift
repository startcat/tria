import Testing
@testable import TriaCLI

struct TextWidthTests {
    @Test func columnsCountWhatTheTerminalShows() {
        #expect(TextWidth.columns("Factura.pdf") == 11)
        #expect(TextWidth.columns("Cafe\u{301}") == 4)          // é descompuesta, como la escribe el Finder
        #expect(TextWidth.columns("東京") == 4)
        #expect(TextWidth.columns("☕") == 2)
        #expect(TextWidth.columns("✓ ● ≡ ▸ ↩") == 9)
        #expect(TextWidth.columns(Style(.trueColor).paint("hola", .accent)) == 4)
    }

    @Test func truncatingNeverSplitsACharacter() {
        let name = String(repeating: "u\u{308}", count: 8) + "東京☕" + String(repeating: "o\u{301}", count: 8) + ".pdf"
        let allowed = Set(name).union([TextWidth.ellipsis])
        for width in 0...TextWidth.columns(name) {
            for cut in [TextWidth.truncateMiddle(name, to: width), TextWidth.truncateEnd(name, to: width)] {
                #expect(TextWidth.columns(cut) <= width)
                #expect(Set(cut).isSubset(of: allowed))
            }
        }
    }

    @Test func middleTruncationKeepsBothEnds() {
        #expect(TextWidth.truncateMiddle("Factura Papeleria Mar - 2026-10-05.pdf", to: 20) == "Factura Pa…10-05.pdf")
        #expect(TextWidth.truncateMiddle("abc", to: 5) == "abc")
        #expect(TextWidth.truncateMiddle("abcdef", to: 1) == "…")
        #expect(TextWidth.truncateMiddle("abcdef", to: 0) == "")
        #expect(TextWidth.truncateEnd("abcdef", to: 4) == "abc…")
    }

    @Test func pathsLoseFoldersFromTheMiddleFirst() {
        let path = "2-Facturas Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf"
        #expect(TextWidth.truncatePath(path, to: 80) == path)
        #expect(TextWidth.truncatePath(path, to: 64) == "2-Facturas Recibidas/…/4T/Factura Papeleria Mar - 2026-10-05.pdf")
        #expect(TextWidth.truncatePath(path, to: 61) == "2-Facturas Recibidas/…/Factura Papeleria Mar - 2026-10-05.pdf")
        let narrow = TextWidth.truncatePath(path, to: 30)
        #expect(TextWidth.columns(narrow) == 30)
        #expect(narrow.hasSuffix("2026-10-05.pdf"))
    }

    @Test func pathsWrapAfterASlashAndProseAtASpace() {
        let path = "2-Facturas Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf"
        #expect(TextWidth.wrap(path, width: 80, path: true) == [path])
        #expect(TextWidth.wrap(path, width: 32, path: true)
                == ["2-Facturas Recibidas/2026/4T/", "Factura Papeleria Mar -", "2026-10-05.pdf"])
        #expect(TextWidth.wrap(path, width: 20, path: true)
                == ["2-Facturas", "Recibidas/2026/4T/", "Factura Papeleria", "Mar - 2026-10-05.pdf"])
        #expect(TextWidth.wrap("Factura de Papelería Mar del 5 de octubre.", width: 20)
                == ["Factura de Papelería", "Mar del 5 de", "octubre."])
        #expect(TextWidth.wrap("", width: 10).isEmpty)
    }

    @Test func wrappingCountsWideCharactersAndBreaksOnlyWhatDoesNotFitAlone() {
        #expect(TextWidth.wrap("東京東京", width: 5) == ["東京", "東京"])
        #expect(TextWidth.wrap("東京東京 東京", width: 6) == ["東京東", "京", "東京"])
        #expect(TextWidth.wrap("☕☕☕", width: 3) == ["☕", "☕", "☕"])
        #expect(TextWidth.wrap("Recibidas/Supercalifragilistico.pdf", width: 13, path: true)
                == ["Recibidas/", "Supercalifrag", "ilistico.pdf"])
        let texts = ["2-Facturas Recibidas/2026/4T/Factura Café 東京 ☕ - 2026-10-05.pdf",
                     "Una razón con palabras, una/barra y un nombre_larguísimo_sin_espacios_de_ninguna_clase.",
                     "   Empieza con espacios: Supercalifragilísticoespialidoso/y acaba con ellos  "]
        for text in texts {
            for width in 2...40 {
                for path in [false, true] {
                    let lines = TextWidth.wrap(text, width: width, path: path)
                    #expect(lines.allSatisfy { TextWidth.columns($0) <= width && !$0.isEmpty })
                    #expect(lines.joined().filter { $0 != " " } == text.filter { $0 != " " })   // no se pierde nada
                }
            }
        }
    }

    /// Los espacios del principio y del final no se enseñan: con una primera palabra más larga que el ancho, darían
    /// una primera línea vacía.
    @Test func leadingAndTrailingSpacesAreNotWrapped() {
        #expect(TextWidth.wrap("  Supercalifragilístico", width: 10) == ["Supercalif", "ragilístic", "o"])
        #expect(TextWidth.wrap("  7-Facturas/Recibidas/x.pdf", width: 8, path: true)
                == ["7-Factur", "as/", "Recibida", "s/x.pdf"])
        #expect(TextWidth.wrap("  Hola mundo  ", width: 20) == ["Hola mundo"])
        #expect(TextWidth.wrap("   ", width: 5).isEmpty)
    }

    @Test func aPathThatDoesNotFitShortensOnlyTheFileName() {
        let path = "7-Facturas/Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf"
        #expect(TextWidth.wrapPath(path, width: 40, rows: 3) == TextWidth.wrap(path, width: 40, path: true))
        #expect(TextWidth.wrapPath(path, width: 40, rows: 1) == ["7-Facturas/Recibidas/2026/4T/Factu…5.pdf"])
        let two = TextWidth.wrapPath(path, width: 22, rows: 2)
        #expect(two.count == 2 && two[0] == "7-Facturas/Recibidas/" && two[1].hasPrefix("2026/4T/"))
        #expect(two[1].contains("…") && two[1].hasSuffix(".pdf") && TextWidth.columns(two[1]) <= 22)
        // Si ni las carpetas caben, salen todas igualmente: nunca se quita una.
        let deep = TextWidth.wrapPath(path, width: 12, rows: 2)
        #expect(deep.count > 2 && deep.joined().hasPrefix("7-Facturas/Recibidas/2026/4T/"))
    }

    @Test func singleLineTurnsEveryControlIntoASpace() {
        #expect(TextWidth.singleLine("a\nb\tc\r\u{1B}[31md\u{7F}e\u{85}f\u{9B}g\u{0}") == "a b c  [31md e f g ")
        #expect(TextWidth.singleLine("l1\r\nl2") == "l1  l2")
        let clean = "Factura Café 東京 ☕ e\u{301}.pdf"
        #expect(TextWidth.singleLine(clean) == clean)
    }

    @Test func padAlignsWideNames() {
        #expect(TextWidth.pad("東京.pdf", to: 10) == "東京.pdf  ")
        #expect(TextWidth.pad("largo", to: 2) == "largo")
        #expect(TextWidth.padLeft("3", to: 3) == "  3")
    }
}
