import Foundation
import TriaKit

/// Todo lo que un comando necesita del mundo exterior. Los tests lo sustituyen con `$current.withValue`.
public struct CLIEnvironment: Sendable {
    public var environment: [String: String]
    public var currentDirectory: URL
    public var configURL: URL
    public var secrets: any SecretStore
    public var terminal: any Terminal
    /// Cómo acaba el proceso tras un Ctrl-C en una tecla: muriendo por SIGINT (solo en el entorno real).
    public var onInterrupt: (@Sendable () -> Void)?
    public var makeProvider: @Sendable (ProviderID, String, String) -> any LLMProvider
    public var lang: Lang
    /// La pantalla de la revisión a pantalla completa (spec CLI §5); las pruebas ponen una falsa.
    public var makeScreen: @Sendable () -> any ScreenIO

    public init(environment: [String: String], currentDirectory: URL, configURL: URL, secrets: any SecretStore,
                terminal: any Terminal, makeProvider: @escaping @Sendable (ProviderID, String, String) -> any LLMProvider,
                lang: Lang, makeScreen: (@Sendable () -> any ScreenIO)? = nil) {
        self.environment = environment
        self.currentDirectory = currentDirectory
        self.configURL = configURL
        self.secrets = secrets
        self.terminal = terminal
        self.makeProvider = makeProvider
        self.lang = lang
        self.makeScreen = makeScreen ?? { TTYScreen() }
    }

    /// El entorno del proceso. Las pruebas pasan el suyo para ver qué proveedor monta.
    public static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> CLIEnvironment {
        let live = make(environment: environment)
        #if DEBUG
        // La Papelera de la tanda es de todo el proceso: solo la pone el proceso real, nunca `make`.
        if environment["TRIA_QA"] == "1" { QATrash.folder = QATrash.folder(forEnvironment: environment) }
        #endif
        return live
    }

    /// Como `live(environment:)`, pero sin tocar nada de todo el proceso (`QATrash.folder`): para las pruebas.
    static func make(environment: [String: String]) -> CLIEnvironment {
        var live = CLIEnvironment(
            environment: environment,
            currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            configURL: UserConfig.defaultURL(environment: environment),
            secrets: KeychainSecretStore(), terminal: StandardTerminal(environment: environment),
            makeProvider: { provider, model, key in ProviderFactory.make(provider, model: model, apiKey: key) },
            lang: Lang.detect(environment: environment))
        live.onInterrupt = { TerminalGuard.shared.interrupt(SIGINT) }
        #if DEBUG
        if environment["TRIA_QA"] == "1" { live.setUpQA(root: environment["TRIA_QA_ROOT"]) }
        #endif
        return live
    }

    #if DEBUG
    /// La tanda QA (spec QA §4), en lugar de lo de verdad, con la raíz de la prueba:
    /// - `QAProvider`, que apunta lo que se le pide en `<raíz>/estado/peticiones.jsonl` y no tiene red si existe
    ///   `<raíz>/estado/sin-red`, como la app QA con la misma raíz;
    /// - las keys, en memoria: no toca el Llavero;
    /// - la Papelera, `<raíz>/papelera/`, la pone `live` (`QATrash.folder(forEnvironment:)`, de todo el proceso).
    ///
    /// Solo en Debug: en la versión que se publica, `TRIA_QA` no hace nada.
    mutating func setUpQA(root: String?) {
        let base = root.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let state = base?.appendingPathComponent("estado", isDirectory: true)
        let log = state?.appendingPathComponent("peticiones.jsonl")
        let offlineFlag = state?.appendingPathComponent("sin-red")
        makeProvider = { provider, model, _ in
            QAProvider(id: provider, model: model, log: log, offlineFlag: offlineFlag)
        }
        secrets = InMemorySecretStore()
    }
    #endif

    @TaskLocal public static var current: CLIEnvironment = .live()

    /// Estilo de la salida estándar y de la de errores, según el terminal (spec CLI §2).
    public var style: Style { Style(terminal.capabilities.colors) }
    public var errorStyle: Style { Style(terminal.capabilities.errorColors) }

    public func t(_ key: L10n.Key, _ args: String...) -> String { L10n.text(key, lang, args) }

    /// Un mensaje para leer. Lo que cita (nombres, rutas, reglas de la IA) va sin caracteres de control.
    public func say(_ key: L10n.Key, _ args: String...) { terminal.write(message(key, args)) }

    /// Como `say`, con un papel del estilo: avisos en ámbar, lo hecho en verde y los errores en rojo.
    public func say(_ role: StyleRole, _ key: L10n.Key, _ args: String...) {
        terminal.write(style.paint(message(key, args), role))
    }

    /// Un aviso por la salida de error, en ámbar si es un terminal: no ensucia lo que lee un script.
    public func warn(_ key: L10n.Key, _ args: String...) {
        terminal.error(errorStyle.paint(message(key, args), .warning))
    }

    private func message(_ key: L10n.Key, _ args: [String]) -> String {
        L10n.text(key, lang, args.map(TextWidth.singleLine))
    }

    public func resolve(_ path: String?) -> URL {
        guard let path else { return currentDirectory }
        return URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
    }

    public func workspace(root: String?) throws -> Workspace {
        try Workspace.discover(from: resolve(root))
    }

    public func provider() throws -> (any LLMProvider, UserConfig) {
        let config = try UserConfig.load(from: configURL)
        guard let key = try APIKeyResolver.resolve(config.provider, environment: environment, store: secrets) else {
            throw CLIError(t(.noKey, config.provider.rawValue, config.provider.environmentKey))
        }
        return (makeProvider(config.provider, config.resolvedModel, key), config)
    }

    public func confirm(_ key: L10n.Key, _ args: String..., assumeYes: Bool) throws -> Bool {
        if assumeYes { return true }
        guard terminal.isInteractive else { throw CLIError(t(.nonInteractive)) }
        return L10n.isYes(terminal.ask(L10n.text(key, lang, args)))
    }
}
