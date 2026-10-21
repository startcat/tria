import Foundation
import TriaKit

/// Una corrección hecha al revisar: lo que propuso la IA y dónde lo ha puesto el usuario, para sugerir una regla.
struct SortCorrection: Equatable, Sendable {
    var item: SortItem
    var original: Proposal
    var folder: String
    var filename: String
}

/// Lo que deja una edición: lo que se aplica y, si el destino ha cambiado, la corrección.
struct SortEdit: Equatable, Sendable {
    var approved: ApprovedItem
    var correction: SortCorrection?
}

/// Dos piezas de la revisión (spec CLI §4 y §5):
/// - la revisión por fichas, con preguntas de una tecla;
/// - la edición de carpeta y nombre, que también usa la pantalla completa.
enum SortReview {
    static func isApprovable(_ item: SortItem) -> Bool {
        if case .pending = item.kind { return false }
        return true
    }

    /// Mandar un duplicado a la Papelera.
    static func trash(_ item: SortItem) -> ApprovedItem? {
        guard case .duplicate(_, let action) = item.kind else { return nil }
        return ApprovedItem(action: FilingAction(kind: .trash, source: action.source, destination: ""),
                            sha256: item.sha256, reason: "trash")
    }

    static func lines(_ plan: SortPlan, workspace: Workspace, env: CLIEnvironment) throws -> ([ApprovedItem], [SortCorrection]) {
        let approvable = plan.items.filter(isApprovable)
        guard !approvable.isEmpty else { return ([], []) }
        switch try ask(.chooseAction, ["t", "a", "r", "n"], env) {
        case "t":
            return (approvable.compactMap { SortPipeline.approvedItem(for: $0) }, [])
        case "a":
            return (SortPipeline.automaticItems(plan), [])
        case "r":
            break
        default:
            return ([], [])
        }

        var approved: [ApprovedItem] = []
        var corrections: [SortCorrection] = []
        var reserved = Set<String>()
        let validator = Validator(workspace: workspace)
        loop: for (index, item) in approvable.enumerated() {
            env.terminal.write(Presenter.card(item, index: index + 1, total: approvable.count, env, style: env.style)
                .joined(separator: "\n"))
            switch item.kind {
            case .proposal(_, let action):
                switch try ask(.reviewProposal, ["s", "e", "o", "q"], env) {
                case "s":
                    if let accepted = SortPipeline.approvedItem(for: item) {
                        approved.append(accepted)
                        reserved.insert(action.destination)
                    }
                case "e":
                    guard let edited = edit(item, validator: validator, reserved: reserved, env: env) else {
                        continue
                    }
                    approved.append(edited.approved)
                    reserved.insert(edited.approved.action.destination)
                    if let correction = edited.correction { corrections.append(correction) }
                case "q":
                    break loop
                default:
                    continue
                }
            case .duplicate:
                switch try ask(.reviewDuplicate, ["s", "p", "o", "q"], env) {
                case "s":
                    if let accepted = SortPipeline.approvedItem(for: item) {
                        approved.append(accepted)
                    }
                case "p":
                    if let trashed = trash(item) { approved.append(trashed) }
                case "q":
                    break loop
                default:
                    continue
                }
            case .pending:
                continue
            }
        }
        return (approved, corrections)
    }

    /// Pregunta carpeta y nombre hasta que el `Validator` los acepta. `nil` si se acaba la entrada (Ctrl-D). Si el
    /// destino no es el propuesto, lo que se aplica va marcado como corregido y el registro lo guarda, con lo que costó
    /// leer el documento (spec de la app, §9, pieza 5).
    static func edit(_ item: SortItem, validator: Validator, reserved: Set<String>, env: CLIEnvironment) -> SortEdit? {
        guard case .proposal(let proposal, let action) = item.kind else { return nil }
        // Un Ctrl-D cancela solo su edición. Sin esto, la siguiente volvería sin preguntar y, en la pantalla completa,
        // el Intro que el usuario cree que contesta a la carpeta aplicaría lo marcado.
        env.terminal.resetEndOfInput()
        let currentFolder = (action.destination as NSString).deletingLastPathComponent
        let currentName = (action.destination as NSString).lastPathComponent
        // Las preguntas enseñan lo propuesto sin caracteres de control; con Intro se queda tal cual.
        let shownFolder = TextWidth.singleLine(currentFolder), shownName = TextWidth.singleLine(currentName)
        while true {
            guard let folderAnswer = env.terminal.ask(env.t(.editFolder, shownFolder)),
                  let nameAnswer = env.terminal.ask(env.t(.editName, shownName)) else { return nil }
            var edited = proposal
            edited.action = .file
            edited.destination = folderAnswer.trimmingCharacters(in: .whitespaces).isEmpty ? currentFolder : folderAnswer
            edited.filename = nameAnswer.trimmingCharacters(in: .whitespaces).isEmpty ? currentName : nameAnswer
            switch validator.validate(edited, originalFilename: item.file.lastPathComponent, reserved: reserved) {
            case .success(let destination):
                let changed = destination != action.destination
                let accepted = ApprovedItem(action: FilingAction(kind: .file, source: action.source, destination: destination),
                                            sha256: item.sha256, confidence: proposal.confidence, reason: proposal.reason,
                                            provider: item.readProvider, model: item.readModel,
                                            corrected: changed, usage: item.readUsage)
                guard changed else { return SortEdit(approved: accepted, correction: nil) }
                return SortEdit(approved: accepted, correction: SortCorrection(
                    item: item, original: proposal, folder: (destination as NSString).deletingLastPathComponent,
                    filename: (destination as NSString).lastPathComponent))
            case .failure(let error):
                env.say(.danger, .editInvalid, error.feedback)
            }
        }
    }

    /// Una pregunta de una tecla, con las teclas resaltadas. En minúscula y sin espacios.
    static func ask(_ key: L10n.Key, _ allowed: Set<Character>, _ env: CLIEnvironment) throws -> String? {
        try env.terminal.readKey(Presenter.keys(env.t(key), style: env.style), allowed: allowed)?
            .trimmingCharacters(in: .whitespaces).lowercased()
    }
}
