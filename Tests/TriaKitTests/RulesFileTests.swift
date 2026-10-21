import Testing
@testable import TriaKit

private let valid = """
---
inbox: 99-Pendiente de Organizar
duplicates: 97-Duplicados
protected:
  - "7-Facturas/20*/"
new_folders: never
---
# Organización de documentos

- Regla de ejemplo.
"""

@Test func parsesHeaderAndBody() throws {
    let rules = try RulesFile.parse(valid)
    #expect(rules.header == RulesHeader(
        inbox: "99-Pendiente de Organizar", duplicates: "97-Duplicados",
        protected: ["7-Facturas/20*"], newFolders: .never))
    #expect(rules.body.hasPrefix("# Organización de documentos"))
    #expect(rules.raw == valid)
}

@Test func defaultsNewFoldersToSubfoldersOnly() throws {
    let rules = try RulesFile.parse("---\ninbox: In\nduplicates: Dup\n---\nCuerpo")
    #expect(rules.header.newFolders == .subfoldersOnly)
    #expect(rules.header.protected.isEmpty)
}

@Test func acceptsCRLFAndBOM() throws {
    let text = "\u{FEFF}---\r\ninbox: In\r\nduplicates: Dup\r\n---\r\nCuerpo\r\n"
    #expect(try RulesFile.parse(text).header.inbox == "In")
}

@Test(arguments: [
    ("Sin cabecera", RulesError.missingFrontmatter),
    ("---\nduplicates: Dup\n---\n", RulesError.missingKey("inbox")),
    ("---\ninbox: In\n---\n", RulesError.missingKey("duplicates")),
    ("---\ninbox: In\nduplicates: Dup\nnew_folders: sometimes\n---\n",
     RulesError.invalidValue(key: "new_folders", value: "sometimes")),
    ("---\ninbox: /tmp/In\nduplicates: Dup\n---\n", RulesError.unsafePath(key: "inbox", value: "/tmp/In")),
    ("---\ninbox: ../In\nduplicates: Dup\n---\n", RulesError.unsafePath(key: "inbox", value: "../In")),
    ("---\ninbox: .tria\nduplicates: Dup\n---\n", RulesError.unsafePath(key: "inbox", value: ".tria")),
    ("---\ninbox: In\nduplicates: In/Dup\n---\n", RulesError.overlappingFolders),
])
func rejectsInvalidHeaders(text: String, expected: RulesError) {
    #expect(throws: expected) { try RulesFile.parse(text) }
}

@Test func renderRoundTrips() throws {
    let header = RulesHeader(inbox: "99-Pendiente", duplicates: "98-Duplicados",
                             protected: ["Archivo \"viejo\"/*"], newFolders: .anywhere)
    let text = RulesFile.render(header: header, body: "# Reglas\n\n- Una.\n")
    let parsed = try RulesFile.parse(text)
    #expect(parsed.header == header)
    #expect(parsed.body == "# Reglas\n\n- Una.\n")
}

@Test func hashChangesWithContent() throws {
    let a = try RulesFile.parse("---\ninbox: In\nduplicates: Dup\n---\nA")
    let b = try RulesFile.parse("---\ninbox: In\nduplicates: Dup\n---\nB")
    #expect(a.hash != b.hash)
    #expect(a.hash.count == 64)
}
