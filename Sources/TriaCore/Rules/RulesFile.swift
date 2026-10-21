import Foundation
import Yams

public enum NewFoldersPolicy: String, Sendable, Codable, CaseIterable {
    case never
    case subfoldersOnly = "subfolders_only"
    case anywhere
}

public struct RulesHeader: Sendable, Equatable {
    public var inbox: String
    public var duplicates: String
    public var protected: [String]
    public var newFolders: NewFoldersPolicy

    public init(inbox: String, duplicates: String, protected: [String] = [],
                newFolders: NewFoldersPolicy = .subfoldersOnly) {
        self.inbox = inbox
        self.duplicates = duplicates
        self.protected = protected
        self.newFolders = newFolders
    }
}

public enum RulesError: Error, Equatable, Sendable {
    case missingFrontmatter
    case invalidYAML(String)
    case missingKey(String)
    case invalidValue(key: String, value: String)
    case unsafePath(key: String, value: String)
    case overlappingFolders
}

/// `TRIA.md`: cabecera YAML con lo que se cumple de forma determinista y cuerpo en lenguaje natural.
/// Es la única fuente de verdad de las reglas (spec §6.2).
public struct RulesFile: Sendable, Equatable {
    public let header: RulesHeader
    public let body: String
    public let raw: String

    private struct RawHeader: Decodable {
        var inbox: String?
        var duplicates: String?
        var protected: [String]?
        var new_folders: String?
    }

    public static func parse(_ text: String) throws -> RulesFile {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { throw RulesError.missingFrontmatter }

        let yaml = lines[1..<end].joined(separator: "\n")
        var bodyLines = Array(lines[(end + 1)...])
        if bodyLines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { bodyLines.removeFirst() }
        let body = bodyLines.joined(separator: "\n")

        let rawHeader: RawHeader
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawHeader = RawHeader()
        } else {
            do { rawHeader = try YAMLDecoder().decode(RawHeader.self, from: yaml) }
            catch { throw RulesError.invalidYAML(String(describing: error)) }
        }

        let inbox = try folder(rawHeader.inbox, key: "inbox")
        let duplicates = try folder(rawHeader.duplicates, key: "duplicates")
        if overlaps(inbox, duplicates) { throw RulesError.overlappingFolders }

        let protected = try (rawHeader.protected ?? []).map { pattern -> String in
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("~")
                || trimmed.split(separator: "/").contains("..") {
                throw RulesError.unsafePath(key: "protected", value: pattern)
            }
            return trimmed.normalizedRelativePath
        }

        let policy: NewFoldersPolicy
        if let value = rawHeader.new_folders {
            guard let parsed = NewFoldersPolicy(rawValue: value) else {
                throw RulesError.invalidValue(key: "new_folders", value: value)
            }
            policy = parsed
        } else {
            policy = .subfoldersOnly
        }

        return RulesFile(
            header: RulesHeader(inbox: inbox, duplicates: duplicates, protected: protected, newFolders: policy),
            body: body, raw: text)
    }

    public static func render(header: RulesHeader, body: String) -> String {
        func quoted(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var lines = ["---", "inbox: \(quoted(header.inbox))", "duplicates: \(quoted(header.duplicates))"]
        if header.protected.isEmpty {
            lines.append("protected: []")
        } else {
            lines.append("protected:")
            lines += header.protected.map { "  - \(quoted($0))" }
        }
        lines += ["new_folders: \(header.newFolders.rawValue)", "---", ""]
        let text = lines.joined(separator: "\n") + body
        return text.hasSuffix("\n") ? text : text + "\n"
    }

    private static func folder(_ value: String?, key: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw RulesError.missingKey(key)
        }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let normalized = trimmed.normalizedRelativePath
        let components = normalized.split(separator: "/")
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || components.contains("..")
            || components.first == ".tria" || normalized.isEmpty {
            throw RulesError.unsafePath(key: key, value: value)
        }
        return normalized
    }

    private static func overlaps(_ a: String, _ b: String) -> Bool {
        let lhs = a.lowercased(), rhs = b.lowercased()
        return lhs == rhs || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
    }
}
