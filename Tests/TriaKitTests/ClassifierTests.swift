import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private func document(_ name: String = "doc_x.pdf") -> DocumentContext {
    DocumentContext(originalFilename: name, created: nil, modified: nil,
                    extracted: ExtractedDocument(text: "Modelo 303 1T 2023", pageCount: 1, method: .textLayer))
}

private let good = ScriptedProvider.proposalJSON(destination: "1-Modelos Tributarios/Modelo 303 - IVA",
                                                 filename: "Modelo 303 - 2023 - 1T.pdf")

@Test func validProposalIsValidated() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let provider = ScriptedProvider { _ in good }
    let (outcome, usage) = try await Classifier(provider: provider, workspace: ws, tree: "").classify(document())
    guard case .proposed(let proposal, let destination) = outcome else { Issue.record("\(outcome)"); return }
    #expect(destination == "1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf")
    #expect(proposal.confidence == .high)
    #expect(usage.inputTokens == 100)
}

@Test func modelDoubtBecomesPending() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let provider = ScriptedProvider { _ in
        ScriptedProvider.proposalJSON(action: "pending", destination: "", filename: "", confidence: "low",
                                      doubt: "No se ve la fecha")
    }
    let (outcome, _) = try await Classifier(provider: provider, workspace: ws, tree: "").classify(document())
    guard case .pending(let proposal, .modelDoubt(let doubt)) = outcome else { Issue.record("\(outcome)"); return }
    #expect(doubt == "No se ve la fecha")
    #expect(proposal?.action == .pending)
}

@Test func invalidProposalIsRetriedOnceWithFeedback() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let bad = ScriptedProvider.proposalJSON(destination: "7-Facturas/2013/1T", filename: "Factura.pdf")
    let provider = ScriptedProvider { request in
        request.userText.contains("previous answer was rejected") ? good : bad
    }
    let (outcome, usage) = try await Classifier(provider: provider, workspace: ws, tree: "").classify(document())
    guard case .proposed = outcome else { Issue.record("\(outcome)"); return }
    #expect(usage.inputTokens == 200)
    let second = try #require(await provider.requests.last)
    #expect(second.userText.contains("is protected"))
}

@Test func twoInvalidAnswersEndPending() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let provider = ScriptedProvider { _ in ScriptedProvider.proposalJSON(destination: "../fuera", filename: "x.pdf") }
    let (outcome, _) = try await Classifier(provider: provider, workspace: ws, tree: "").classify(document())
    guard case .pending(_, .invalidProposal(let feedback)) = outcome else { Issue.record("\(outcome)"); return }
    #expect(feedback.contains("must be relative"))
    #expect(await provider.requests.count == 2)
}

@Test func nonJSONIsRetried() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let provider = ScriptedProvider { request in request.userText.contains("rejected") ? good : "no sé" }
    let (outcome, _) = try await Classifier(provider: provider, workspace: ws, tree: "").classify(document())
    guard case .proposed = outcome else { Issue.record("\(outcome)"); return }
}

@Test func refusalIsPendingAndTransientErrorsPropagate() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let refusing = ScriptedProvider { _ in throw LLMError.refused }
    let (outcome, _) = try await Classifier(provider: refusing, workspace: ws, tree: "").classify(document())
    #expect(outcome == .pending(nil, .refused))

    let limited = ScriptedProvider { _ in throw LLMError.rateLimited }
    await #expect(throws: LLMError.rateLimited) {
        try await Classifier(provider: limited, workspace: ws, tree: "").classify(document())
    }
}

/// Una cancelación no es un rechazo del documento: se propaga, y el documento no queda como `providerError`.
@Test func aCancellationPropagatesInsteadOfBecomingAProviderError() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let cancelled = ScriptedProvider { _ in throw CancellationError() }
    await #expect(throws: CancellationError.self) {
        try await Classifier(provider: cancelled, workspace: ws, tree: "").classify(document())
    }

    // Lo mismo si la tarea ya está cancelada y el proveedor lo cuenta con otro error (p. ej. `URLError(.cancelled)`).
    let other = ScriptedProvider { _ in throw URLError(.cancelled) }
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await Classifier(provider: other, workspace: ws, tree: "").classify(document())
    }
    await #expect(throws: CancellationError.self) { try await task.value }

    // Sin cancelar, un error así sigue siendo un rechazo del documento.
    let (outcome, _) = try await Classifier(provider: other, workspace: ws, tree: "").classify(document())
    guard case .pending(nil, .providerError) = outcome else { Issue.record("\(outcome)"); return }
}

/// La realimentación del reintento lleva lo que propuso el modelo, que puede ser larguísimo: con la IA de Tria iría al
/// servidor en las piezas y, pasado el tope, el segundo intento (el gratis) daría 413. Se recorta al tope del contrato.
@Test func theRetryFeedbackNeverExceedsTheContractLimit() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let long = "../" + String(repeating: "carpeta/", count: 400)
    let provider = ScriptedProvider { request in
        request.userText.contains("previous answer was rejected")
            ? good : ScriptedProvider.proposalJSON(destination: long, filename: "x.pdf")
    }
    let (outcome, _) = try await Classifier(provider: provider, workspace: ws, tree: "").classify(document())
    guard case .proposed = outcome else { Issue.record("\(outcome)"); return }
    let parts = try #require(await provider.requests.last?.parts)
    try TriaAPI.check(parts)
    guard case .proposal(let p) = parts, let feedback = p.feedback else { Issue.record("\(parts)"); return }
    #expect(feedback.count == TriaAPI.Limits.feedback)
    #expect(feedback.hasPrefix("destination '../carpeta/"))
}

@Test func reportsEveryRequestForShowPrompt() async throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let seen = SeenRequests()
    let classifier = Classifier(provider: ScriptedProvider { _ in good }, workspace: ws, tree: "TREE",
                                onRequest: { request in Task { await seen.add(request) } })
    _ = try await classifier.classify(document())
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(await seen.count == 1)
}

private actor SeenRequests {
    var count = 0
    func add(_ request: LLMRequest) { count += 1 }
}
