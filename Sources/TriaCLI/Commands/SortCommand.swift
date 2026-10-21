import ArgumentParser
import Foundation
import TriaKit

struct SortCommand: TriaSubcommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "sort", abstract: L10n.help(.sortAbstract))
    }

    @Flag(help: .catalog(.sortAuto)) var auto = false
    @Flag(help: .catalog(.sortDryRun)) var dryRun = false
    @Flag(help: .catalog(.sortJSON)) var json = false
    @Flag(help: .catalog(.sortShowPrompt)) var showPrompt = false
    @Flag(help: .catalog(.sortNoCache)) var noCache = false
    @Option(help: .catalog(.root)) var root: String?

    func execute(_ env: CLIEnvironment) async throws {
        let workspace = try env.workspace(root: root)
        let interactive = !auto && !dryRun && !json
        if interactive && !env.terminal.isInteractive { throw CLIError(env.t(.nonInteractive)) }
        let (provider, _) = try env.provider()
        let lock = try WorkspaceLock.acquire(workspace)
        defer { lock.release() }

        if !json {
            env.terminal.write(Presenter.header(workspace: workspace.root.lastPathComponent, provider: provider.id,
                                                model: provider.model, style: env.style))
        }
        let tally = RequestTally()
        let pipeline = SortPipeline(workspace: workspace, provider: provider, useCache: !noCache,
                                    onRequest: onRequest(tally: tally, env: env))
        let plan = try await read(pipeline, inbox: workspace.rules.header.inbox, tally: tally, env: env)

        if !json {
            if !plan.inUse.isEmpty { env.say(.inUse, String(plan.inUse.count)) }
            if !plan.ignoredFolders.isEmpty {
                env.say(.ignoredFolders, plan.ignoredFolders.map(\.lastPathComponent).joined(separator: ", "))
            }
        }
        if plan.items.isEmpty {
            if json { try printJSON(SortOutput(plan: plan, report: nil, env: env), env) } else { env.say(.nothingToDo) }
            return
        }
        // En un terminal de verdad, la revisión es a pantalla completa (spec CLI §5); si la ventana es pequeña o no hay
        // nada que aprobar, por fichas.
        let fullScreen = interactive && env.terminal.capabilities.fullScreen
            && plan.items.contains(where: SortReview.isApprovable)
        if !json {
            if !fullScreen {
                for (index, item) in plan.items.enumerated() {
                    env.terminal.write(Presenter.card(item, index: index + 1, total: plan.items.count, env,
                                                      style: env.style).joined(separator: "\n"))
                }
            }
            env.terminal.write(Presenter.summary(plan, env, style: env.style))
            env.terminal.write(Presenter.cost(plan.usage, model: plan.model, env, style: env.style))
            if let interruption = plan.interruption { env.say(.warning, .interrupted, describe(interruption, env)) }
        }

        var approved: [ApprovedItem] = []
        var corrections: [SortCorrection] = []
        if auto {
            approved = SortPipeline.automaticItems(plan)
        } else if interactive {
            (approved, corrections) = try fullScreen
                ? reviewFullScreen(plan, workspace: workspace, env: env)
                : SortReview.lines(plan, workspace: workspace, env: env)
        }

        let report = approved.isEmpty ? nil : pipeline.apply(approved)
        if let report, !json {
            for line in Presenter.applied(report, env, style: env.style) { env.terminal.write(line) }
        }
        if let report, !corrections.isEmpty {
            try await offerSuggestions(corrections, report: report, workspace: workspace, provider: provider, env: env)
        }

        let remaining = plan.items.count - (report?.applied.count ?? 0)
        if json {
            try printJSON(SortOutput(plan: plan, report: report, env: env), env)
        } else if remaining > 0 && !dryRun {
            env.terminal.write(env.style.paint(L10n.count(remaining, .pendingLeftOne, .pendingLeft, env.lang), .warning))
        }
        if remaining > 0 && !dryRun { throw ExitCode(1) }
    }

    /// Cuenta cada petición y, con `--show-prompt`, la escribe. Con `--json` la escribe por la salida de errores, para
    /// que la estándar sea solo JSON.
    private func onRequest(tally: RequestTally, env: CLIEnvironment) -> @Sendable (LLMRequest) -> Void {
        let terminal = env.terminal
        let show = showPrompt
        let quiet = json
        return { request in
            tally.record(request)
            guard show else { return }
            let text = PromptBuilder.render(request)
            if quiet { terminal.error(text) } else { terminal.write(text) }
        }
    }

    /// Pide las propuestas. Normalmente con la animación de espera en la salida de errores, que pasa por cada documento
    /// (spec CLI §4). Sin ella:
    /// - con `--json`, que no escribe nada más;
    /// - con `--show-prompt`, que ya va escribiendo lo que se envía.
    private func read(_ pipeline: SortPipeline, inbox: String, tally: RequestTally, env: CLIEnvironment) async throws -> SortPlan {
        let terminal = env.terminal
        guard !json && !showPrompt else {
            let quiet = json
            // La línea «Analizando…» cita la bandeja (sin caracteres de control, con `say`); lo que se envía, que escribe
            // `onRequest`, va tal cual: `--show-prompt` enseña exactamente eso.
            return try await pipeline.plan(progress: { progress in
                if !quiet, case .started(let total) = progress, total > 0 {
                    env.say(.analyzing, String(total), inbox)
                }
            })
        }
        return try await terminal.withActivity(env.t(.scanning, inbox), done: { plan, seconds in
            Presenter.readingDone(plan, seconds: seconds, cached: tally.cachedCount(in: plan), env, style: env.errorStyle)
        }) { activity in
            try await pipeline.plan(progress: { progress in
                switch progress {
                case .started(let total):
                    activity.update(env.t(.analyzing, String(total), inbox), progress: nil)
                case .document(let done, let total, let name):
                    activity.update(name, progress: ActivityProgress(done: done, total: total))
                }
            })
        }
    }

    /// La revisión a pantalla completa (spec CLI §5). Con `e` sale de ella, enseña la ficha y pregunta carpeta y
    /// nombre como la revisión por fichas; luego vuelve.
    private func reviewFullScreen(_ plan: SortPlan, workspace: Workspace,
                                  env: CLIEnvironment) throws -> ([ApprovedItem], [SortCorrection]) {
        let validator = Validator(workspace: workspace)
        let header = ReviewHeader(workspace: workspace.root.lastPathComponent, model: plan.model,
                                  cost: plan.cost.map { L10n.money($0, env.lang) })
        let review = FullScreenReview(plan: plan, header: header, env: env, style: env.style, edit: { item, reserved in
            let index = (plan.items.firstIndex(of: item) ?? 0) + 1
            env.terminal.write(Presenter.card(item, index: index, total: plan.items.count, env, style: env.style)
                .joined(separator: "\n"))
            return SortReview.edit(item, validator: validator, reserved: reserved, env: env)
        })
        switch try review.run(on: env.makeScreen()) {
        case .apply(let approved, let corrections): return (approved, corrections)
        case .cancelled: return ([], [])
        }
    }

    private func offerSuggestions(_ corrections: [SortCorrection], report: ApplyReport, workspace: Workspace,
                                  provider: any LLMProvider, env: CLIEnvironment) async throws {
        let moved = Dictionary(report.applied.map { ($0.from, $0.to) }, uniquingKeysWith: { first, _ in first })
        var current = workspace
        let learner = RulesLearner(provider: provider)
        let store = SuggestionStore(workspace: workspace)
        for correction in corrections {
            guard let newPath = moved[correction.item.relativePath] else { continue }
            let excerpt = (try? RulesLearner.sampleExtractor.extract(workspace.url(forRelative: newPath)).text) ?? ""
            let name = correction.item.file.lastPathComponent
            let rules = current.rules
            do {
                // La animación mientras se piensa la regla (spec CLI §4).
                let (draft, _) = try await env.terminal.withActivity(env.t(.thinkingRule, name)) { _ in
                    try await learner.suggestRule(rules: rules, original: correction.original, originalFilename: name,
                                                  correctedDestination: correction.folder,
                                                  correctedFilename: correction.filename, excerpt: excerpt)
                }
                let suggestion = RuleSuggestion(draft: draft, context: "\(name): "
                                                + "\(correction.original.destination) → \(correction.folder)",
                                                document: name, fromFolder: correction.original.destination,
                                                toFolder: correction.folder)
                env.terminal.write(Presenter.rulePreview(
                    RulesPatcher.preview(rule: draft.rule, section: draft.section, in: current.rules.raw), style: env.style))
                switch try SortReview.ask(.suggestionOffer, ["a", "l", "d"], env) {
                case "a":
                    current = try current.applySuggestion(suggestion)
                    env.say(.success, .suggestionApplied, draft.rule)
                case "d":
                    env.say(.suggestionDiscarded)
                default:
                    // Sin decidir (Intro o "l"): queda en las sugeridas para más tarde (spec §7.3).
                    try store.add(suggestion)
                    env.say(.suggestionSaved)
                }
            } catch let interrupt as TerminalInterrupt {
                throw interrupt
            } catch {
                env.terminal.error(describe(error, env))
            }
        }
    }

    private func printJSON(_ output: SortOutput, _ env: CLIEnvironment) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        env.terminal.write(String(decoding: try encoder.encode(output), as: UTF8.self))
    }
}

/// A qué documentos se ha preguntado a la IA en este lote, para saber cuántos han salido de la caché sin gastar.
final class RequestTally: @unchecked Sendable {
    private let lock = NSLock()
    private var asked = Set<String>()

    func record(_ request: LLMRequest) {
        guard let name = Self.documentName(in: request.userText) else { return }
        lock.withLock { _ = asked.insert(name) }
    }

    /// El nombre que `PromptBuilder` pone en cada documento («Original file name: …»). En la bandeja no hay dos
    /// iguales, porque sus subcarpetas no se procesan.
    static func documentName(in userText: String) -> String? {
        let marker = "Original file name: "
        return userText.split(separator: "\n").first { $0.hasPrefix(marker) }.map { String($0.dropFirst(marker.count)) }
    }

    /// Documentos con respuesta de la IA a los que no se ha preguntado: salen de la caché.
    func cachedCount(in plan: SortPlan) -> Int {
        let asked = lock.withLock { self.asked }
        return plan.items.filter { item in
            guard !asked.contains(item.file.lastPathComponent) else { return false }
            switch item.kind {
            case .proposal, .pending(_, .modelDoubt(_)), .pending(_, .invalidProposal(_)), .pending(_, .refused):
                return true
            default:
                return false
            }
        }.count
    }
}
