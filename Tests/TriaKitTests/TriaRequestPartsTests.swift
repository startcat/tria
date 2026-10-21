import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

/// Las piezas de cada petición (para que `tria-api` la monte igual) dan la petición de siempre, con `parts` puesto.
struct TriaRequestPartsTests {
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])

    private func document(images: [Data] = []) -> DocumentContext {
        DocumentContext(originalFilename: "doc_x.pdf", created: Date(timeIntervalSince1970: 1_700_000_000), modified: nil,
                        extracted: ExtractedDocument(text: "FACTURA 2025-014", pageCount: 2, method: .textLayer,
                                                     needsImage: !images.isEmpty, images: images))
    }

    @Test func proposalPartsBuildTheSameRequest() throws {
        let rules = try RulesFile.parse(WorkspaceFixture.defaultRules)
        let profile = try ProfileFile.parse(ProfileFile.render(Profile(kind: .sl, name: "EMPRESA EJEMPLO SL", taxID: "B00000000"),
                                                           language: .es))
        let doc = document(images: [jpeg])
        let request = PromptBuilder.request(rules: rules, tree: "7-Facturas/", profile: profile, document: doc,
                                            feedback: "no vale")
        #expect(request.system == PromptBuilder.systemPrompt)
        #expect(request.cachedContext == """
        # Filing rules (TRIA.md)

        \(rules.raw)

        # Owner profile (PERFIL.md)

        \(profile.raw)

        # Archive folder tree

        Inbox folder (never a destination): \(rules.header.inbox)
        Duplicates folder (never a destination): \(rules.header.duplicates)
        New folders policy: new subfolders may be created inside existing top-level folders, but no new top-level folders
        Folders marked [protected] can never be used.

        7-Facturas/
        """)
        #expect(request.userText == PromptBuilder.userText(doc, feedback: "no vale"))
        #expect(request.images == [LLMImage(jpeg: jpeg)])
        #expect(request.schemaName == "tria_proposal")
        #expect(request.schema == Proposal.jsonSchema)
        #expect(request.maxOutputTokens == 4096)
        #expect(request.parts == .proposal(ProposalParts(
            rules: rules.raw, tree: "7-Facturas/", profile: profile.raw, originalFilename: "doc_x.pdf",
            created: doc.created, modified: nil, text: "FACTURA 2025-014", pageCount: 2, method: .textLayer,
            images: [jpeg], feedback: "no vale")))
        // Las piezas solas dan lo mismo.
        #expect(try request.parts?.makeRequest() == request)
    }

    /// Una realimentación más larga que el tope del contrato se recorta al armar las piezas, y el texto sale de esas
    /// mismas piezas: con clave propia se envía lo mismo que montaría el servidor.
    @Test func aLongFeedbackIsClampedInThePartsAndTheText() throws {
        let rules = try RulesFile.parse(WorkspaceFixture.defaultRules)
        let doc = document()
        let long = String(repeating: "'7-Facturas/2013' is protected; ", count: 100)
        let clamped = ProposalFeedback.clamped(long)
        #expect(clamped.count == TriaAPI.Limits.feedback)
        let request = PromptBuilder.request(rules: rules, tree: "7-Facturas/", document: doc, feedback: long)
        let parts = try #require(request.parts)
        try TriaAPI.check(parts)
        guard case .proposal(let p) = parts else { Issue.record("\(parts)"); return }
        #expect(p.feedback == clamped)
        #expect(request.userText == PromptBuilder.userText(doc, feedback: clamped))
        #expect(try parts.makeRequest() == request)
    }

    @Test func rulesChangePartsBuildTheSameRequest() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        let request = try RulesAsker.request("  Las facturas de la luz van a Suministros ", in: ws)
        #expect(request.system == RulesChangePrompt.systemPrompt)
        #expect(request.system == RulesAsker.systemPrompt)
        #expect(request.cachedContext == (try RulesAsker.cachedContext(for: ws)))
        #expect(request.cachedContext.contains("<<<SECTION s2\n"))
        #expect(request.cachedContext.contains("Inbox folder: 99-Pendiente"))
        #expect(request.userText == "# What the user wants\n\n<<<REQUEST\nLas facturas de la luz van a Suministros\nREQUEST>>>")
        #expect(request.schemaName == "tria_rules_change")
        #expect(request.schema == RulesAsker.schema)
        #expect(request.maxOutputTokens == 8000)
        #expect(request.images.isEmpty)
        let parts = RulesChangeParts(rules: ws.rules.raw, tree: try ws.folderTree(), profile: ws.profile?.raw,
                                     instruction: "  Las facturas de la luz van a Suministros ")
        #expect(request.parts == .rulesChange(parts))
        #expect(try request.parts?.makeRequest() == request)
        #expect(try RulesChangePrompt.cachedContext(rules: parts.rules, tree: parts.tree, profile: parts.profile)
                == request.cachedContext)
    }

    @Test func suggestionPartsBuildTheSameRequest() async throws {
        let provider = ScriptedProvider { _ in #"{"section":"Casos especiales","rule":"r"}"# }
        let rules = try RulesFile.parse(WorkspaceFixture.defaultRules)
        let original = Proposal(action: .file, destination: "7-Facturas/Recibidas", filename: "Factura AutoRent.pdf",
                                documentType: "Factura", documentDate: nil, confidence: .medium, reason: "r", doubt: nil)
        _ = try await RulesLearner(provider: provider).suggestRule(
            rules: rules, original: original, originalFilename: "scan.pdf", correctedDestination: "2-Contratos/Renting",
            correctedFilename: "Contrato.pdf", excerpt: "Contrato marco")
        let request = try #require(await provider.requests.first)
        #expect(request.system == RuleSuggestionPrompt.systemPrompt)
        #expect(request.cachedContext == rules.raw)
        #expect(request.userText == """
        Original file name: scan.pdf
        Proposed: 7-Facturas/Recibidas/Factura AutoRent.pdf
        Corrected: 2-Contratos/Renting/Contrato.pdf

        <<<DOCUMENT
        Contrato marco
        DOCUMENT>>>
        """)
        #expect(request.schemaName == "tria_rule_suggestion")
        #expect(request.schema == RuleSuggestionPrompt.schema)
        #expect(request.maxOutputTokens == 1000)
        #expect(request.images.isEmpty)
        #expect(request.parts == .ruleSuggestion(SuggestionParts(
            rules: rules.raw, proposedDestination: "7-Facturas/Recibidas", proposedFilename: "Factura AutoRent.pdf",
            originalFilename: "scan.pdf", correctedDestination: "2-Contratos/Renting",
            correctedFilename: "Contrato.pdf", excerpt: "Contrato marco")))
        #expect(try request.parts?.makeRequest() == request)
    }

    @Test func partsRoundTripThroughJSON() throws {
        let all: [TriaRequestParts] = [
            .proposal(ProposalParts(rules: "r", tree: "t", profile: nil, originalFilename: "a.pdf",
                                    created: Date(timeIntervalSince1970: 1_700_000_000), modified: nil, text: "x",
                                    pageCount: nil, method: .ocr, images: [jpeg, Data([1, 2, 3])], feedback: "f",
                                    timeZone: "Europe/Madrid")),
            .rulesChange(RulesChangeParts(rules: "r", tree: "t", profile: "p", instruction: "i")),
            .ruleSuggestion(SuggestionParts(rules: "r", proposedDestination: "a", proposedFilename: "b",
                                            originalFilename: "c", correctedDestination: "d", correctedFilename: "e",
                                            excerpt: "x")),
        ]
        for parts in all {
            let data = try JSONEncoder().encode(parts)
            let back = try JSONDecoder().decode(TriaRequestParts.self, from: data)
            #expect(back == parts)
            if case .proposal(let p) = back { #expect(p.timeZone == "Europe/Madrid") }
        }
    }

    @Test func feedbackGoesIntoTheUserText() throws {
        let rules = try RulesFile.parse(WorkspaceFixture.defaultRules)
        var parts = ProposalParts(rules: rules.raw, tree: "", profile: nil, originalFilename: "a.pdf", created: nil,
                                  modified: nil, text: "x", pageCount: 1, method: .textLayer, images: [], feedback: nil)
        let plain = try TriaRequestParts.proposal(parts).makeRequest()
        #expect(!plain.userText.contains("Your previous answer was rejected"))
        parts.feedback = "'7-Facturas/2013' is protected"
        let retry = try TriaRequestParts.proposal(parts).makeRequest()
        #expect(retry.userText.contains("Your previous answer was rejected: '7-Facturas/2013' is protected"))
    }

    @Test func fileDatesFollowThePartsTimeZone() throws {
        let rules = try RulesFile.parse(WorkspaceFixture.defaultRules)
        // 2025-03-10 23:30 UTC es ya el 11 en Madrid (UTC+1).
        let instant = Date(timeIntervalSince1970: 1_741_649_400)
        func line(_ zone: String) throws -> String {
            let parts = ProposalParts(rules: rules.raw, tree: "", profile: nil, originalFilename: "a.pdf",
                                      created: instant, modified: instant, text: "x", pageCount: 1,
                                      method: .textLayer, images: [], feedback: nil, timeZone: zone)
            return try TriaRequestParts.proposal(parts).makeRequest().userText
        }
        #expect(try line("Europe/Madrid").contains("File dates: created 2025-03-11, modified 2025-03-11"))
        #expect(try line("UTC").contains("File dates: created 2025-03-10, modified 2025-03-10"))
        #expect(try line("America/Los_Angeles").contains("created 2025-03-10"))
        // Un identificador desconocido no rompe: usa la zona actual.
        _ = try line("No/Existe")
        // El cliente escribe la fecha en su zona.
        let doc = DocumentContext(originalFilename: "a.pdf", created: instant, modified: nil,
                                  extracted: ExtractedDocument(text: "x", pageCount: 1, method: .textLayer))
        let request = PromptBuilder.request(rules: rules, tree: "", document: doc)
        guard case .proposal(let parts)? = request.parts else { Issue.record("sin piezas"); return }
        #expect(parts.timeZone == TimeZone.current.identifier)
        #expect(request.userText == PromptBuilder.userText(doc))
    }

    @Test func learnerForwardsItsPromptToRuleSuggestionPrompt() {
        #expect(RulesLearner.suggestionSystemPrompt == RuleSuggestionPrompt.systemPrompt)
        #expect(RulesLearner.suggestionSchema == RuleSuggestionPrompt.schema)
    }

    @Test func unreadableRulesThrow() {
        let parts = ProposalParts(rules: "sin cabecera", tree: "", profile: nil, originalFilename: "a.pdf", created: nil,
                                  modified: nil, text: "x", pageCount: nil, method: .plainText, images: [], feedback: nil)
        #expect(throws: RulesError.self) { try TriaRequestParts.proposal(parts).makeRequest() }
    }
}
