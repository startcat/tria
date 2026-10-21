import Foundation

public enum Confidence: String, Codable, Sendable, CaseIterable {
    case high, medium, low
}

public enum ProposalAction: String, Codable, Sendable {
    case file, pending
}

public enum ProposalDecodingError: Error, Equatable, Sendable {
    case notJSON(String)
    case invalidDate(String)
}

/// Lo único que devuelve la IA: una propuesta. Nunca ejecuta nada (spec §6.4).
public struct Proposal: Codable, Sendable, Equatable {
    public var action: ProposalAction
    public var destination: String
    public var filename: String
    public var documentType: String
    public var documentDate: String?
    public var confidence: Confidence
    public var reason: String
    public var doubt: String?

    enum CodingKeys: String, CodingKey {
        case action, destination, filename
        case documentType = "document_type"
        case documentDate = "document_date"
        case confidence, reason, doubt
    }

    public init(action: ProposalAction, destination: String, filename: String, documentType: String,
                documentDate: String?, confidence: Confidence, reason: String, doubt: String?) {
        self.action = action
        self.destination = destination
        self.filename = filename
        self.documentType = documentType
        self.documentDate = documentDate
        self.confidence = confidence
        self.reason = reason
        self.doubt = doubt
    }

    public static let jsonSchema: JSONValue = [
        "type": "object",
        "additionalProperties": false,
        "required": ["action", "destination", "filename", "document_type", "document_date",
                     "confidence", "reason", "doubt"],
        "properties": [
            "action": ["type": "string", "enum": ["file", "pending"]],
            "destination": ["type": "string",
                            "description": "Folder path relative to the archive root, '/' separated, without file name."],
            "filename": ["type": "string", "description": "New file name, including the original extension."],
            "document_type": ["type": "string"],
            "document_date": ["anyOf": [["type": "string"], ["type": "null"]],
                              "description": "YYYY-MM-DD when the document has a full date, else null."],
            "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
            "reason": ["type": "string"],
            "doubt": ["anyOf": [["type": "string"], ["type": "null"]]],
        ],
    ]

    public static func decode(_ text: String) throws -> Proposal {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw ProposalDecodingError.notJSON(String(text.prefix(200)))
        }
        var proposal: Proposal
        do {
            proposal = try JSONDecoder().decode(Proposal.self, from: Data(text[start...end].utf8))
        } catch {
            throw ProposalDecodingError.notJSON(String(describing: error))
        }
        if let date = proposal.documentDate?.trimmingCharacters(in: .whitespaces) {
            if date.isEmpty {
                proposal.documentDate = nil
            } else if date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil {
                throw ProposalDecodingError.invalidDate(date)
            }
        }
        return proposal
    }
}
