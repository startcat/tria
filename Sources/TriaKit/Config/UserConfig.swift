import Foundation

public enum ConfigError: Error, Equatable, Sendable {
    case invalidLine(Int, String)
    case unknownProvider(String)
}

/// Configuración personal (proveedor y modelo). Vive fuera del espacio y nunca contiene keys (spec §6.1).
/// Formato: subconjunto plano de TOML (`clave = "valor"`).
public struct UserConfig: Sendable, Equatable {
    public var provider: ProviderID
    public var model: String?

    public init(provider: ProviderID = .anthropic, model: String? = nil) {
        self.provider = provider
        self.model = model
    }

    public var resolvedModel: String { model ?? provider.defaultModel }

    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("tria/config.toml")
        }
        let home = environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".config/tria/config.toml")
    }

    public static func load(from url: URL) throws -> UserConfig {
        guard let data = FileManager.default.contents(atPath: url.path) else { return UserConfig() }
        return try parse(String(decoding: data, as: UTF8.self))
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(render().utf8).write(to: url, options: .atomic)
    }

    public static func parse(_ text: String) throws -> UserConfig {
        var config = UserConfig()
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let equals = line.firstIndex(of: "=") else { throw ConfigError.invalidLine(index + 1, line) }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            switch key {
            case "provider":
                guard let provider = ProviderID(rawValue: value) else { throw ConfigError.unknownProvider(value) }
                config.provider = provider
            case "model":
                config.model = value.isEmpty ? nil : value
            default:
                continue
            }
        }
        return config
    }

    public func render() -> String {
        var lines = ["# Lyncat Tria — configuración personal (no contiene keys)", "provider = \"\(provider.rawValue)\""]
        if let model { lines.append("model = \"\(model)\"") }
        return lines.joined(separator: "\n") + "\n"
    }
}
