import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

struct RulesChangeTests {
    private func workspace(_ dir: TempDir, rules: String = WorkspaceFixture.defaultRules) throws -> Workspace {
        try Workspace.initialize(at: dir.url, rulesText: rules)
    }

    @Test func editingASectionChangesOnlyThatSection() throws {
        let dir = try TempDir()
        let ws = try workspace(dir, rules: Templates.text(.autonomo, language: .es))
        let document = RulesDocument.parse(ws.rules.raw)
        let s3 = try #require(document.section("s3"))
        let text = s3.text.trimmingCharacters(in: .newlines) + "\n- Los recibos del agua van con la luz.\n"
        let change = try RulesChange.editing(section: "s3", newText: text, in: ws)
        #expect(change.baseHash == ws.rules.hash)
        let untouched = document.frontmatter + document.preamble + document.sections[0].text + document.sections[1].text
        #expect(change.newText.hasPrefix(untouched))
        #expect(change.newText.hasSuffix("pendiente.\n- Los recibos del agua van con la luz."))
        #expect(change.createFolders.isEmpty)
        #expect(change.summary.isEmpty)
        #expect(change.preview.map(\.kind) == [.changed])
        #expect(change.preview[0].title == "Casos especiales")
        #expect(change.preview[0].lines.last == .added("- Los recibos del agua van con la luz."))
        #expect(!change.preview[0].lines.contains { if case .removed = $0 { true } else { false } })
    }

    @Test func editingACRLFFileKeepsTheRestByteForByte() throws {   // Review Focus 1
        let dir = try TempDir()
        let rules = WorkspaceFixture.defaultRules.replacingOccurrences(of: "\n", with: "\r\n")
        let ws = try workspace(dir, rules: rules)
        let change = try RulesChange.editing(section: "s2", newText: "## Nomenclatura\nTodo en minúsculas.\n", in: ws)
        let before = rules.components(separatedBy: "## Nomenclatura")[0]
        #expect(change.newText == before + "## Nomenclatura\r\nTodo en minúsculas.")
    }

    @Test func anEditMustBeOneSectionThatStartsWithTwoHashes() throws {
        let dir = try TempDir()
        let ws = try workspace(dir)
        #expect(throws: RulesChangeError.emptySection) {
            try RulesChange.editing(section: "s1", newText: " \n\n", in: ws)
        }
        #expect(throws: RulesChangeError.missingTitle(line: 1)) {
            try RulesChange.editing(section: "s1", newText: "Carpetas\n- a\n", in: ws)
        }
        #expect(throws: RulesChangeError.missingTitle(line: 2)) {
            try RulesChange.editing(section: "s1", newText: "\n---\n## Carpetas\n", in: ws)
        }
        #expect(throws: RulesChangeError.notOneSection(line: 4)) {
            try RulesChange.editing(section: "s1", newText: "## Carpetas\n- a\n\n## Otra\n- b\n", in: ws)
        }
        #expect(throws: RulesChangeError.notOneSection(line: 3)) {
            try RulesChange.editing(section: "s1", newText: "\n## Carpetas\n## Otra\n", in: ws)
        }
        #expect(throws: RulesChangeError.unknownSection("s9")) {
            try RulesChange.editing(section: "s9", newText: "## X\n", in: ws)
        }
        let s1 = try #require(RulesDocument.parse(ws.rules.raw).section("s1"))
        #expect(throws: RulesChangeError.noChange) { try RulesChange.editing(section: "s1", newText: s1.text, in: ws) }
        // Las líneas en blanco de delante no cuentan, ni un «## » dentro de un bloque de código.
        let fenced = try RulesChange.editing(section: "s1", newText: "\n\n## Carpetas\n```\n## no es otra\n```\n", in: ws)
        #expect(fenced.preview.map(\.title) == ["Carpetas"])
    }

    @Test func aSectionThatLeavesACodeBlockOpenCannotBeSaved() throws {
        let dir = try TempDir()
        let ws = try workspace(dir)
        // Al volver a leer TRIA.md, el bloque abierto se tragaría las secciones de detrás. La línea cuenta las de
        // delante, como en los otros errores.
        #expect(throws: RulesChangeError.unclosedCodeBlock(line: 4)) {
            try RulesChange.editing(section: "s1", newText: "\n## Carpetas\n- a\n```\n## no es otra\n", in: ws)
        }
        #expect(throws: RulesChangeError.unclosedCodeBlock(line: 2)) {
            try RulesChange.editing(section: "s1", newText: "## Carpetas\n~~~\n- a\n```\n", in: ws)
        }
        #expect(throws: RulesChangeError.unclosedCodeBlock(line: 5)) {
            try RulesChange.editing(section: "s1", newText: "## Carpetas\n```\nx\n```\n```\n", in: ws)
        }
        #expect(try String(contentsOf: ws.rulesURL, encoding: .utf8) == WorkspaceFixture.defaultRules)
    }

    @Test func aChangeThatWouldReadBackAsOtherSectionsIsNotPrepared() throws {
        // Un TRIA.md escrito a mano que acaba con un bloque de código abierto: una sección nueva detrás quedaría dentro.
        let dir = try TempDir()
        let rules = WorkspaceFixture.defaultRules + "\n\n## Ejemplos\n- uno\n```\n## no es una sección\n"
        let ws = try workspace(dir, rules: rules)
        let document = RulesDocument.parse(ws.rules.raw)
        #expect(document.sections.map(\.title) == ["Carpetas", "Nomenclatura", "Ejemplos"])
        #expect(throws: RulesChangeError.unclosedCodeBlock(line: 3)) {
            try RulesChange.make(from: ws, to: document.appending("## Suministros\n- luz\n"))
        }
    }

    @Test func aChangeThatOnlyTouchesTrailingBlankLinesIsNoChange() throws {
        let dir = try TempDir()
        let ws = try workspace(dir)
        let s1 = try #require(RulesDocument.parse(ws.rules.raw).section("s1"))
        // Unas líneas con espacios al final: el texto cambia, pero la vista previa no enseñaría nada.
        #expect(throws: RulesChangeError.noChange) {
            try RulesChange.editing(section: "s1", newText: s1.text + "   \n \n", in: ws)
        }
    }

    @Test func theHeaderFormDoesNotProtectTheInboxOrTheDuplicates() throws {
        let dir = try TempDir()
        let ws = try workspace(dir)
        // Lo mismo que avisa `tria rules check`: la carpeta, algo que la cubre o un patrón que encaja.
        for patterns in [["99-Pendiente"], ["99-pendiente/"], ["99-*"], ["*"]] {
            #expect(throws: RulesChangeError.inboxProtected) {
                try RulesChange.header(newFolders: .subfoldersOnly, protected: patterns, in: ws)
            }
        }
        #expect(throws: RulesChangeError.duplicatesProtected) {
            try RulesChange.header(newFolders: .never, protected: ["98-Duplicados"], in: ws)
        }
        // Una carpeta de dentro de la bandeja no protege la bandeja.
        _ = try RulesChange.header(newFolders: .never, protected: ["99-Pendiente/sub"], in: ws)
    }

    @Test func theHeaderFormRewritesOnlyTheHeader() throws {
        let dir = try TempDir()
        let ws = try workspace(dir)
        let change = try RulesChange.header(newFolders: .never, protected: ["7-Facturas/20*/", "8-Certificados"], in: ws)
        let rules = try RulesFile.parse(change.newText)
        #expect(rules.header.newFolders == .never)
        #expect(rules.header.protected == ["7-Facturas/20*", "8-Certificados"])
        #expect(rules.header.inbox == "99-Pendiente")
        #expect(rules.header.duplicates == "98-Duplicados")
        let body = { (text: String) -> String in
            let document = RulesDocument.parse(text)
            return document.preamble + document.sections.map(\.text).joined()
        }
        #expect(body(change.newText) == body(ws.rules.raw))
        #expect(change.preview.map(\.kind) == [.header])
        #expect(change.preview[0].lines.contains(.removed("new_folders: subfolders_only")))
        #expect(change.preview[0].lines.contains(.added("new_folders: never")))
        // Lo mismo que hay (con los patrones normalizados) no es un cambio.
        #expect(throws: RulesChangeError.noChange) {
            try RulesChange.header(newFolders: .subfoldersOnly, protected: ["7-Facturas/20*/"], in: ws)
        }
    }

    @Test func aBrokenHeaderIsNotPrepared() throws {
        let dir = try TempDir()
        let ws = try workspace(dir)
        #expect(throws: RulesChangeError.invalidRules(.unsafePath(key: "protected", value: "../fuera"))) {
            try RulesChange.header(newFolders: .never, protected: ["../fuera"], in: ws)
        }
    }

    @Test func theDiffMarksRemovedAndAddedLines() {
        #expect(RulesSectionDiff.lines(from: "## A\n- uno\n- dos\n", to: "## A\n- uno\n- tres\n- dos\n")
                == [.same("## A"), .same("- uno"), .added("- tres"), .same("- dos")])
        #expect(RulesSectionDiff.lines(from: "## A\n- uno\n", to: "## A\n- otro\n")
                == [.same("## A"), .removed("- uno"), .added("- otro")])
        #expect(RulesSectionDiff.lines(from: "", to: "## B\r\n- b\r\n") == [.added("## B"), .added("- b")])
    }

    @Test func onlyTheBlankLineBeforeANewSectionIsNotAChange() {
        let old = RulesDocument.parse("## A\n- a")
        let new = old.appending("## B\n- b\n")
        let diffs = RulesSectionDiff.between(old, new)
        #expect(diffs.map(\.kind) == [.added])
        #expect(diffs[0].title == "B")
        #expect(diffs[0].lines == [.added("## B"), .added("- b")])
    }

    @Test func updatingTheHeaderTrimsPatternsAndDetectsNoChange() {
        let header = RulesHeader(inbox: "99-Pendiente", duplicates: "98-Duplicados",
                                 protected: ["7-Facturas/20*/"], newFolders: .subfoldersOnly)
        #expect(header.updating(newFolders: .subfoldersOnly, protected: ["  7-Facturas/20*/ ", "", "   "]) == nil)
        let changed = header.updating(newFolders: .never, protected: [" 8-Certificados ", ""])
        #expect(changed == RulesHeader(inbox: "99-Pendiente", duplicates: "98-Duplicados",
                                       protected: ["8-Certificados"], newFolders: .never))
    }
}
