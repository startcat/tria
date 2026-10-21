import ArgumentParser
import TriaKit

struct CLIError: Error {
    let message: String
    let code: Int32

    init(_ message: String, code: Int32 = 2) {
        self.message = message
        self.code = code
    }
}

/// Subcomando con entorno inyectable. Los errores se muestran traducidos y salen con código 2 (spec §8.1).
protocol TriaSubcommand: AsyncParsableCommand {
    func execute(_ env: CLIEnvironment) async throws
}

extension TriaSubcommand {
    func run() async throws {
        let env = CLIEnvironment.current
        do {
            try await execute(env)
        } catch let exit as ExitCode {
            throw exit
        } catch is TerminalInterrupt {
            // Ctrl-C en una pregunta de una tecla o en la pantalla completa: no se ha movido nada (spec CLI §6).
            // En el entorno real el proceso muere por SIGINT (el shell ve 130 y los bucles de bash paran).
            env.onInterrupt?()
            throw ExitCode(130)
        } catch let error as CLIError {
            env.terminal.error(error.message)
            throw ExitCode(error.code)
        } catch {
            env.terminal.error(describe(error, env))
            throw ExitCode(2)
        }
    }
}

/// El error para leer, en una línea y sin caracteres de control: cita lo que dice el proveedor, un fichero o el sistema.
/// Va por la salida de errores o en un aviso, nunca en `--json`.
func describe(_ error: Error, _ env: CLIEnvironment) -> String {
    TextWidth.singleLine(message(for: error, env))
}

private func message(for error: Error, _ env: CLIEnvironment) -> String {
    if let error = error as? WorkspaceError {
        switch error {
        case .rootNotFound(let path), .rulesNotFound(let path): return env.t(.noWorkspace, path)
        case .rules(let rulesError): return env.t(.invalidRules, L10n.describe(rulesError, env.lang))
        case .profile(let profileError): return env.t(.invalidProfile, L10n.describe(profileError, env.lang))
        case .locked(let host, let pid, _): return env.t(.locked, host, String(pid))
        case .rulesAlreadyExist: return env.t(.initExistsShort)
        }
    }
    if let error = error as? LLMError {
        switch error {
        case .invalidKey: return env.t(.invalidKey)
        case .keyWithoutWorkspace: return env.t(.keyWithoutWorkspace)
        case .quotaExceeded(let message): return env.t(.quota, message)
        default: return env.t(.providerError, String(describing: error))
        }
    }
    if let failure = error as? RulesAskFailure { return L10n.describe(failure.reason, env.lang) }
    if let error = error as? RulesChangeError { return L10n.describe(error, env.lang) }
    if let failure = error as? LearnFailure { return env.t(.learnFailed, String(describing: failure.reason)) }
    if let error = error as? LearnError { return env.t(.learnFailed, String(describing: error)) }
    return String(describing: error)
}

extension TemplateKind: ExpressibleByArgument {}
extension TemplateLanguage: ExpressibleByArgument {}
extension ProviderID: ExpressibleByArgument {}
