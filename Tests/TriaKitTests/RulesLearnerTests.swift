import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private func archive(_ dir: TempDir) throws {
    for folder in ["Facturas", "Impuestos", "Bancos"] {
        for n in 1...5 { try dir.write("\(folder)/\(folder) \(n) - 2025-0\(n)-01.txt", "Documento \(folder) número \(n)") }
    }
}

private let draftJSON = """
{"inbox":"99-Pendiente","duplicates":"98-Duplicados","protected":[],"new_folders":"subfolders_only",
 "body":"# Organización de documentos\\n\\n## Carpetas\\n| Carpeta | Contenido |\\n|---|---|\\n| `Facturas/` | Facturas |\\n"}
"""

@Test func planSamplesRoundRobinAcrossFolders() throws {
    let dir = try TempDir()
    try archive(dir)
    let plan = try RulesLearner(provider: ScriptedProvider { _ in "" }).plan(root: dir.url, sampleSize: 4)
    #expect(plan.samples.count == 4)
    #expect(Set(plan.samples.map { $0.relativePath.split(separator: "/")[0] }) == ["Facturas", "Impuestos", "Bancos"])
    #expect(plan.samples.allSatisfy { $0.excerpt.hasPrefix("Documento") })
    #expect(plan.tree.contains("Facturas/"))
    #expect(plan.tree.contains("· "))
    #expect(plan.estimatedInputTokens > 0)
    #expect(plan.estimatedCost(model: "claude-haiku-5-5") != nil)
}

@Test func emptyFolderCannotBeLearned() throws {
    let dir = try TempDir()
    #expect(throws: LearnError.emptyFolder) { try RulesLearner(provider: ScriptedProvider { _ in "" }).plan(root: dir.url) }
}

@Test func draftProducesAValidRulesFile() async throws {
    let dir = try TempDir()
    try archive(dir)
    let provider = ScriptedProvider { _ in draftJSON }
    let learner = RulesLearner(provider: provider)
    let (text, usage) = try await learner.draft(try learner.plan(root: dir.url), language: .es)
    let rules = try RulesFile.parse(text)
    #expect(rules.header.inbox == "99-Pendiente")
    #expect(rules.body.contains("## Carpetas"))
    #expect(usage.inputTokens == 100)
    let request = try #require(await provider.requests.first)
    #expect(request.schemaName == "tria_rules_draft")
    #expect(request.system.contains("Write in Spanish"))
    #expect(request.userText.contains("Documento Facturas"))
}

@Test func invalidDraftIsRejected() async throws {
    let dir = try TempDir()
    try archive(dir)
    let bad = draftJSON.replacingOccurrences(of: "\"99-Pendiente\"", with: "\"../fuera\"")
    let learner = RulesLearner(provider: ScriptedProvider { _ in bad })
    await #expect(throws: LearnError.self) { try await learner.draft(try learner.plan(root: dir.url), language: .es) }
}

@Test func suggestsARuleFromACorrection() async throws {
    let provider = ScriptedProvider { _ in
        #"{"section":"Casos especiales","rule":"Los contratos de AutoRent van a 2-Contratos/Renting."}"#
    }
    let rules = try RulesFile.parse(WorkspaceFixture.defaultRules)
    let original = Proposal(action: .file, destination: "7-Facturas/Recibidas", filename: "Factura AutoRent.pdf",
                            documentType: "Factura", documentDate: nil, confidence: .medium, reason: "r", doubt: nil)
    let (draft, _) = try await RulesLearner(provider: provider).suggestRule(
        rules: rules, original: original, originalFilename: "scan.pdf",
        correctedDestination: "2-Contratos/Renting", correctedFilename: "Contrato Renting AutoRent - 2024-09.pdf",
        excerpt: "Contrato marco de renting")
    #expect(draft == RuleSuggestionDraft(section: "Casos especiales", rule: "Los contratos de AutoRent van a 2-Contratos/Renting."))
    let request = try #require(await provider.requests.first)
    #expect(request.userText.contains("Corrected: 2-Contratos/Renting/Contrato Renting AutoRent - 2024-09.pdf"))
    #expect(request.cachedContext == rules.raw)
}

@Test func unreadableSuggestionStillReportsWhatItCost() async throws {
    let provider = ScriptedProvider { _ in "no es JSON" }
    let rules = try RulesFile.parse(WorkspaceFixture.defaultRules)
    let original = Proposal(action: .file, destination: "7-Facturas/Recibidas", filename: "Factura.pdf",
                            documentType: "Factura", documentDate: nil, confidence: .medium, reason: "r", doubt: nil)
    do {
        _ = try await RulesLearner(provider: provider).suggestRule(
            rules: rules, original: original, originalFilename: "scan.pdf", correctedDestination: "2-Contratos",
            correctedFilename: "Contrato.pdf", excerpt: "Contrato")
        Issue.record("Debía fallar")
    } catch let failure as LearnFailure {
        #expect(failure.reason == .invalidDraft("not JSON"))
        #expect(failure.usage == TokenUsage(inputTokens: 100, outputTokens: 10))
    }
}
