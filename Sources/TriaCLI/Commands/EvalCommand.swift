import ArgumentParser
import Foundation
import TriaKit

struct EvalCommand: TriaSubcommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "eval",
            abstract: L10n.help(.evalAbstract))
    }

    @Argument(help: .catalog(.evalArchive)) var archive: String?
    @Option(help: .catalog(.evalRules)) var rules: String?
    @Flag(help: .catalog(.evalSynthetic)) var synthetic = false
    @Option(help: .catalog(.evalSample)) var sample = 200
    @Option(help: .catalog(.evalSeed)) var seed: UInt64 = 42
    @Option(help: .catalog(.evalOutput)) var out: String?
    @Option(help: .catalog(.evalBaseline)) var baseline: String?
    @Flag(help: .catalog(.evalJSON)) var json = false
    @Flag(name: .shortAndLong, help: .catalog(.evalYes)) var yes = false

    func execute(_ env: CLIEnvironment) async throws {
        guard synthetic || archive != nil else { throw CLIError(env.t(.evalNeedsArchive)) }
        // La referencia se lee antes de confirmar el coste y de llamar a la IA: una ruta mal escrita falla aquí, sin
        // gastar nada, y no después de una evaluación pagada.
        let reference = try baseline.map { try Self.readBaseline($0, env) }
        let (provider, config) = try env.provider()

        var scratch: URL?
        defer { if let scratch { try? FileManager.default.removeItem(at: scratch) } }
        let workspace: Workspace
        if synthetic {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tria-synthetic-\(UUID().uuidString)")
            scratch = directory
            workspace = try SyntheticArchive.build(at: directory)
        } else if let rules {
            workspace = try Workspace.open(at: env.resolve(archive), rulesFile: env.resolve(rules))
        } else {
            workspace = try Workspace.open(at: env.resolve(archive))
        }

        let options = EvalOptions(sampleSize: sample, seed: seed)
        let evaluator = Evaluator(provider: provider)
        let plan = try evaluator.plan(workspace: workspace, options: options)
        let estimate = L10n.money(plan.estimatedCost(model: config.resolvedModel), env.lang)
        guard try env.confirm(.evalEstimate, String(plan.sample.count), config.resolvedModel, estimate, assumeYes: yes) else {
            env.say(.cancelled)
            return
        }

        let report = try await evaluate(evaluator, plan: plan, workspace: workspace, options: options, model: provider.model,
                                   env: env)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let out {
            try encoder.encode(report).write(to: env.resolve(out), options: .atomic)
            if !json { env.say(.evalSaved, out) }
        }
        // Se compara antes de las cifras: el acierto sale en verde, o en rojo si baja (spec CLI §4). Un informe parcial
        // no se compara, porque el acierto de unos pocos documentos no es comparable.
        var compared: (reference: EvalReport, comparison: EvalComparison)?
        if let reference, report.interruption == nil {
            compared = (reference, Evaluator.compare(report, baseline: reference))
        }
        if json {
            env.terminal.write(String(decoding: try encoder.encode(report), as: UTF8.self))
        } else {
            let regressed = compared?.comparison.regressed == true
            env.say(regressed ? .danger : .success, .evalFolder, L10n.percent(report.folderAccuracy, env.lang))
            env.say(.evalFilename, L10n.percent(report.filenameExactRate, env.lang), L10n.percent(report.filenameFuzzyRate, env.lang))
            env.say(.evalPending, L10n.percent(report.pendingRate, env.lang), String(report.unreadableCount))
            for confidence in Confidence.allCases {
                guard let stats = report.byConfidence[confidence.rawValue] else { continue }
                env.say(.evalByConfidence, Presenter.confidence(confidence, env), String(stats.count),
                        L10n.percent(stats.accuracy, env.lang))
            }
            env.terminal.write(Presenter.cost(report.usage, model: report.model, env, style: env.style))
        }

        if let interruption = report.interruption, !json {
            env.say(.warning, .evalInterrupted, String(report.sampleSize), String(plan.sample.count), interruption)
        }
        if baseline != nil {
            guard let compared else { throw CLIError(env.t(.evalBaselineSkipped)) }
            if compared.comparison.regressed {
                let points = String(format: "%.1f", -compared.comparison.folderDelta * 100)
                env.say(.danger, .evalRegressed, env.lang == .en ? points : points.replacingOccurrences(of: ".", with: ","))
                throw ExitCode(1)
            }
            if !json { env.say(.success, .evalNoRegression, L10n.percent(compared.reference.folderAccuracy, env.lang)) }
        }
    }

    /// El informe de `--baseline`, con un error claro si no se puede leer o no es un informe.
    private static func readBaseline(_ path: String, _ env: CLIEnvironment) throws -> EvalReport {
        guard let data = try? Data(contentsOf: env.resolve(path)) else {
            throw CLIError(env.t(.evalBaselineUnreadable, path))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let report = try? decoder.decode(EvalReport.self, from: data) else {
            throw CLIError(env.t(.evalBaselineInvalid, path))
        }
        return report
    }

    /// Evalúa con la barra de progreso en la salida de errores (spec CLI §4). Con `--json`, sin animación.
    private func evaluate(_ evaluator: Evaluator, plan: EvalPlan, workspace: Workspace, options: EvalOptions, model: String,
                     env: CLIEnvironment) async throws -> EvalReport {
        guard !json else { return try await evaluator.run(plan, workspace: workspace, options: options) }
        let title = env.t(.evalRunning, String(plan.sample.count), model)
        return try await env.terminal.withActivity(title, done: { report, seconds in
            Presenter.done(L10n.count(report.sampleSize, .evalDoneOne, .evalDoneMany, env.lang, String(seconds)),
                           style: env.errorStyle)
        }) { activity in
            try await evaluator.run(plan, workspace: workspace, options: options, progress: { done, total in
                activity.update(title, progress: ActivityProgress(done: done, total: total))
            })
        }
    }
}
