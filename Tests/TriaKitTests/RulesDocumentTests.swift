import Foundation
import Testing
@testable import TriaKit

struct RulesDocumentTests {
    @Test(arguments: TemplateKind.allCases, TemplateLanguage.allCases)
    func everyTemplateComesBackByteForByte(kind: TemplateKind, language: TemplateLanguage) {
        let text = Templates.text(kind, language: language)
        let document = RulesDocument.parse(text)
        #expect(document.text == text)
        #expect(document.frontmatter.hasPrefix("---\n"))
        #expect(document.preamble.hasPrefix("# "))
        #expect(document.sections.map(\.id) == ["s1", "s2", "s3"])
        #expect(document.sections.allSatisfy { $0.text.hasPrefix("## ") })
    }

    @Test(arguments: [
        "",
        "sin cabecera ni secciones",
        "---\ninbox: x\n---\n",
        "---\nsin cerrar\n## A\n",
        "# Título\n\n## A\n- a\n\n## A\n- otra\n",
        "## A\n```\n## no es sección\n```\n## B\n",
        "---\r\ninbox: x\r\n---\r\n# T\r\n\r\n## A\r\n- a\r\n",
        "---\ninbox: x\n---\n## A\n- sin salto final",
        "\u{FEFF}---\ninbox: x\n---\n## A\n",
        "##sin espacio\n### subtítulo\n## Bueno\n",
    ])
    func oddFilesComeBackByteForByte(_ text: String) {   // Review Focus 1
        #expect(RulesDocument.parse(text).text == text)
    }

    @Test func sectionsAreCutAtEachLineThatStartsWithTwoHashes() {
        let text = "---\ninbox: x\n---\n# T\n\nIntro\n\n## A\n- a\n### Sub\n- b\n\n## A\n```\n## código\n```\n"
        let document = RulesDocument.parse(text)
        #expect(document.frontmatter == "---\ninbox: x\n---\n")
        #expect(document.preamble == "# T\n\nIntro\n\n")
        #expect(document.sections == [
            RulesSection(id: "s1", title: "A", text: "## A\n- a\n### Sub\n- b\n\n"),
            RulesSection(id: "s2", title: "A", text: "## A\n```\n## código\n```\n"),
        ])
    }

    @Test func crlfLinesStayCrlf() {
        let document = RulesDocument.parse("---\r\ninbox: x\r\n---\r\n## A\r\n- a\r\n")
        #expect(document.sections.first?.title == "A")
        #expect(document.sections.first?.text == "## A\r\n- a\r\n")
        #expect(document.lineEnding == "\r\n")
        #expect(RulesDocument.parse("## A\n").lineEnding == "\n")
    }

    @Test func replacingASectionTouchesNothingElse() throws {
        let document = RulesDocument.parse(Templates.text(.autonomo, language: .es))
        let edited = try #require(document.replacing("s2", with: "## Nomenclatura\n\nTodo en minúsculas.\n"))
        #expect(edited.frontmatter == document.frontmatter)
        #expect(edited.preamble == document.preamble)
        #expect(edited.sections[0] == document.sections[0])
        #expect(edited.sections[2] == document.sections[2])
        // Acaba con los mismos saltos que la que sustituye: la siguiente sigue tras una línea en blanco.
        #expect(edited.sections[1] == RulesSection(id: "s2", title: "Nomenclatura",
                                                   text: "## Nomenclatura\n\nTodo en minúsculas.\n\n"))
        #expect(RulesDocument.parse(edited.text) == edited)
        #expect(document.replacing("s9", with: "## X\n") == nil)
    }

    @Test func replacingKeepsTheLineEndingsOfTheFile() throws {   // Review Focus 1
        let text = "---\r\ninbox: x\r\n---\r\n## A\r\n- a\r\n\r\n## B\r\n- b"
        let first = try #require(RulesDocument.parse(text).replacing("s1", with: "## A\n- a\n- otra\n"))
        #expect(first.text == "---\r\ninbox: x\r\n---\r\n## A\r\n- a\r\n- otra\r\n\r\n## B\r\n- b")
        // La última sección no tenía salto final, y sigue sin él.
        let last = try #require(RulesDocument.parse(text).replacing("s2", with: "## B\n- c\n"))
        #expect(last.text == "---\r\ninbox: x\r\n---\r\n## A\r\n- a\r\n\r\n## B\r\n- c")
    }

    @Test func appendingLeavesABlankLineBeforeTheNewSection() {
        let appended = RulesDocument.parse("---\ninbox: x\n---\n## A\n- a").appending("## Suministros\n\n- Luz.")
        #expect(appended.text == "---\ninbox: x\n---\n## A\n- a\n\n## Suministros\n\n- Luz.\n")
        #expect(appended.sections.last == RulesSection(id: "s2", title: "Suministros", text: "## Suministros\n\n- Luz.\n"))
        let crlf = RulesDocument.parse("## A\r\n- a\r\n").appending("## B\n- b\n")
        #expect(crlf.text == "## A\r\n- a\r\n\r\n## B\r\n- b\r\n")
    }

    @Test func matchingFindsTheSameSectionAfterAnInsertAbove() throws {   // Review Focus 2
        let before = RulesDocument.parse("## A\n- a\n\n## B\n- b\n")
        let edited = try #require(before.section("s2"))
        #expect(before.matching(edited) == edited)
        let after = RulesDocument.parse("## Nueva\n- n\n\n## A\n- a\n\n## B\n- b\n")
        #expect(after.matching(edited)?.id == "s3")
        // Dos «B» y en s2 otra sección: no se sabe cuál era.
        let repeated = RulesDocument.parse("## B\n- 1\n\n## Nueva\n\n## B\n- 2\n")
        #expect(repeated.matching(edited) == nil)
    }

    @Test func replacingTheFrontmatterKeepsTheMarkAndTheLineEndings() {
        let document = RulesDocument.parse("\u{FEFF}---\r\ninbox: x\r\n---\r\n# T\r\n")
        let replaced = document.replacingFrontmatter("---\ninbox: y\n---\n")
        #expect(replaced.text == "\u{FEFF}---\r\ninbox: y\r\n---\r\n# T\r\n")
    }
}
