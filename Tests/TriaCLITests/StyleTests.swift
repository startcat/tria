import Testing
@testable import TriaCLI

struct StyleTests {
    @Test func plainStyleReturnsTheTextAsIs() {
        for role in StyleRole.allCases { #expect(Style.plain.paint("Movidos: 3", role) == "Movidos: 3") }
    }

    @Test func paletteCodesIn256Colors() {
        let style = Style(.palette256)
        #expect(style.paint("a", .accent) == "\u{1B}[38;5;166ma\u{1B}[39m")
        #expect(style.paint("a", .success) == "\u{1B}[38;5;65ma\u{1B}[39m")
        #expect(style.paint("a", .warning) == "\u{1B}[38;5;136ma\u{1B}[39m")
        #expect(style.paint("a", .danger) == "\u{1B}[38;5;131ma\u{1B}[39m")
        #expect(style.paint("a", .muted) == "\u{1B}[38;5;244ma\u{1B}[39m")
        #expect(style.paint("a", .strong) == "\u{1B}[1ma\u{1B}[22m")
    }

    @Test func paletteCodesInTrueColor() {
        let style = Style(.trueColor)
        #expect(style.paint("a", .accent) == "\u{1B}[38;2;211;90;49ma\u{1B}[39m")
        #expect(style.paint("a", .success) == "\u{1B}[38;2;102;145;83ma\u{1B}[39m")
        #expect(style.paint("a", .warning) == "\u{1B}[38;2;164;124;32ma\u{1B}[39m")
        #expect(style.paint("a", .danger) == "\u{1B}[38;2;177;80;61ma\u{1B}[39m")
        #expect(style.paint("a", .muted) == "\u{1B}[38;2;137;120;99ma\u{1B}[39m")
        #expect(style.paint("a", .strong) == "\u{1B}[1ma\u{1B}[22m")
    }

    @Test func emptyTextStaysEmpty() {
        #expect(Style(.trueColor).paint("", .accent) == "")
    }

    @Test func boldAndAColorCombine() {
        let style = Style(.palette256)
        #expect(style.paint(style.paint("s", .accent), .strong) == "\u{1B}[1m\u{1B}[38;5;166ms\u{1B}[39m\u{1B}[22m")
    }
}
