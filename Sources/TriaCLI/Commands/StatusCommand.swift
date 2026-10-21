import ArgumentParser
import TriaKit

struct StatusCommand: TriaSubcommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "status", abstract: L10n.help(.statusAbstract))
    }

    @Option(help: .catalog(.root)) var root: String?

    func execute(_ env: CLIEnvironment) async throws {
        let workspace = try env.workspace(root: root)
        // Sin key también funciona: el modelo sale de la configuración.
        let config = try UserConfig.load(from: env.configURL)
        let model = (try? env.provider())?.0.model ?? config.resolvedModel
        let items = try SortPipeline.status(workspace: workspace, provider: config.provider, model: model)
        // Sin perfil o sin lo mínimo, un aviso por la salida de error, en ámbar (spec del perfil, §4). Un NIF que no
        // cuadra avisa igual, con el mismo texto que `rules check`.
        if let file = workspace.profile {
            if !file.profile.isComplete { env.warn(.profileWarnMissing, L10n.fields(file.profile.missing, env.lang)) }
            if let taxID = file.profile.taxID, !SpanishTaxID.isValid(taxID) { env.warn(.profileWarnTaxID, taxID) }
        } else {
            env.warn(.profileNone)
        }
        if items.isEmpty { env.say(.nothingToDo) }
        for line in Presenter.status(items, env, style: env.style) { env.terminal.write(line) }
    }
}
