#if DEBUG
import ArgumentParser
import Foundation
import Testing
import TriaKit
import TriaTestSupport
@testable import TriaCLI

/// El CLI de Debug con `TRIA_QA=1` usa `QAProvider`, las keys en memoria y la Papelera de la raíz QA (spec QA §4);
/// sin la variable, lo de verdad. Usan `make`, que no toca `QATrash.folder` (es de todo el proceso).
struct QAEnvironmentTests {
    @Test func withTRIA_QATheCLIUsesTheQAProviderNoKeychainAndTheQATrash() throws {
        let env = CLIEnvironment.make(environment: ["TRIA_QA": "1", "TRIA_QA_ROOT": "/tmp/raiz-qa", "TRIA_LANG": "es"])
        let qa = try #require(env.makeProvider(.anthropic, "claude-haiku-5-5", "qa") as? QAProvider)
        #expect(qa.id == .anthropic)
        #expect(qa.model == "claude-haiku-5-5")
        #expect(qa.log?.path == "/tmp/raiz-qa/estado/peticiones.jsonl")
        #expect(qa.offlineFlag?.path == "/tmp/raiz-qa/estado/sin-red")
        #expect(env.secrets is InMemorySecretStore)
        #expect(QATrash.folder(forEnvironment: ["TRIA_QA": "1", "TRIA_QA_ROOT": "/tmp/raiz-qa"])?.path == "/tmp/raiz-qa/papelera")

        let openai = try #require(env.makeProvider(.openai, "gpt-5.4-mini", "qa") as? QAProvider)
        #expect(openai.id == .openai)
        #expect(openai.model == "gpt-5.4-mini")

        // Sin raíz, no apunta nada, siempre tiene red y la Papelera es una carpeta temporal, nunca la del Mac.
        let rootless = CLIEnvironment.make(environment: ["TRIA_QA": "1"])
        let bare = try #require(rootless.makeProvider(.anthropic, "claude-sonnet-5-5", "qa") as? QAProvider)
        #expect(bare.log == nil)
        #expect(bare.offlineFlag == nil)
    }

    @Test func withoutTRIA_QATheCLIUsesTheRealProviderTheKeychainAndTheTrash() {
        for environment in [["TRIA_LANG": "es"], ["TRIA_QA": "0", "TRIA_QA_ROOT": "/tmp/raiz-qa"], ["TRIA_QA": ""]] {
            let env = CLIEnvironment.make(environment: environment)
            #expect(env.makeProvider(.anthropic, "claude-sonnet-5-5", "sk-ant-x") is AnthropicProvider)
            #expect(env.makeProvider(.openai, "gpt-5.4-mini", "sk-x") is OpenAIProvider)
            #expect(env.secrets is KeychainSecretStore)
            #expect(QATrash.folder(forEnvironment: environment) == nil)
        }
    }

    /// `tria sort --auto` con `TRIA_QA=1`: archiva donde dice la marca y apunta la petición en la raíz QA.
    @Test func sortWithTRIA_QAFilesByTheMarkerAndLogsTheRequest() async throws {
        let dir = try TempDir("tria-qa-cli")
        _ = try WorkspaceFixture.make(in: dir)
        let marker = QAMarker.proposal(folder: "7-Facturas/Recibidas", name: "Factura Papeleria Mar - 2026-10-09",
                                       type: "Factura", date: "2026-10-09")
        let inbox = try dir.write("99-Pendiente/escaneo.txt", "Factura de papelería.\n\(marker.text)\n")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)],
                                              ofItemAtPath: inbox.path)
        let root = dir.url.appendingPathComponent("qa", isDirectory: true)

        var env = CLIEnvironment.make(environment: [
            "TRIA_QA": "1", "TRIA_QA_ROOT": root.path, "TRIA_LANG": "es", "ANTHROPIC_API_KEY": "qa",
            "XDG_CONFIG_HOME": dir.url.appendingPathComponent("cli-config").path,
        ])
        env.terminal = ScriptedTerminal(interactive: false)
        env.currentDirectory = dir.url
        env.makeScreen = { FakeScreen(keys: []) }
        let status = try await CLIEnvironment.$current.withValue(env) { () async throws -> Int32 in
            do {
                var command = try TriaCommand.parseAsRoot(["sort", "--auto", "--root", dir.url.path])
                if var asyncCommand = command as? AsyncParsableCommand {
                    try await asyncCommand.run()
                } else {
                    try command.run()
                }
                return 0
            } catch let exit as ExitCode {
                return exit.rawValue
            }
        }

        #expect(status == 0)
        let filed = dir.url.appendingPathComponent("7-Facturas/Recibidas/Factura Papeleria Mar - 2026-10-09.txt")
        #expect(FileManager.default.fileExists(atPath: filed.path))
        let log = try String(contentsOf: root.appendingPathComponent("estado/peticiones.jsonl"), encoding: .utf8)
        let lines = log.split(separator: "\n").map {
            try? JSONDecoder().decode([String: String].self, from: Data($0.utf8))
        }
        #expect(lines == [["modelo": "claude-sonnet-5-5", "fichero": "escaneo.txt", "marca": marker.text]])
    }

    /// `tria rules ask -y` con `TRIA_QA=1`: aplica el cambio que dice la marca de la petición y la apunta.
    @Test func rulesAskWithTRIA_QAAppliesTheMarkersChange() async throws {
        let dir = try TempDir("tria-qa-cli")
        _ = try Workspace.initialize(at: dir.url, rulesText: Templates.text(.autonomo, language: .es))
        let root = dir.url.appendingPathComponent("qa", isDirectory: true)
        var env = CLIEnvironment.make(environment: [
            "TRIA_QA": "1", "TRIA_QA_ROOT": root.path, "TRIA_LANG": "es", "ANTHROPIC_API_KEY": "qa",
            "XDG_CONFIG_HOME": dir.url.appendingPathComponent("cli-config").path,
        ])
        env.terminal = ScriptedTerminal(interactive: false)
        env.currentDirectory = dir.url
        let marker = QAMarker.rulesChange(rule: "Los recibos del agua van a 9-Administracion.", section: "s3")
        let status = try await CLIEnvironment.$current.withValue(env) { () async throws -> Int32 in
            do {
                var command = try TriaCommand.parseAsRoot(["rules", "ask", "El agua \(marker.text)", "-y"])
                if var asyncCommand = command as? AsyncParsableCommand { try await asyncCommand.run() } else { try command.run() }
                return 0
            } catch let exit as ExitCode {
                return exit.rawValue
            }
        }
        #expect(status == 0)
        let rules = try String(contentsOf: dir.url.appendingPathComponent("TRIA.md"), encoding: .utf8)
        #expect(rules.hasSuffix("\n- Los recibos del agua van a 9-Administracion."))
        let log = try String(contentsOf: root.appendingPathComponent("estado/peticiones.jsonl"), encoding: .utf8)
        let lines = log.split(separator: "\n").compactMap {
            try? JSONDecoder().decode([String: String].self, from: Data($0.utf8))
        }
        #expect(lines.map { $0["marca"] } == [marker.text])
    }
}
#endif
