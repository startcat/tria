import Foundation
import Testing
@testable import TriaKit

private let json = """
{"action":"file","destination":"1-Modelos Tributarios/Modelo 303 - IVA","filename":"Modelo 303 - 2023 - 1T.pdf",
 "document_type":"Modelo 303","document_date":"2023-04-20","confidence":"high",
 "reason":"Autoliquidación de IVA del 1T de 2023.","doubt":null}
"""

@Test func decodesSnakeCaseJSON() throws {
    let proposal = try Proposal.decode(json)
    #expect(proposal == Proposal(
        action: .file, destination: "1-Modelos Tributarios/Modelo 303 - IVA",
        filename: "Modelo 303 - 2023 - 1T.pdf", documentType: "Modelo 303", documentDate: "2023-04-20",
        confidence: .high, reason: "Autoliquidación de IVA del 1T de 2023.", doubt: nil))
}

@Test func toleratesTextAroundTheObject() throws {
    #expect(try Proposal.decode("Aquí tienes:\n\(json)\nFin").confidence == .high)
}

@Test func emptyDateBecomesNil() throws {
    let text = json.replacingOccurrences(of: "\"2023-04-20\"", with: "\"\"")
    #expect(try Proposal.decode(text).documentDate == nil)
}

@Test func rejectsMalformedDateAndNonJSON() {
    let badDate = json.replacingOccurrences(of: "2023-04-20", with: "20/04/2023")
    #expect(throws: ProposalDecodingError.invalidDate("20/04/2023")) { try Proposal.decode(badDate) }
    #expect(throws: ProposalDecodingError.self) { try Proposal.decode("no es json") }
    #expect(throws: ProposalDecodingError.self) { try Proposal.decode(#"{"action":"file"}"#) }
}

@Test func schemaIsStrictAndRequiresEveryField() throws {
    let schema = Proposal.jsonSchema
    #expect(schema["additionalProperties"] == .bool(false))
    let required = Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    #expect(required == ["action", "destination", "filename", "document_type", "document_date",
                         "confidence", "reason", "doubt"])
    #expect(schema["properties"]?["confidence"]?["enum"] == ["high", "medium", "low"])
}
