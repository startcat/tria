import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

struct RulesApplyTests {
    /// Una fila más en «Carpetas» de las reglas de prueba, con las carpetas que se pidan.
    private func suministros(_ ws: Workspace, folders: [String] = []) throws -> RulesChange {
        guard let s1 = RulesDocument.parse(ws.rules.raw).section("s1") else { throw RulesChangeError.unknownSection("s1") }
        let text = s1.text.trimmingCharacters(in: .newlines) + "\n| 10-Suministros/ | Luz, agua y gas |\n"
        var change = try RulesChange.editing(section: "s1", newText: text, in: ws)
        change.createFolders = folders
        return change
    }

    private func history(_ ws: Workspace) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: ws.rulesHistoryURL.path).sorted()
    }

    @Test func applyingWritesTheRulesCreatesTheFoldersAndReloads() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        let change = try suministros(ws, folders: ["10-Suministros/Luz"])
        let updated = try ws.apply(change)
        #expect(updated.rules.raw == change.newText)
        #expect(try String(contentsOf: ws.rulesURL, encoding: .utf8) == change.newText)
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("10-Suministros/Luz").path))
        // Cambiar TRIA.md cambia lo que la bandeja da por leído (spec de Reglas, §4.3).
        #expect(updated.contextHash != ws.contextHash)
        let copies = try history(ws)
        #expect(copies.count == 1)
        #expect(try String(contentsOf: ws.rulesHistoryURL.appendingPathComponent(copies[0]), encoding: .utf8)
                == WorkspaceFixture.defaultRules)
        #expect(!FileManager.default.fileExists(atPath: ws.lockURL.path), "El cerrojo se suelta")
    }

    @Test func theHistoryIsNamedByDateAndTimeAndKeepsTheLastTwenty() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        try FileManager.default.createDirectory(at: ws.rulesHistoryURL, withIntermediateDirectories: true)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for index in 0..<21 {
            let url = ws.rulesHistoryURL.appendingPathComponent(String(format: "viejo-%02d.md", index))
            try Data("v\(index)".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(Double(index) * 60)],
                                                  ofItemAtPath: url.path)
        }
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 10,
                                                                          minute: 15, second: 30)))
        _ = try ws.apply(try suministros(ws), now: now)
        let names = Set(try history(ws))
        #expect(names.count == 20)
        #expect(names.contains("2026-10-16-101530.md"))
        #expect(!names.contains("viejo-00.md") && !names.contains("viejo-01.md"))
        #expect(names.contains("viejo-02.md") && names.contains("viejo-20.md"))
    }

    @Test func twoChangesInTheSameSecondKeepBothCopies() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let first = try ws.apply(try suministros(ws), now: now)
        let header = try RulesChange.header(newFolders: .never, protected: [], in: first)
        _ = try first.apply(header, now: now)
        let names = try history(ws)
        #expect(names.count == 2)
        #expect(names.contains { $0.hasSuffix(" (2).md") })
    }

    @Test func aChangePreparedOnAnOlderTextIsNotApplied() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        let change = try suministros(ws, folders: ["10-Suministros"])
        let outside = WorkspaceFixture.defaultRules + "\n\n## Hecho a mano\n- fuera\n"
        try Data(outside.utf8).write(to: ws.rulesURL)
        #expect(throws: RulesChangeError.changedOnDisk) { try ws.apply(change) }
        #expect(try String(contentsOf: ws.rulesURL, encoding: .utf8) == outside)
        #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("10-Suministros").path))
        #expect(!FileManager.default.fileExists(atPath: ws.rulesHistoryURL.path))
    }

    @Test func whileAnotherProcessSortsTheChangeIsNotApplied() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        let since = ISO8601DateFormatter().string(from: Date())
        try Data(#"{"pid":1,"host":"otro-mac","since":"\#(since)"}"#.utf8).write(to: ws.lockURL)
        #expect(throws: RulesChangeError.locked) { try ws.apply(try suministros(ws)) }
        #expect(try String(contentsOf: ws.rulesURL, encoding: .utf8) == WorkspaceFixture.defaultRules)
    }

    @Test func whileThisProcessSortsTheChangeIsNotAppliedAndSaysSo() throws {   // la app, a la vez, no es «otro sitio»
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        let change = try suministros(ws)
        let lock = try WorkspaceLock.acquire(ws)
        defer { lock.release() }
        #expect(throws: RulesChangeError.lockedByThisProcess) { try ws.apply(change) }
        #expect(try String(contentsOf: ws.rulesURL, encoding: .utf8) == WorkspaceFixture.defaultRules)
    }

    @Test func applyRefusesAnUnsafeFolderInAHandMadeChange() throws {   // Review Focus 3
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        for folder in ["../fuera", "/tmp/tria-fuera", ".tria/x", "99-Pendiente/sub", "98-Duplicados/x"] {
            #expect(throws: RulesChangeError.unsafeFolder(folder)) { try ws.apply(try suministros(ws, folders: [folder])) }
        }
        #expect(try String(contentsOf: ws.rulesURL, encoding: .utf8) == WorkspaceFixture.defaultRules)
        #expect(!FileManager.default.fileExists(atPath: ws.rulesHistoryURL.path))
        // Ni dentro de la bandeja ni de duplicados, aunque ya existan o vengan con otras mayúsculas: no se crea nada.
        #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("99-Pendiente/sub").path))
        #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("98-Duplicados/x").path))
        #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent(".tria/x").path))
        #expect(throws: RulesChangeError.unsafeFolder("99-pendiente")) {
            try ws.apply(try suministros(ws, folders: ["99-pendiente"]))
        }
    }

    @Test func ifOldCopiesCannotBeDeletedTheChangeIsStillApplied() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        try FileManager.default.createDirectory(at: ws.rulesHistoryURL, withIntermediateDirectories: true)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for index in 1...20 {
            let url = ws.rulesHistoryURL.appendingPathComponent(String(format: "viejo-%02d.md", index))
            try Data("v\(index)".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(Double(index) * 60)],
                                                  ofItemAtPath: url.path)
        }
        // La más vieja no se puede borrar: es una carpeta sin permiso de escritura con algo dentro.
        let stuck = ws.rulesHistoryURL.appendingPathComponent("viejo-00.md", isDirectory: true)
        try FileManager.default.createDirectory(at: stuck, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: stuck.appendingPathComponent("dentro.txt"))
        try FileManager.default.setAttributes([.modificationDate: start], ofItemAtPath: stuck.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: stuck.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stuck.path) }
        #expect(throws: (any Error).self, "La prueba necesita una copia que no se pueda borrar") {
            try FileManager.default.removeItem(at: stuck.appendingPathComponent("dentro.txt"))
        }
        let change = try suministros(ws, folders: ["10-Suministros"])
        let updated = try ws.apply(change)
        #expect(updated.rules.raw == change.newText)
        #expect(try String(contentsOf: ws.rulesURL, encoding: .utf8) == change.newText)
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("10-Suministros").path))
        // La copia de antes del cambio está; sobra la que no se pudo borrar.
        let names = try history(ws)
        #expect(names.contains("viejo-00.md"))
        #expect(names.count == 22)
        #expect(!FileManager.default.fileExists(atPath: ws.lockURL.path), "El cerrojo se suelta")
    }

    @Test func applyingASuggestionKeepsWhatChangedOutside() throws {   // spec de Reglas, §6.2
        let dir = try TempDir()
        let stale = try WorkspaceFixture.make(in: dir)
        let outside = WorkspaceFixture.defaultRules + "\n\n## Casos especiales\n- Escrito a mano.\n"
        try Data(outside.utf8).write(to: stale.rulesURL)
        let suggestion = RuleSuggestion(draft: RuleSuggestionDraft(section: "Casos especiales",
                                                                   rule: "Los recibos del agua van con la luz."),
                                        context: "a.pdf")
        let updated = try stale.applySuggestion(suggestion)
        #expect(updated.rules.raw.contains("- Escrito a mano.\n- Los recibos del agua van con la luz."))
    }

    @Test func aSuggestionOnACRLFFileGoesToItsSectionWithTheSameLineEndings() throws {
        let dir = try TempDir()
        let lf = WorkspaceFixture.defaultRules + "\n\n## Casos especiales\n- Escrito a mano.\n\n## Después\n- algo\n"
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        let ws = try WorkspaceFixture.make(in: dir, rules: crlf)
        let draft = RuleSuggestionDraft(section: "casos especiales", rule: "Los recibos del agua van con la luz.")
        let updated = try ws.applySuggestion(RuleSuggestion(draft: draft, context: "a.pdf"))
        let expected = crlf.replacingOccurrences(of: "- Escrito a mano.\r\n",
                                                 with: "- Escrito a mano.\r\n- Los recibos del agua van con la luz.\r\n")
        #expect(updated.rules.raw == expected)
        #expect(updated.rules.raw.components(separatedBy: "## Casos especiales").count == 2, "Sin sección repetida")
        #expect(!updated.rules.raw.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "Todo con \\r\\n")
        // Una sección que no está se añade al final, también con \r\n.
        let other = RuleSuggestionDraft(section: "Excepciones", rule: "- Regla suelta.")
        let added = try updated.applySuggestion(RuleSuggestion(draft: other, context: "b.pdf"))
        #expect(added.rules.raw == expected + "\r\n## Excepciones\r\n\r\n- Regla suelta.\r\n")
    }

    @Test func aTitleInsideACodeBlockIsNotTheSection() throws {
        let dir = try TempDir()
        let rules = WorkspaceFixture.defaultRules + "\n\n## Ejemplos\n```\n## Casos especiales\n```\n"
        let ws = try WorkspaceFixture.make(in: dir, rules: rules)
        let draft = RuleSuggestionDraft(section: "Casos especiales", rule: "Los recibos del agua van con la luz.")
        let updated = try ws.applySuggestion(RuleSuggestion(draft: draft, context: "a.pdf"))
        #expect(updated.rules.raw == rules + "\n## Casos especiales\n\n- Los recibos del agua van con la luz.\n")
    }

    @Test func suggestionsRememberWhereTheyCameFromAndOldOnesStillRead() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        let store = SuggestionStore(workspace: ws)
        let draft = RuleSuggestionDraft(section: "Casos especiales", rule: "Los recibos de seguros van a 7-Seguros.")
        try store.add(RuleSuggestion(draft: draft, context: "scan_0012.pdf: 5-Bancos → 7-Seguros",
                                     document: "scan_0012.pdf", fromFolder: "5-Bancos", toFolder: "7-Seguros"))
        // Una línea de antes, sin los campos nuevos.
        var data = try Data(contentsOf: ws.suggestionsURL)
        data.append(Data(#"{"context":"b.pdf","createdAt":"2026-10-11T10:00:00Z","id":"sg_viejo01","rule":"Regla vieja.","section":"Nomenclatura"}"#.utf8))
        data.append(0x0A)
        try data.write(to: ws.suggestionsURL)
        let listed = try store.list()
        #expect(listed.count == 2)
        #expect(listed[0].document == "scan_0012.pdf")
        #expect(listed[0].fromFolder == "5-Bancos")
        #expect(listed[0].toFolder == "7-Seguros")
        #expect(listed[1].id == "sg_viejo01")
        #expect(listed[1].document == nil && listed[1].fromFolder == nil && listed[1].toFolder == nil)
        // Sin origen no se escriben los campos: el fichero sigue como lo lee una versión anterior.
        let old = RuleSuggestion(draft: draft, context: "c.pdf")
        #expect(!String(decoding: try JSONEncoder().encode(old), as: UTF8.self).contains("fromFolder"))
    }
}
