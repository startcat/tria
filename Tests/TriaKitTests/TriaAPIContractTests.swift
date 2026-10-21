import Foundation
import Testing
@testable import TriaKit

/// El contrato con `tria-api`: ida y vuelta por JSON, los topes y que el motor nunca los rebasa.
struct TriaAPIContractTests {
    private let status = TriaAPI.BuyerStatus(unlocked: true, trialRemaining: 12, balance: 480, documentsToday: 3,
                                             documentsDailyLimit: 1000, rulesChangesLeft: 49, suggestionsLeft: 50,
                                             environment: .sandbox)
    private let date = Date(timeIntervalSinceReferenceDate: 814_091_400.125)

    private func proposal(text: String = "FACTURA", images: [Data] = [Data([0xFF, 0xD8, 0xFF, 0x01])],
                          timeZone: String = "Europe/Madrid", tree: String = "7-Facturas/") -> ProposalParts {
        ProposalParts(rules: "# TRIA", tree: tree, profile: "# PERFIL", originalFilename: "doc_x.pdf", created: date,
                      modified: nil, text: text, pageCount: 2, method: .textLayer, images: images, feedback: nil,
                      timeZone: timeZone)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try TriaAPI.makeEncoder().encode(value)
        return try TriaAPI.makeDecoder().decode(T.self, from: data)
    }

    @Test func contractRoundTripsThroughJSON() throws {
        let credited = TriaAPI.CreditedTransaction(transactionId: "t1", productId: "cat.start.tria.pack500",
                                                   documents: 500, alreadyCredited: false)
        #expect(try roundTrip(status) == status)
        #expect(try roundTrip(TriaAPI.SessionRequest(appTransaction: "a.b.c")) == .init(appTransaction: "a.b.c"))
        let session = TriaAPI.SessionResponse(token: "tok", expiresAt: date, status: status)
        #expect(try roundTrip(session) == session)
        #expect(try roundTrip(TriaAPI.PurchasesRequest(transactions: ["x", "y"])).transactions == ["x", "y"])
        let purchases = TriaAPI.PurchasesResponse(credited: [credited], status: status)
        #expect(try roundTrip(purchases) == purchases)
        let complete = TriaAPI.CompleteResponse(text: "{}", usage: TokenUsage(inputTokens: 1, outputTokens: 2,
                                                cacheReadTokens: 3, cacheWriteTokens: 4), model: "m", charged: true,
                                                status: status)
        #expect(try roundTrip(complete) == complete)
        let buyer = TriaAPI.BuyerData(appTransactionId: "1", environment: .production, createdAt: date, status: status,
                                      purchases: [.init(transactionId: "t1", productId: "cat.start.tria.pack500", documents: 500,
                                                        creditedAt: date, refundedAt: date)],
                                      trialDocuments: 20, requestsLast90Days: 7,
                                      documentsByDay: ["2026-10-19": 3])
        #expect(try roundTrip(buyer) == buyer)
        let error = TriaAPI.ErrorBody(code: .balanceEmpty, message: "sin saldo", status: status)
        #expect(try roundTrip(error) == error)
        #expect(try roundTrip(TriaAPI.ErrorBody(code: .tooLarge, message: "x")).status == nil)
    }

    @Test func completeRequestKeepsImagesAndDates() throws {
        let image = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let request = TriaAPI.CompleteRequest(parts: .proposal(proposal(images: [image])))
        let back = try roundTrip(request)
        #expect(back == request)
        guard case .proposal(let p) = back.parts else { Issue.record("no es .proposal"); return }
        #expect(p.images == [image])
        #expect(p.created == date)
        for parts in [TriaRequestParts.rulesChange(.init(rules: "r", tree: "t", profile: nil, instruction: "i")),
                      .ruleSuggestion(.init(rules: "r", proposedDestination: "a", proposedFilename: "b",
                                            originalFilename: "c", correctedDestination: "d", correctedFilename: "e",
                                            excerpt: "x"))] {
            #expect(try roundTrip(TriaAPI.CompleteRequest(parts: parts)).parts == parts)
        }
    }

    @Test func completeRequestCarriesItsRequestId() throws {
        let id = "7C9E6679-7425-40DE-944B-E07FC1F90AE7"
        let request = TriaAPI.CompleteRequest(parts: .proposal(proposal()), requestId: id)
        #expect(try roundTrip(request) == request)
        #expect(try roundTrip(request).requestId == id)
        let json = String(decoding: try TriaAPI.makeEncoder().encode(request), as: UTF8.self)
        #expect(json.contains("\"requestId\":\"\(id)\""))
    }

    /// Una app de antes no lo manda: el JSON de siempre se sigue leyendo, sin `requestId`.
    @Test func completeRequestWithoutRequestIdStillDecodes() throws {
        let request = TriaAPI.CompleteRequest(parts: .proposal(proposal()))
        #expect(request.requestId == nil)
        let json = String(decoding: try TriaAPI.makeEncoder().encode(request), as: UTF8.self)
        #expect(!json.contains("requestId"))
        let parts = String(decoding: try TriaAPI.makeEncoder().encode(request.parts), as: UTF8.self)
        let old = try TriaAPI.makeDecoder().decode(TriaAPI.CompleteRequest.self, from: Data(#"{"parts":\#(parts)}"#.utf8))
        #expect(old == request)
        #expect(old.requestId == nil)
    }

    @Test func checkBoundsTheRequestId() throws {
        try TriaAPI.check(TriaAPI.CompleteRequest(parts: .proposal(proposal()), requestId: UUID().uuidString))
        try TriaAPI.check(TriaAPI.CompleteRequest(parts: .proposal(proposal())))
        do {
            try TriaAPI.check(TriaAPI.CompleteRequest(parts: .proposal(proposal()),
                                                      requestId: String(repeating: "a", count: TriaAPI.Limits.requestId + 1)))
            Issue.record("debía lanzar tooLarge en requestId")
        } catch let error as TriaAPI.LimitError {
            #expect(error.piece == "requestId")
        }
        // Las piezas se comprueban igual que con `check(_ parts:)`.
        var p = proposal()
        p.feedback = String(repeating: "a", count: TriaAPI.Limits.feedback + 1)
        #expect(throws: TriaAPI.LimitError.self) { try TriaAPI.check(TriaAPI.CompleteRequest(parts: .proposal(p))) }
    }

    /// Los topes diarios de «Pídeselo a Tria», los mismos en el servidor y en la app.
    @Test func dailyRulesLimitsAreFixed() {
        #expect(TriaAPI.Limits.rulesChangesPerDay == 50)
        #expect(TriaAPI.Limits.suggestionsPerDay == 50)
    }

    @Test func jsonShapeIsStable() throws {
        let json = try String(decoding: TriaAPI.makeEncoder().encode(
            TriaAPI.SessionResponse(token: "t", expiresAt: date, status: status)), as: UTF8.self)
        #expect(json.contains("\"expiresAt\":\"2026-10-19T"))
        #expect(json.contains(".125Z\""))
        #expect(json.contains("\"documentsDailyLimit\":1000"))
        let plain = Data(#"{"token":"t","expiresAt":"2026-10-19T08:30:00Z","status":\#(String(decoding: try TriaAPI.makeEncoder().encode(status), as: UTF8.self))}"#.utf8)
        #expect(try TriaAPI.makeDecoder().decode(TriaAPI.SessionResponse.self, from: plain).expiresAt.timeIntervalSince1970 == 1_792_398_600)
    }

    private func expectTooLarge(_ parts: TriaRequestParts, piece: String) {
        do {
            try TriaAPI.check(parts)
            Issue.record("debía lanzar tooLarge en \(piece)")
        } catch let error as TriaAPI.LimitError {
            #expect(error.code == .tooLarge)
            #expect(error.piece == piece)
            #expect(error.body().code == .tooLarge)
        } catch {
            Issue.record("error inesperado: \(error)")
        }
    }

    @Test func checkRejectsEachOversizedPart() throws {
        let big = { (n: Int) in String(repeating: "a", count: n) }
        let jpeg = Data(count: 10)
        expectTooLarge(.proposal(proposal(text: big(TriaAPI.Limits.text + 1))), piece: "text")
        expectTooLarge(.proposal(proposal(images: [jpeg, jpeg, jpeg])), piece: "images")
        expectTooLarge(.proposal(proposal(images: [jpeg, Data(count: TriaAPI.Limits.imageBytes + 1)])), piece: "images[1]")
        expectTooLarge(.proposal(proposal(timeZone: big(65))), piece: "timeZone")
        expectTooLarge(.proposal(proposal(tree: big(TriaAPI.Limits.tree + 1))), piece: "tree")
        var p = proposal()
        p.rules = big(TriaAPI.Limits.rules + 1)
        expectTooLarge(.proposal(p), piece: "rules")
        p = proposal(); p.profile = big(TriaAPI.Limits.profile + 1)
        expectTooLarge(.proposal(p), piece: "profile")
        p = proposal(); p.originalFilename = big(TriaAPI.Limits.filename + 1)
        expectTooLarge(.proposal(p), piece: "originalFilename")
        p = proposal(); p.feedback = big(TriaAPI.Limits.feedback + 1)
        expectTooLarge(.proposal(p), piece: "feedback")
        expectTooLarge(.rulesChange(.init(rules: "r", tree: "t", profile: nil, instruction: big(4_001))), piece: "instruction")
        expectTooLarge(.rulesChange(.init(rules: big(TriaAPI.Limits.rules + 1), tree: "t", profile: nil, instruction: "i")), piece: "rules")
        expectTooLarge(.ruleSuggestion(.init(rules: "r", proposedDestination: "a", proposedFilename: "b",
                                             originalFilename: "c", correctedDestination: "d", correctedFilename: "e",
                                             excerpt: big(16_001))), piece: "excerpt")
        expectTooLarge(.ruleSuggestion(.init(rules: "r", proposedDestination: "a", proposedFilename: big(513),
                                             originalFilename: "c", correctedDestination: "d", correctedFilename: "e",
                                             excerpt: "x")), piece: "proposedFilename")
    }

    @Test func checkAcceptsWhatTheEngineProduces() throws {
        let limits = ExtractionLimits()
        let tree = (0..<FolderTreeOptions().maxLines).map { "  carpeta-\($0)/ejemplo-\($0).pdf" }.joined(separator: "\n")
        let parts = TriaRequestParts.proposal(proposal(text: String(repeating: "é", count: limits.maxCharacters),
                                                        images: Array(repeating: Data(count: 200_000), count: limits.imagePages),
                                                        tree: tree))
        try TriaAPI.check(parts)
        // Justo en el tope también pasa.
        try TriaAPI.check(.proposal(proposal(text: String(repeating: "a", count: TriaAPI.Limits.text))))
    }

    @Test func checkAcceptsDecomposedAccents() throws {
        let e = "e\u{301}"
        let ok = String(repeating: e, count: 12_000)
        try TriaAPI.check(.proposal(proposal(text: ok)))
        try TriaAPI.check(.ruleSuggestion(.init(rules: "r", proposedDestination: "a", proposedFilename: "b",
                                                originalFilename: "c", correctedDestination: "d", correctedFilename: "e",
                                                excerpt: ok)))
        expectTooLarge(.proposal(proposal(text: String(repeating: e, count: 16_001))), piece: "text")
        expectTooLarge(.ruleSuggestion(.init(rules: "r", proposedDestination: "a", proposedFilename: "b",
                                             originalFilename: "c", correctedDestination: "d", correctedFilename: "e",
                                             excerpt: String(repeating: e, count: 16_001))), piece: "excerpt")
    }

    @Test func serviceLimitCarriesTheErrorCode() {
        #expect(LLMError.serviceLimit(TriaAPI.ErrorCode.tooLarge.rawValue) == .serviceLimit("tooLarge"))
    }

    @Test func refusedIsAnErrorCode() throws {
        let body = TriaAPI.ErrorBody(code: .refused, message: "x")
        let data = try TriaAPI.makeEncoder().encode(body)
        #expect(String(decoding: data, as: UTF8.self).contains("\"refused\""))
        #expect(try TriaAPI.makeDecoder().decode(TriaAPI.ErrorBody.self, from: data) == body)
    }

    /// La realimentación nunca pasa del tope: se recorta por grafemas, sin partir un carácter.
    @Test func proposalFeedbackIsClampedToTheLimit() throws {
        #expect(ProposalFeedback.clamped("corta") == "corta")
        let exact = String(repeating: "a", count: TriaAPI.Limits.feedback)
        #expect(ProposalFeedback.clamped(exact) == exact)
        let flags = String(repeating: "🇪🇸", count: TriaAPI.Limits.feedback + 10)
        let clamped = ProposalFeedback.clamped(flags)
        #expect(clamped.count == TriaAPI.Limits.feedback)
        #expect(clamped.unicodeScalars.count == 2 * TriaAPI.Limits.feedback)
        #expect(Set(clamped) == ["🇪🇸"])
        let accents = ProposalFeedback.clamped(String(repeating: "e\u{301}", count: TriaAPI.Limits.feedback + 1))
        #expect(accents.count == TriaAPI.Limits.feedback)
        #expect(accents.unicodeScalars.last == "\u{301}")
    }

    @Test func proposalFeedbackTextsAreFixed() {
        #expect(ProposalFeedback.truncated == "your answer was cut off; reply with the JSON object only")
        #expect(ProposalFeedback.unreadable("x") == "the response could not be read (x)")
        struct E: Error, CustomStringConvertible { var description: String { "boom" } }
        #expect(ProposalFeedback.invalidJSON(E()) == "your answer was not a valid JSON object for the schema (boom)")
    }
}
