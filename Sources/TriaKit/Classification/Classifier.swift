import Foundation

public enum PendingReason: Codable, Sendable, Equatable {
    case modelDoubt(String)
    case invalidProposal(String)
    case unreadable(String)
    case unsupported(String)
    case encrypted
    case refused
    case offline
    case paused(String)
    /// El proveedor ha rechazado este documento (p. ej. HTTP 400); el resto del lote sigue.
    case providerError(String)
    /// Quien embebe el motor (`admit`) ha dejado el documento en espera: no se ha enviado a la IA ni se guarda en la caché.
    case held
}

public enum ClassificationOutcome: Codable, Sendable, Equatable {
    case proposed(Proposal, destination: String)
    case pending(Proposal?, PendingReason)
}

/// Pide la propuesta, la decodifica y la valida, con un reintento con feedback (spec §6.3, pasos 4-5).
public struct Classifier: Sendable {
    public let provider: any LLMProvider
    public let workspace: Workspace
    public let tree: String
    public let onRequest: (@Sendable (LLMRequest) -> Void)?

    public init(provider: any LLMProvider, workspace: Workspace, tree: String,
                onRequest: (@Sendable (LLMRequest) -> Void)? = nil) {
        self.provider = provider
        self.workspace = workspace
        self.tree = tree
        self.onRequest = onRequest
    }

    public func classify(_ document: DocumentContext, reserved: Set<String> = []) async throws -> (ClassificationOutcome, TokenUsage) {
        var usage = TokenUsage.zero
        var feedback: String?
        var lastProposal: Proposal?
        let validator = Validator(workspace: workspace)

        for _ in 0..<2 {
            let request = PromptBuilder.request(rules: workspace.rules, tree: tree, profile: workspace.profile,
                                                document: document, feedback: feedback)
            onRequest?(request)
            let response: LLMResponse
            do {
                response = try await provider.complete(request)
            } catch LLMError.refused {
                return (.pending(nil, .refused), usage)
            } catch LLMError.truncated {
                feedback = ProposalFeedback.truncated
                continue
            } catch LLMError.badResponse(let message) {
                feedback = ProposalFeedback.unreadable(message)
                continue
            } catch let error as LLMError where error.isTransient || error.isFatal {
                throw error
            } catch {
                // Una lectura cancelada no es un rechazo del documento: se propaga y no se guarda, para leerlo otra vez.
                // También si el proveedor cuenta la cancelación con otro error (`URLError(.cancelled)`).
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                // Un rechazo de este documento (p. ej. HTTP 400) lo deja pendiente; el resto del lote sigue (spec §10).
                return (.pending(nil, .providerError(Self.describe(error))), usage)
            }
            usage = usage + response.usage

            let proposal: Proposal
            do {
                proposal = try Proposal.decode(response.text)
            } catch {
                feedback = ProposalFeedback.invalidJSON(error)
                continue
            }
            lastProposal = proposal
            if proposal.action == .pending {
                return (.pending(proposal, .modelDoubt(proposal.doubt ?? proposal.reason)), usage)
            }
            switch validator.validate(proposal, originalFilename: document.originalFilename, reserved: reserved) {
            case .success(let destination): return (.proposed(proposal, destination: destination), usage)
            case .failure(let error): feedback = error.feedback
            }
        }
        return (.pending(lastProposal, .invalidProposal(feedback ?? "invalid proposal")), usage)
    }

    static func describe(_ error: Error) -> String {
        if case LLMError.rejected(let status, let message) = error { return "HTTP \(status): \(message)" }
        return String(describing: error)
    }
}
