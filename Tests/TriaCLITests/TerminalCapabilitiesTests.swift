import Testing
@testable import TriaCLI

private let window = TerminalSize(columns: 100, rows: 30)

private func detect(_ environment: [String: String], stdin: Bool = true, stdout: Bool = true, stderr: Bool = true,
                    size: TerminalSize? = window) -> TerminalCapabilities {
    TerminalCapabilities.detect(environment: environment, stdin: stdin, stdout: stdout, stderr: stderr, size: size)
}

struct TerminalCapabilitiesTests {
    @Test func aRealTerminalGetsEverything() {
        let capabilities = detect(["TERM": "xterm-256color"])
        #expect(capabilities == TerminalCapabilities(colors: .palette256, errorColors: .palette256, animates: true,
                                                     keys: true, size: window))
        #expect(capabilities.fullScreen)
    }

    @Test func colortermChoosesTrueColor() {
        #expect(detect(["TERM": "xterm-256color", "COLORTERM": "truecolor"]).colors == .trueColor)
        #expect(detect(["TERM": "xterm-256color", "COLORTERM": "24bit"]).errorColors == .trueColor)
        #expect(detect(["TERM": "xterm-256color", "COLORTERM": "TrueColor"]).colors == .trueColor)
        #expect(detect(["TERM": "xterm-256color", "COLORTERM": "yes"]).colors == .palette256)
    }

    @Test func noColorTurnsOffColorsAndAnimations() {
        let capabilities = detect(["TERM": "xterm-256color", "NO_COLOR": "1"])
        #expect(capabilities.colors == .none && capabilities.errorColors == .none && !capabilities.animates)
        #expect(capabilities.fullScreen)
        // Vacía no cuenta (no-color.org).
        #expect(detect(["TERM": "xterm-256color", "NO_COLOR": ""]).colors == .palette256)
    }

    @Test func aDumbTerminalIsPlain() {
        let capabilities = detect(["TERM": "dumb"])
        #expect(capabilities.colors == .none && !capabilities.animates)
        #expect(!capabilities.keys && !capabilities.fullScreen)
    }

    @Test func pipingStandardOutputKeepsItPlain() {   // tria sort --dry-run > propuestas.txt
        let capabilities = detect(["TERM": "xterm-256color"], stdout: false)
        #expect(capabilities.colors == .none)
        #expect(capabilities.errorColors == .palette256 && capabilities.animates)
        #expect(!capabilities.keys && !capabilities.fullScreen && capabilities.size == nil)
    }

    @Test func redirectingErrorsStopsTheAnimation() {
        let capabilities = detect(["TERM": "xterm-256color"], stderr: false)
        #expect(capabilities.colors == .palette256 && capabilities.errorColors == .none && !capabilities.animates)
    }

    @Test func clicolorForceForcesColorsButNotOverNoColor() {
        #expect(detect(["CLICOLOR_FORCE": "1"], stdout: false, stderr: false).colors == .palette256)
        #expect(detect(["CLICOLOR_FORCE": "1", "TERM": "dumb"]).colors == .palette256)
        #expect(detect(["CLICOLOR_FORCE": "0"], stdout: false).colors == .none)
        #expect(detect(["CLICOLOR_FORCE": "1", "NO_COLOR": "1"]).colors == .none)
        #expect(!detect(["CLICOLOR_FORCE": "1"], stdout: false, stderr: false).animates)
    }

    @Test func withoutAnInputTerminalThereAreNoKeys() {
        #expect(!detect(["TERM": "xterm-256color"], stdin: false).keys)
        #expect(!detect(["TERM": "xterm-256color"], stdin: false).fullScreen)
    }

    @Test func fullScreenNeedsSixtyByTwelve() {
        #expect(detect(["TERM": "xterm"], size: TerminalSize(columns: 60, rows: 12)).fullScreen)
        #expect(!detect(["TERM": "xterm"], size: TerminalSize(columns: 59, rows: 30)).fullScreen)
        #expect(!detect(["TERM": "xterm"], size: TerminalSize(columns: 120, rows: 11)).fullScreen)
        #expect(!detect(["TERM": "xterm"], size: nil).fullScreen)
    }
}
