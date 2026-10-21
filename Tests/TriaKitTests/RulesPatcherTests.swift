import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private let text = """
---
inbox: In
duplicates: Dup
---
# Reglas

## Casos especiales

- Primera regla.

## Otra sección

Texto.
"""

@Test func insertsUnderTheMatchingSectionAfterItsLastLine() {
    let patched = RulesPatcher.insert(rule: "Nueva regla.", section: "casos especiales", into: text)
    #expect(patched.contains("- Primera regla.\n- Nueva regla.\n\n## Otra sección"))
}

@Test func createsTheSectionWhenMissing() {
    let patched = RulesPatcher.insert(rule: "- Regla suelta.", section: "Excepciones", into: text)
    #expect(patched.hasSuffix("Texto.\n\n## Excepciones\n\n- Regla suelta.\n"))
}

@Test func previewMarksTheAddedLine() {
    let preview = RulesPatcher.preview(rule: "Nueva regla.", section: "Casos especiales", in: text)
    #expect(preview.contains("  - Primera regla.\n+ - Nueva regla."))
    let created = RulesPatcher.preview(rule: "X.", section: "Nueva", in: text)
    #expect(created.contains("+ ## Nueva"))
}

@Test func aCRLFFileFindsItsSectionAndThePreviewHasNoCarriageReturns() {
    let crlf = text.replacingOccurrences(of: "\n", with: "\r\n")
    let patched = RulesPatcher.insert(rule: "Nueva regla.", section: "Casos especiales", into: crlf)
    #expect(patched == crlf.replacingOccurrences(of: "- Primera regla.\r\n", with: "- Primera regla.\r\n- Nueva regla.\r\n"))
    let preview = RulesPatcher.preview(rule: "Nueva regla.", section: "Casos especiales", in: crlf)
    #expect(preview.contains("  - Primera regla.\n+ - Nueva regla."))
    #expect(!preview.contains("+ ## Casos especiales") && !preview.contains("\r"))
}

@Test func aSectionWithOnlyItsTitleGetsABlankLineBeforeTheRule() {
    let patched = RulesPatcher.insert(rule: "Nueva.", section: "Vacía", into: "## Vacía\n\n## Otra\n- x\n")
    #expect(patched == "## Vacía\n\n- Nueva.\n\n## Otra\n- x\n")
    #expect(RulesPatcher.insert(rule: "Nueva.", section: "Vacía", into: "# R\n\n## Vacía") == "# R\n\n## Vacía\n\n- Nueva.")
    #expect(RulesPatcher.preview(rule: "Nueva.", section: "Vacía", in: "## Vacía\n\n## Otra\n") == "  ## Vacía\n  \n+ - Nueva.\n  ")
}

@Test func storesListsAndRemovesSuggestions() throws {
    let dir = try TempDir()
    let store = SuggestionStore(workspace: try WorkspaceFixture.make(in: dir))
    let a = RuleSuggestion(draft: RuleSuggestionDraft(section: "S", rule: "A"), context: "a.pdf")
    let b = RuleSuggestion(draft: RuleSuggestionDraft(section: "S", rule: "B"), context: "b.pdf")
    try store.add(a)
    try store.add(b)
    #expect(try store.list().map(\.rule) == ["A", "B"])
    try store.remove(id: a.id)
    #expect(try store.list().map(\.id) == [b.id])
    #expect(a.id.hasPrefix("sg_"))
}

@Test func applyingASuggestionRewritesTheRules() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let suggestion = RuleSuggestion(draft: RuleSuggestionDraft(section: "Nomenclatura", rule: "Los recibos de luz llevan el mes."),
                                    context: "luz.pdf")
    let updated = try ws.applySuggestion(suggestion)
    #expect(updated.rules.body.contains("- Los recibos de luz llevan el mes."))
    #expect(updated.rules.hash != ws.rules.hash)
}
