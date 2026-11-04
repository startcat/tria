import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private func archive(_ dir: TempDir) throws -> Workspace {
    try WorkspaceFixture.make(in: dir, folders: WorkspaceFixture.defaultFolders + ["2-Contratos", "4-Correspondencia"])
}

private func exists(_ dir: TempDir, _ relative: String) -> Bool {
    FileManager.default.fileExists(atPath: dir.url.appendingPathComponent(relative).path)
}

private func contents(_ dir: TempDir, _ relative: String) throws -> String {
    try String(contentsOf: dir.url.appendingPathComponent(relative), encoding: .utf8)
}

@Test func movesAnArchivedDocumentAndJournalsItByUser() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/Contrato telefonía.pdf", "contrato")

    let report = Executor(workspace: ws).relocate(
        [RelocationItem(source: "4-Correspondencia/Contrato telefonía.pdf", folder: "2-Contratos")], batch: "b_move")

    #expect(report.batch == "b_move")
    #expect(report.failed.isEmpty)
    #expect(report.moved.map(\.from) == ["4-Correspondencia/Contrato telefonía.pdf"])
    #expect(report.moved.map(\.to) == ["2-Contratos/Contrato telefonía.pdf"])
    #expect(!exists(dir, "4-Correspondencia/Contrato telefonía.pdf"))
    #expect(try contents(dir, "2-Contratos/Contrato telefonía.pdf") == "contrato")
    let events = try Journal(workspace: ws).events()
    #expect(events.map(\.state) == [.intent, .done])
    #expect(events.allSatisfy { $0.op == .move && $0.batch == "b_move" && $0.id == report.moved.first?.operationID })
    #expect(events.allSatisfy { $0.byUser == true && $0.sha256 == Hashing.sha256("contrato") })
    let operation = try #require(try Journal(workspace: ws).operations().first)
    #expect(operation.isUserMove)
    #expect(operation.from == "4-Correspondencia/Contrato telefonía.pdf")
    #expect(operation.to == "2-Contratos/Contrato telefonía.pdf")
}

@Test func aNameClashGetsANumberAndNeverOverwrites() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("2-Contratos/Contrato telefonía.pdf", "el que estaba")
    try dir.write("4-Correspondencia/Contrato telefonía.pdf", "el movido")

    let report = Executor(workspace: ws).relocate(
        [RelocationItem(source: "4-Correspondencia/Contrato telefonía.pdf", folder: "2-Contratos")])

    #expect(report.moved.map(\.to) == ["2-Contratos/Contrato telefonía (2).pdf"])
    #expect(try contents(dir, "2-Contratos/Contrato telefonía.pdf") == "el que estaba")
    #expect(try contents(dir, "2-Contratos/Contrato telefonía (2).pdf") == "el movido")
}

@Test func twoDocumentsWithTheSameNameGetDifferentNames() throws {   // Review Focus 3
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/A.pdf", "uno")
    try dir.write("1-Modelos Tributarios/A.pdf", "dos")

    let report = Executor(workspace: ws).relocate([
        RelocationItem(source: "4-Correspondencia/A.pdf", folder: "2-Contratos"),
        RelocationItem(source: "1-Modelos Tributarios/A.pdf", folder: "2-Contratos"),
    ])

    #expect(report.failed.isEmpty)
    #expect(report.moved.map(\.to) == ["2-Contratos/A.pdf", "2-Contratos/A (2).pdf"])
    #expect(try contents(dir, "2-Contratos/A.pdf") == "uno")
    #expect(try contents(dir, "2-Contratos/A (2).pdf") == "dos")
}

@Test func protectedInboxAndDuplicatesNeitherGiveNorTake() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    let movable = "4-Correspondencia/Contrato telefonía.pdf"
    for path in ["7-Facturas/2013/1T/F.pdf", "99-Pendiente/a.pdf", "98-Duplicados/d.pdf", movable] {
        try dir.write(path)
    }

    let report = Executor(workspace: ws).relocate([
        RelocationItem(source: "7-Facturas/2013/1T/F.pdf", folder: "2-Contratos"),
        RelocationItem(source: "99-Pendiente/a.pdf", folder: "2-Contratos"),
        RelocationItem(source: "98-Duplicados/d.pdf", folder: "2-Contratos"),
        RelocationItem(source: movable, folder: "7-Facturas/2013"),
        RelocationItem(source: movable, folder: "99-Pendiente"),
        RelocationItem(source: movable, folder: "98-Duplicados"),
    ])

    #expect(report.moved.isEmpty)
    #expect(report.failed.map(\.problem) == [
        .notMovable, .notMovable, .notMovable,
        .destination(.protectedPath("7-Facturas/2013")), .destination(.intoInbox), .destination(.intoDuplicates),
    ])
    for path in ["7-Facturas/2013/1T/F.pdf", "99-Pendiente/a.pdf", "98-Duplicados/d.pdf", movable] {
        #expect(exists(dir, path))
    }
    #expect(try Journal(workspace: ws).events().isEmpty)
}

@Test func aNameThatAProtectedPatternWouldCatchDoesNotGoIn() throws {
    // "7-Facturas" no es protegida, pero "7-Facturas/2024 resumen.pdf" encaja con "7-Facturas/20*/", como al archivar.
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/2024 resumen.pdf")

    let report = Executor(workspace: ws).relocate(
        [RelocationItem(source: "4-Correspondencia/2024 resumen.pdf", folder: "7-Facturas")])

    #expect(report.failed.map(\.problem) == [.destination(.protectedPath("7-Facturas/2024 resumen.pdf"))])
    #expect(exists(dir, "4-Correspondencia/2024 resumen.pdf"))
}

@Test func aDocumentLooseAtTheRootIsNotMovable() throws {   // M16: su carpeta de antes sería la raíz
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("Suelto.pdf")

    let report = Executor(workspace: ws).relocate([RelocationItem(source: "Suelto.pdf", folder: "2-Contratos")])

    #expect(report.failed == [FailedRelocation(source: "Suelto.pdf", problem: .notMovable)])
    #expect(exists(dir, "Suelto.pdf"))
}

@Test func aMissingFolderIsNotCreated() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/Contrato telefonía.pdf")
    try dir.write("4-Correspondencia/Otro.pdf")

    let report = Executor(workspace: ws).relocate([
        RelocationItem(source: "4-Correspondencia/Contrato telefonía.pdf", folder: "3-Nueva"),
        // Un fichero no es una carpeta.
        RelocationItem(source: "4-Correspondencia/Contrato telefonía.pdf", folder: "4-Correspondencia/Otro.pdf"),
    ])

    #expect(report.failed.map(\.problem) == [.folderMissing, .folderMissing])
    #expect(!exists(dir, "3-Nueva"))
    #expect(exists(dir, "4-Correspondencia/Contrato telefonía.pdf"))
}

@Test func theSameFolderIsLeftAloneAndWritesNothing() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/Contrato telefonía.pdf")

    let report = Executor(workspace: ws).relocate([
        RelocationItem(source: "4-Correspondencia/Contrato telefonía.pdf", folder: "4-Correspondencia"),
        RelocationItem(source: "4-Correspondencia/Contrato telefonía.pdf", folder: "4-correspondencia"),
    ])

    #expect(report.failed.map(\.problem) == [.sameFolder, .sameFolder])
    #expect(exists(dir, "4-Correspondencia/Contrato telefonía.pdf"))
    #expect(try Journal(workspace: ws).events().isEmpty)
}

@Test func aDocumentOnlyInTheCloudIsNotMoved() throws {   // M17
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/Contrato telefonía.pdf")

    let report = Executor(workspace: ws).relocate(
        [RelocationItem(source: "4-Correspondencia/Contrato telefonía.pdf", folder: "2-Contratos")],
        isDownloaded: { _ in false })

    #expect(report.failed.map(\.problem) == [.onlyInCloud])
    #expect(exists(dir, "4-Correspondencia/Contrato telefonía.pdf"))
    #expect(try Journal(workspace: ws).events().isEmpty)
}

@Test func aDocumentThatCannotBeReadIsNotMoved() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    let file = try dir.write("4-Correspondencia/Contrato telefonía.pdf")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

    let report = Executor(workspace: ws).relocate(
        [RelocationItem(source: "4-Correspondencia/Contrato telefonía.pdf", folder: "2-Contratos")])

    #expect(report.moved.isEmpty)
    guard case .unreadable(let message) = report.failed.first?.problem else {
        Issue.record("se esperaba .unreadable y llegó \(String(describing: report.failed.first?.problem))")
        return
    }
    // El problema es para el usuario: la frase del sistema, no el volcado del error.
    #expect(!message.isEmpty)
    #expect(!message.contains("Error Domain"))
    #expect(exists(dir, "4-Correspondencia/Contrato telefonía.pdf"))
    #expect(try Journal(workspace: ws).events().isEmpty)
}

@Test func aMoveThatFailsIsJournaledAsFailed() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/Contrato telefonía.pdf")
    // Sin permiso de escritura en la carpeta de destino, el movimiento falla después de apuntar la intención.
    let folder = dir.url.appendingPathComponent("2-Contratos").path
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }

    let report = Executor(workspace: ws).relocate(
        [RelocationItem(source: "4-Correspondencia/Contrato telefonía.pdf", folder: "2-Contratos")])

    #expect(report.moved.isEmpty)
    guard case .failed(let message) = report.failed.first?.problem else {
        Issue.record("se esperaba .failed y llegó \(String(describing: report.failed.first?.problem))")
        return
    }
    // Al usuario, la frase del sistema; al registro, el error entero, para saber qué pasó.
    #expect(!message.isEmpty)
    #expect(!message.contains("Error Domain"))
    #expect(exists(dir, "4-Correspondencia/Contrato telefonía.pdf"))
    let events = try Journal(workspace: ws).events()
    #expect(events.map(\.state) == [.intent, .failed])
    #expect(events.allSatisfy { $0.byUser == true })
    #expect(events.last?.error?.contains("NSCocoaErrorDomain") == true)
}

@Test func oneFailureDoesNotStopTheOthers() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/Contrato telefonía.pdf")

    let report = Executor(workspace: ws).relocate([
        RelocationItem(source: "4-Correspondencia/No está.pdf", folder: "2-Contratos"),
        RelocationItem(source: "4-Correspondencia/Contrato telefonía.pdf", folder: "2-Contratos"),
    ])

    #expect(report.moved.count == 1)
    #expect(report.failed == [FailedRelocation(source: "4-Correspondencia/No está.pdf", problem: .missing)])
    #expect(exists(dir, "2-Contratos/Contrato telefonía.pdf"))
}
