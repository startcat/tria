import ArgumentParser
import Foundation
import TriaKit

struct InitCommand: TriaSubcommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "init", abstract: L10n.help(.initAbstract))
    }

    @Option(help: .catalog(.initTemplate)) var template: TemplateKind?
    @Flag(help: .catalog(.initLearn)) var learn = false
    @Option(help: .catalog(.initLang)) var lang: TemplateLanguage?
    @Flag(name: .shortAndLong, help: .catalog(.noConfirm)) var yes = false
    @Option(help: .catalog(.initRoot)) var root: String?

    func execute(_ env: CLIEnvironment) async throws {
        let rootURL = env.resolve(root)
        if FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(Workspace.rulesFileName).path) {
            let workspace = try Workspace.open(at: rootURL)
            try workspace.ensureStructure()
            env.say(.initExists, workspace.root.path)
            // Un espacio sin perfil lo gana con --template (spec del perfil, §4).
            if workspace.profile == nil {
                if let template {
                    try createProfile(template, language: lang ?? env.lang.templateLanguage, in: workspace, env: env)
                } else {
                    env.say(.warning, .profileNone)
                }
            }
            return
        }
        let language = lang ?? env.lang.templateLanguage
        var useLearn = learn
        var kind = template
        if !useLearn && kind == nil {
            guard env.terminal.isInteractive else { throw CLIError(env.t(.nonInteractive)) }
            let visible = ((try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ?? []).filter { !$0.hasPrefix(".") }
            if !visible.isEmpty, L10n.isYes(env.terminal.ask(env.t(.initOfferLearn))) {
                useLearn = true
            } else {
                switch env.terminal.ask(env.t(.initChooseTemplate))?.trimmingCharacters(in: .whitespaces) {
                case "1": kind = .autonomo
                case "2": kind = .sl
                case "3": kind = .hogar
                default: throw CLIError(env.t(.cancelled), code: 1)
                }
            }
        }
        if useLearn {
            try await learnRules(at: rootURL, language: language, env: env)
            return
        }
        guard let kind else { throw CLIError(env.t(.cancelled), code: 1) }
        let workspace = try Workspace.initialize(at: rootURL, rulesText: Templates.text(kind, language: language))
        for folder in Templates.folders(kind, language: language) {
            try FileManager.default.createDirectory(at: workspace.root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let name: L10n.Key = kind == .autonomo ? .templateAutonomo : kind == .sl ? .templateSL : .templateHogar
        env.say(.initCreated, workspace.root.path, env.t(name))
        // Si la carpeta ya traía un PERFIL.md, es del usuario: no se toca.
        if workspace.profile == nil {
            try createProfile(kind, language: language, in: workspace, env: env)
        } else {
            env.say(.profileKept)
        }
    }

    /// Crea `PERFIL.md` del tipo de la plantilla. En un terminal pregunta solo el mínimo; el resto se rellena editando
    /// el fichero (spec del perfil, §4).
    private func createProfile(_ kind: TemplateKind, language: TemplateLanguage, in workspace: Workspace,
                               env: CLIEnvironment) throws {
        var profile = Profile(kind: kind)
        if env.terminal.isInteractive && !yes {
            func answer(_ key: L10n.Key) -> String? {
                let text = env.terminal.ask(env.t(key))?.trimmingCharacters(in: .whitespaces) ?? ""
                return text.isEmpty ? nil : text
            }
            switch kind {
            case .autonomo, .sl:
                profile.name = answer(kind == .sl ? .initAskCompany : .initAskName)
                profile.taxID = answer(.initAskTaxID)
            case .hogar:
                if let member = answer(.initAskMember) { profile.members = [ProfilePerson(name: member)] }
            }
        }
        _ = try workspace.saveProfile(profile, language: language)
        env.say(profile.isComplete ? .initProfileCreated : .initProfileToFill)
    }

    private func learnRules(at rootURL: URL, language: TemplateLanguage, env: CLIEnvironment) async throws {
        let (provider, config) = try env.provider()
        let learner = RulesLearner(provider: provider)
        let plan = try learner.plan(root: rootURL)
        let cost = L10n.money(plan.estimatedCost(model: config.resolvedModel), env.lang)
        guard try env.confirm(.learnEstimate, String(plan.samples.count), cost, assumeYes: yes) else {
            env.say(.cancelled)
            return
        }
        // La animación mientras la IA lee la muestra (spec CLI §4).
        let title = env.t(.learnRunning, String(plan.samples.count))
        let (text, _) = try await env.terminal.withActivity(title, done: { _, seconds in
            Presenter.done(env.t(.learnDone, String(seconds)), style: env.errorStyle)
        }) { _ in try await learner.draft(plan, language: language) }
        // El borrador se enseña línea a línea sin caracteres de control; el fichero se guarda tal cual.
        env.terminal.write(text.components(separatedBy: "\n").map(TextWidth.singleLine).joined(separator: "\n"))
        if try env.confirm(.learnConfirmSave, assumeYes: yes) {
            let workspace = try Workspace.initialize(at: rootURL, rulesText: text)
            env.say(.initCreated, workspace.root.path, env.t(.templateLearned))
            if workspace.profile == nil { env.say(.warning, .profileNone) }
        } else {
            let draft = Collision.uniqueRelativePath("TRIA.draft.md", root: rootURL)
            try Data(text.utf8).write(to: rootURL.appendingPathComponent(draft))
            env.say(.learnDraftSaved, draft)
        }
    }
}
