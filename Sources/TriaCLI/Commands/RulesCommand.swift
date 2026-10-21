import ArgumentParser
import Foundation
import TriaKit

/// Solo agrupa subcomandos (no se ejecuta por sí mismo): basta con ParsableCommand.
struct RulesCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "rules",
            abstract: L10n.help(.rulesAbstract),
            subcommands: [Check.self, Learn.self, Suggestions.self, Ask.self])
    }

    struct Check: TriaSubcommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "check", abstract: L10n.help(.rulesCheckAbstract))
        }
        @Option(help: .catalog(.root)) var root: String?

        func execute(_ env: CLIEnvironment) async throws {
            let workspace = try env.workspace(root: root)
            if workspace.protectedPaths.contains(workspace.rules.header.inbox) {
                throw CLIError(env.t(.rulesInboxProtected))
            }
            if workspace.protectedPaths.contains(workspace.rules.header.duplicates) {
                throw CLIError(env.t(.rulesDuplicatesProtected))
            }
            for folder in [workspace.rules.header.inbox, workspace.rules.header.duplicates]
            where !FileManager.default.fileExists(atPath: workspace.root.appendingPathComponent(folder).path) {
                env.say(.warning, .rulesWarnMissingFolder, folder)
            }
            let directories = Self.directories(in: workspace.root, maxDepth: 4)
            for pattern in workspace.rules.header.protected
            where !directories.contains(where: { ProtectedPaths([pattern]).contains($0) }) {
                env.say(.warning, .rulesWarnProtectedUnmatched, pattern)
            }
            guard let file = workspace.profile else {
                env.say(.warning, .profileNone)
                env.say(.success, .rulesOK)
                return
            }
            for warning in file.warnings {
                switch warning {
                case .unknownKey(let key): env.say(.warning, .profileWarnUnknownKey, key)
                case .notForKind(let field):
                    env.say(.warning, .profileWarnNotForKind, field.rawValue, file.profile.kind.rawValue)
                }
            }
            if !file.profile.isComplete {
                env.say(.warning, .profileWarnMissing, L10n.fields(file.profile.missing, env.lang))
            }
            if let taxID = file.profile.taxID, !SpanishTaxID.isValid(taxID) { env.say(.warning, .profileWarnTaxID, taxID) }
            env.say(.success, .rulesOKWithProfile)
        }

        static func directories(in root: URL, maxDepth: Int) -> [String] {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
            var result: [String] = []
            let rootPath = root.path
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let relative = String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1)).normalizedRelativePath
                if relative.split(separator: "/").count >= maxDepth { enumerator.skipDescendants() }
                result.append(relative)
            }
            return result
        }
    }

    struct Learn: TriaSubcommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "learn", abstract: L10n.help(.rulesLearnAbstract))
        }
        @Option(help: .catalog(.root)) var root: String?
        @Option(help: .catalog(.rulesLearnLang)) var lang: TemplateLanguage?
        @Flag(name: .shortAndLong, help: .catalog(.noConfirm)) var yes = false

        func execute(_ env: CLIEnvironment) async throws {
            let workspace = try env.workspace(root: root)
            let (provider, config) = try env.provider()
            let learner = RulesLearner(provider: provider)
            let plan = try learner.plan(root: workspace.root)
            let cost = L10n.money(plan.estimatedCost(model: config.resolvedModel), env.lang)
            guard try env.confirm(.learnEstimate, String(plan.samples.count), cost, assumeYes: yes) else {
                env.say(.cancelled)
                return
            }
            let language = lang ?? env.lang.templateLanguage
            let title = env.t(.learnRunning, String(plan.samples.count))
            let (text, _) = try await env.terminal.withActivity(title, done: { _, seconds in
                Presenter.done(env.t(.learnDone, String(seconds)), style: env.errorStyle)
            }) { _ in try await learner.draft(plan, language: language) }
            let draft = Collision.uniqueRelativePath("TRIA.draft.md", root: workspace.root)
            try Data(text.utf8).write(to: workspace.root.appendingPathComponent(draft))
            env.say(.learnDraftSaved, draft)
        }
    }

    struct Suggestions: TriaSubcommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "suggestions", abstract: L10n.help(.rulesSuggestionsAbstract))
        }
        @Option(help: .catalog(.root)) var root: String?
        @Option(help: .catalog(.rulesSuggestionsApply)) var apply: String?
        @Option(help: .catalog(.rulesSuggestionsDiscard)) var discard: String?

        func execute(_ env: CLIEnvironment) async throws {
            let workspace = try env.workspace(root: root)
            let store = SuggestionStore(workspace: workspace)
            let suggestions = try store.list()
            if let id = apply {
                guard let suggestion = suggestions.first(where: { $0.id == id }) else {
                    throw CLIError(env.t(.suggestionNotFound, id))
                }
                _ = try workspace.applySuggestion(suggestion)
                try store.remove(id: id)
                env.say(.suggestionApplied, suggestion.rule)
                return
            }
            if let id = discard {
                guard suggestions.contains(where: { $0.id == id }) else { throw CLIError(env.t(.suggestionNotFound, id)) }
                try store.remove(id: id)
                env.say(.suggestionDiscarded)
                return
            }
            if suggestions.isEmpty { env.say(.suggestionsEmpty) }
            for suggestion in suggestions {
                env.say(.suggestionLine, suggestion.id, suggestion.section, suggestion.rule, suggestion.context)
            }
        }
    }

    /// `tria rules ask "…"` (spec de Reglas, §5): dice lo que costará, pide el cambio, lo enseña en color y pregunta
    /// «[a] aplicar · [d] descartar»; con `-y`, aplica sin preguntar. Una negativa sale con 1. Gasta de la clave
    /// configurada, como `rules learn`.
    struct Ask: TriaSubcommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "ask", abstract: L10n.help(.rulesAskAbstract))
        }
        @Argument(help: .catalog(.rulesAskRequest)) var instruction: String
        @Option(help: .catalog(.root)) var root: String?
        @Flag(name: .shortAndLong, help: .catalog(.applyWithoutAsking)) var yes = false

        func execute(_ env: CLIEnvironment) async throws {
            let workspace = try env.workspace(root: root)
            // Sin terminal y sin -y no se podrá preguntar: se para antes de enviar nada.
            if !yes && !env.terminal.isInteractive { throw CLIError(env.t(.nonInteractive)) }
            let (provider, config) = try env.provider()
            let asker = RulesAsker(provider: provider)
            env.say(.rulesAskEstimate, L10n.money(asker.estimatedCost(for: workspace, model: config.resolvedModel), env.lang),
                    config.resolvedModel)
            let (result, _) = try await env.terminal.withActivity(env.t(.rulesAskThinking), done: { _, seconds in
                Presenter.done(env.t(.rulesAskDone, String(seconds)), style: env.errorStyle)
            }) { _ in try await asker.ask(instruction, in: workspace) }
            switch result {
            case .refused(let reason):
                env.say(.warning, .rulesAskRefused, reason)
                throw ExitCode(1)
            case .change(let change):
                if !change.summary.isEmpty {
                    env.terminal.write(env.style.paint(TextWidth.singleLine(change.summary), .strong))
                }
                env.terminal.write(Presenter.rulesChange(change, env, style: env.style))
                if !yes, try SortReview.ask(.rulesAskOffer, ["a", "d"], env) != "a" {
                    env.say(.rulesAskDiscarded)
                    return
                }
                _ = try workspace.apply(change)
                env.say(.success, .rulesAskApplied)
            }
        }
    }
}
