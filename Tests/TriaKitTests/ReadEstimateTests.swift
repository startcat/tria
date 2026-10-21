import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

@Test func perDocumentIsTheRulesPlusAFixedMargin() {
    let estimate = ReadEstimate.tokensPerDocument(rulesCharacters: 2_000)
    #expect(estimate.input == 3_000)   // (2.000 + 6.000 + 4.000 + 3) / 4
    #expect(estimate.output == 300)
}

@Test func readingCostsTheEstimateTimesTheDocuments() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let perDocument = ReadEstimate.tokensPerDocument(rulesCharacters: ws.rules.raw.count)

    let cost = try #require(ReadEstimate.cost(documents: 120, workspace: ws, model: "claude-sonnet-5-5"))

    // Sonnet 5.5: 2 USD por millón de tokens de entrada y 10 de salida.
    let expected = (Double(perDocument.input * 120) * 2.00 + Double(perDocument.output * 120) * 10.00) / 1_000_000
    #expect(abs(cost - expected) < 0.000_001)
    #expect(ReadEstimate.cost(documents: 0, workspace: ws, model: "claude-sonnet-5-5") == 0)
    #expect(ReadEstimate.cost(documents: 120, workspace: ws, model: "modelo-inventado") == nil)
}

@Test func theEvaluatorEstimateDoesNotChange() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    for n in 1...10 { try dir.write("7-Facturas/Recibidas/f\(n).pdf", "f\(n)") }

    let plan = try Evaluator(provider: ScriptedProvider { _ in "" }).plan(workspace: ws, options: EvalOptions(sampleSize: 4))

    // La cuenta de antes, escrita a mano: reglas + 6.000 + 4.000 caracteres de entrada y 300 tokens de salida.
    #expect(plan.sample.count == 4)
    #expect(plan.estimatedInputTokens == Pricing.estimatedTokens(characters: ws.rules.raw.count + 6_000 + 4_000) * 4)
    #expect(plan.estimatedOutputTokens == 300 * 4)
}
