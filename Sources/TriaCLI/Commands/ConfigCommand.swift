import ArgumentParser
import Foundation
import TriaKit

struct ConfigCommand: TriaSubcommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "config", abstract: L10n.help(.configAbstract))
    }

    @Option(help: .catalog(.configProvider)) var provider: ProviderID?
    @Option(help: .catalog(.configModel)) var model: String?
    @Flag(help: .catalog(.configSetKey)) var setKey = false
    @Flag(help: .catalog(.configDeleteKey)) var deleteKey = false

    func execute(_ env: CLIEnvironment) async throws {
        var config = try UserConfig.load(from: env.configURL)
        if provider != nil || model != nil {
            if let provider { config.provider = provider }
            if let model { config.model = model.isEmpty ? nil : model }
            try config.save(to: env.configURL)
            env.say(.configSaved, env.configURL.path)
        }
        if setKey {
            let prompt = env.t(.keyPrompt, config.provider.rawValue)
            let key = (env.terminal.isInteractive ? env.terminal.askSecret(prompt) : env.terminal.ask(""))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !key.isEmpty else { throw CLIError(env.t(.cancelled), code: 1) }
            try env.secrets.setAPIKey(key, for: config.provider)
            env.say(.keySaved)
        }
        if deleteKey {
            try env.secrets.deleteAPIKey(for: config.provider)
            env.say(.keyDeleted)
        }
        let keyDescription: String
        if let value = env.environment[config.provider.environmentKey], !value.trimmingCharacters(in: .whitespaces).isEmpty {
            keyDescription = env.t(.keyFromEnv, config.provider.environmentKey)
        } else if let stored = try env.secrets.apiKey(for: config.provider) {
            keyDescription = APIKeyResolver.masked(stored)
        } else {
            keyDescription = env.t(.keyNone)
        }
        env.say(.configShow, config.provider.rawValue, config.resolvedModel, keyDescription)
    }
}
