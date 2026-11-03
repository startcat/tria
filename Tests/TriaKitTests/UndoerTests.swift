import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private func fileTwo(_ dir: TempDir, _ ws: Workspace, batch: String) -> ApplyReport {
    Executor(workspace: ws).apply([
        ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/a.pdf", destination: "7-Facturas/Recibidas/A.pdf"),
                     sha256: Hashing.sha256("A")),
        ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/b.pdf", destination: "7-Facturas/Recibidas/B.pdf"),
                     sha256: Hashing.sha256("B")),
    ], batch: batch)
}

@Test func undoRestoresTheWholeBatch() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/a.pdf", "A")
    try dir.write("99-Pendiente/b.pdf", "B")
    _ = fileTwo(dir, ws, batch: "b_1")
    let report = try Undoer(workspace: ws).undo(batch: "b_1")
    #expect(Set(report.restored.map(\.to)) == ["99-Pendiente/a.pdf", "99-Pendiente/b.pdf"])
    #expect(report.skipped.isEmpty)
    #expect(try Journal(workspace: ws).operations().allSatisfy { $0.state == .undone })
}

@Test func undoSkipsModifiedOrMissingFilesAndNeverOverwrites() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/a.pdf", "A")
    try dir.write("99-Pendiente/b.pdf", "B")
    let applied = fileTwo(dir, ws, batch: "b_1")
    try dir.write("7-Facturas/Recibidas/A.pdf", "A modificado")
    try FileManager.default.removeItem(at: dir.url.appendingPathComponent("7-Facturas/Recibidas/B.pdf"))
    let report = try Undoer(workspace: ws).undo(batch: "b_1")
    #expect(report.restored.isEmpty)
    #expect(Set(report.skipped.map(\.reason)) == [.modified, .missing])
    #expect(applied.applied.count == 2)
}

@Test func undoToAnOccupiedPlaceAddsSuffix() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/a.pdf", "A")
    try dir.write("99-Pendiente/b.pdf", "B")
    _ = fileTwo(dir, ws, batch: "b_1")
    try dir.write("99-Pendiente/a.pdf", "otro")
    let report = try Undoer(workspace: ws).undo(batch: "b_1")
    #expect(report.restored.map(\.to).contains("99-Pendiente/a (2).pdf"))
    #expect(try String(contentsOf: dir.url.appendingPathComponent("99-Pendiente/a.pdf"), encoding: .utf8) == "otro")
}

@Test func undoLastPicksTheMostRecentBatchWithDoneOperations() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/a.pdf", "A")
    try dir.write("99-Pendiente/b.pdf", "B")
    _ = fileTwo(dir, ws, batch: "b_1")
    try dir.write("99-Pendiente/c.pdf", "C")
    Thread.sleep(forTimeInterval: 1.1)   // los lotes se ordenan por fecha (resolución de segundos)
    _ = Executor(workspace: ws).apply([
        ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/c.pdf", destination: "7-Facturas/Recibidas/C.pdf")),
    ], batch: "b_2")
    let report = try #require(try Undoer(workspace: ws).undoLast())
    #expect(report.restored.map(\.to) == ["99-Pendiente/c.pdf"])
    #expect(try Undoer(workspace: ws).undoLast()?.restored.count == 2)
    #expect(try Undoer(workspace: ws).undoLast() == nil)
}

/// Un journal manipulado (el espacio puede estar en una unidad compartida) con un lote "futuro" para que --last lo elija.
private func forge(_ ws: Workspace, from: String, to: String, sha: String?) throws {
    let journal = Journal(workspace: ws)
    let future = Date().addingTimeInterval(3600)
    for state in [JournalEvent.State.intent, .done] {
        try journal.append(JournalEvent(id: "op_forged", batch: "b_forged", op: .move, state: state, from: from, to: to,
                                        sha256: sha, ts: future))
    }
}

@Test func undoNeverWritesOutsideTheRoot() throws {
    let dir = try TempDir()
    let outside = try TempDir("tria-outside")
    let ws = try WorkspaceFixture.make(in: dir)
    let planted = try dir.write("7-Facturas/Recibidas/plantado.pdf", "malicioso")
    let escape = "../\(outside.url.lastPathComponent)/LaunchAgents/evil.pdf"
    try forge(ws, from: escape, to: "7-Facturas/Recibidas/plantado.pdf", sha: Hashing.sha256("malicioso"))
    let report = try #require(try Undoer(workspace: ws).undoLast())
    #expect(report.restored.isEmpty)
    #expect(report.skipped.map(\.reason) == [.unsafe])
    #expect(FileManager.default.fileExists(atPath: planted.path))
    #expect(!FileManager.default.fileExists(atPath: outside.url.appendingPathComponent("LaunchAgents/evil.pdf").path))
}

@Test func undoNeverPullsFilesFromOutsideTheRoot() throws {
    let dir = try TempDir()
    let outside = try TempDir("tria-outside")
    let ws = try WorkspaceFixture.make(in: dir)
    let secret = try outside.write("secreto.pdf", "privado")
    try forge(ws, from: "99-Pendiente/secreto.pdf", to: secret.path, sha: Hashing.sha256("privado"))
    let report = try #require(try Undoer(workspace: ws).undoLast())
    #expect(report.restored.isEmpty)
    #expect(report.skipped.map(\.reason) == [.unsafe])
    #expect(FileManager.default.fileExists(atPath: secret.path))
    #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("99-Pendiente/secreto.pdf").path))
}

@Test func undoAfterACrashIncludesTheInterruptedMove() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("7-Facturas/Recibidas/A.pdf", "A")
    try Journal(workspace: ws).append(JournalEvent(id: "op_1", batch: "b_1", op: .move, state: .intent,
                                                   from: "99-Pendiente/a.pdf", to: "7-Facturas/Recibidas/A.pdf",
                                                   sha256: Hashing.sha256("A")))
    let report = try #require(try Undoer(workspace: ws).undoLast())
    #expect(report.restored.map(\.to) == ["99-Pendiente/a.pdf"])
}

@Test func undoSkipsAMoveThatFailsAndRestoresTheRest() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/a.pdf", "A")
    try dir.write("99-Pendiente/b.pdf", "B")
    _ = Executor(workspace: ws).apply([
        ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/a.pdf", destination: "7-Facturas/Recibidas/A.pdf")),
        ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/b.pdf", destination: "1-Modelos Tributarios/B.pdf")),
    ], batch: "b_1")
    let locked = dir.url.appendingPathComponent("1-Modelos Tributarios")
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path); _ = dir }
    let report = try Undoer(workspace: ws).undo(batch: "b_1")
    #expect(report.restored.map(\.to) == ["99-Pendiente/a.pdf"])
    #expect(report.skipped.count == 1)
    guard case .failed? = report.skipped.first?.reason else { Issue.record("\(report.skipped)"); return }
}

@Test func undoOneOperationLeavesTheRestOfTheBatch() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/a.pdf", "A")
    try dir.write("99-Pendiente/b.pdf", "B")
    let applied = fileTwo(dir, ws, batch: "b_1")
    let first = try #require(applied.applied.first { $0.from == "99-Pendiente/a.pdf" })

    let report = try Undoer(workspace: ws).undo(operation: first.operationID)

    #expect(report.restored.map(\.to) == ["99-Pendiente/a.pdf"])
    #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("7-Facturas/Recibidas/B.pdf").path))
    let states = Dictionary(uniqueKeysWithValues: try Journal(workspace: ws).operations().map { ($0.from, $0.state) })
    #expect(states["99-Pendiente/a.pdf"] == .undone)
    #expect(states["99-Pendiente/b.pdf"] == .done)
}

@Test func undoingAnUnknownOrAlreadyUndoneOperationDoesNothing() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/a.pdf", "A")
    try dir.write("99-Pendiente/b.pdf", "B")
    let applied = fileTwo(dir, ws, batch: "b_1")
    let id = try #require(applied.applied.first?.operationID)
    let undoer = Undoer(workspace: ws)
    _ = try undoer.undo(operation: id)
    #expect(try undoer.undo(operation: id) == UndoReport(restored: [], skipped: []))
    #expect(try undoer.undo(operation: "op_nope") == UndoReport(restored: [], skipped: []))
}

// MARK: - Con movimientos del usuario («Mover a»)

private func archive(_ dir: TempDir) throws -> Workspace {
    try WorkspaceFixture.make(in: dir, folders: WorkspaceFixture.defaultFolders + ["2-Contratos", "4-Correspondencia"])
}

private func exists(_ dir: TempDir, _ relative: String) -> Bool {
    FileManager.default.fileExists(atPath: dir.url.appendingPathComponent(relative).path)
}

private func contents(_ dir: TempDir, _ relative: String) throws -> String {
    try String(contentsOf: dir.url.appendingPathComponent(relative), encoding: .utf8)
}

private func move(_ ws: Workspace, _ source: String, to folder: String, batch: String) -> RelocationReport {
    Executor(workspace: ws).relocate([RelocationItem(source: source, folder: folder)], batch: batch)
}

/// Tria archiva lo que hay en la bandeja como «4-Correspondencia/Contrato telefonía.pdf».
private func fileContract(_ dir: TempDir, _ ws: Workspace) throws -> AppliedMove {
    try dir.write("99-Pendiente/contrato.pdf", "contrato")
    let report = Executor(workspace: ws).apply([
        ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/contrato.pdf",
                                          destination: "4-Correspondencia/Contrato telefonía.pdf")),
    ], batch: "b_tria")
    return try #require(report.applied.first)
}

@Test func undoingAUserMovePutsItBackInTheFolderBefore() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/Contrato telefonía.pdf", "contrato")
    #expect(move(ws, "4-Correspondencia/Contrato telefonía.pdf", to: "2-Contratos", batch: "b_move").failed.isEmpty)

    let report = try Undoer(workspace: ws).undo(batch: "b_move")

    #expect(report.skipped.isEmpty)
    #expect(report.restored.map(\.from) == ["2-Contratos/Contrato telefonía.pdf"])
    #expect(report.restored.map(\.to) == ["4-Correspondencia/Contrato telefonía.pdf"])
    #expect(try contents(dir, "4-Correspondencia/Contrato telefonía.pdf") == "contrato")
    #expect(!exists(dir, "2-Contratos/Contrato telefonía.pdf"))
    let operation = try #require(try Journal(workspace: ws).operations().first)
    #expect(operation.state == .undone)
    #expect(operation.restoredTo == "4-Correspondencia/Contrato telefonía.pdf")
    #expect(try Journal(workspace: ws).events().last?.byUser == true)
}

@Test func undoingAUserMoveDoesNotRecreateAMissingFolder() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/Contrato telefonía.pdf", "contrato")
    _ = move(ws, "4-Correspondencia/Contrato telefonía.pdf", to: "2-Contratos", batch: "b_move")
    try FileManager.default.removeItem(at: dir.url.appendingPathComponent("4-Correspondencia"))

    let report = try Undoer(workspace: ws).undo(batch: "b_move")

    #expect(report.restored.isEmpty)
    #expect(report.skipped.map(\.reason) == [.previousFolderUnavailable])
    #expect(!exists(dir, "4-Correspondencia"))
    #expect(try contents(dir, "2-Contratos/Contrato telefonía.pdf") == "contrato")
    #expect(try Journal(workspace: ws).operations().map(\.state) == [.done])
}

@Test func undoingAUserMoveRefusesAFolderThatIsNowProtected() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/Contrato telefonía.pdf", "contrato")
    _ = move(ws, "4-Correspondencia/Contrato telefonía.pdf", to: "2-Contratos", batch: "b_move")
    let rules = WorkspaceFixture.defaultRules
        .replacingOccurrences(of: "protected:\n", with: "protected:\n  - \"4-Correspondencia/\"\n")
    try rules.write(to: ws.rulesURL, atomically: true, encoding: .utf8)
    let reopened = try ws.reloaded()
    #expect(reopened.protectedPaths.contains("4-Correspondencia"))

    let report = try Undoer(workspace: reopened).undo(batch: "b_move")

    #expect(report.restored.isEmpty)
    #expect(report.skipped.map(\.reason) == [.previousFolderUnavailable])
    #expect(!exists(dir, "4-Correspondencia/Contrato telefonía.pdf"))
    #expect(try contents(dir, "2-Contratos/Contrato telefonía.pdf") == "contrato")
}

@Test func undoingAUserMoveRefusesANameThatIsNowProtected() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("4-Correspondencia/Contrato telefonía.pdf", "contrato")
    _ = move(ws, "4-Correspondencia/Contrato telefonía.pdf", to: "2-Contratos", batch: "b_move")
    // Protege la ruta con el nombre y no la carpeta, como "7-Facturas/20*" con "7-Facturas/2024.pdf".
    let rules = WorkspaceFixture.defaultRules
        .replacingOccurrences(of: "protected:\n", with: "protected:\n  - \"4-Correspondencia/Contrato*\"\n")
    try rules.write(to: ws.rulesURL, atomically: true, encoding: .utf8)
    let reopened = try ws.reloaded()
    #expect(!reopened.protectedPaths.contains("4-Correspondencia"))

    let report = try Undoer(workspace: reopened).undo(batch: "b_move")

    #expect(report.skipped.map(\.reason) == [.previousFolderUnavailable])
    #expect(try contents(dir, "2-Contratos/Contrato telefonía.pdf") == "contrato")
}

@Test func undoingTriasFilingFindsTheDocumentWhereTheUserMovedIt() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    let filing = try fileContract(dir, ws)
    _ = move(ws, "4-Correspondencia/Contrato telefonía.pdf", to: "1-Modelos Tributarios", batch: "b_m1")
    _ = move(ws, "1-Modelos Tributarios/Contrato telefonía.pdf", to: "2-Contratos", batch: "b_m2")
    let before = try Journal(workspace: ws).index()
    #expect(before.operation(at: "2-Contratos/Contrato telefonía.pdf")?.id == filing.operationID)
    #expect(before.lastUserMove(at: "2-Contratos/Contrato telefonía.pdf")?.batch == "b_m2")

    let report = try Undoer(workspace: ws).undo(operation: filing.operationID)

    #expect(report.skipped.isEmpty)
    #expect(report.restored == [AppliedMove(operationID: filing.operationID, from: "2-Contratos/Contrato telefonía.pdf",
                                            to: "99-Pendiente/contrato.pdf")])
    #expect(try contents(dir, "99-Pendiente/contrato.pdf") == "contrato")
    #expect(!exists(dir, "2-Contratos/Contrato telefonía.pdf"))
    let operations = try Journal(workspace: ws).operations()
    #expect(operations.count == 3)
    #expect(operations.allSatisfy { $0.state == .undone && $0.restoredTo == "99-Pendiente/contrato.pdf" })
    let after = try Journal(workspace: ws).index()
    #expect(after.operation(at: "2-Contratos/Contrato telefonía.pdf") == nil)
    #expect(after.lastUserMove(at: "2-Contratos/Contrato telefonía.pdf") == nil)
}

@Test func undoingTriasBatchAfterAMoveBringsBackBoth() throws {
    let dir = try TempDir()
    let ws = try archive(dir)
    try dir.write("99-Pendiente/a.pdf", "A")
    try dir.write("99-Pendiente/b.pdf", "B")
    _ = fileTwo(dir, ws, batch: "b_1")
    #expect(move(ws, "7-Facturas/Recibidas/A.pdf", to: "2-Contratos", batch: "b_move").failed.isEmpty)

    let report = try Undoer(workspace: ws).undo(batch: "b_1")

    #expect(report.skipped.isEmpty)
    #expect(Set(report.restored.map(\.to)) == ["99-Pendiente/a.pdf", "99-Pendiente/b.pdf"])
    #expect(try contents(dir, "99-Pendiente/a.pdf") == "A")
    #expect(try contents(dir, "99-Pendiente/b.pdf") == "B")
    #expect(!exists(dir, "2-Contratos/A.pdf"))
    #expect(try Journal(workspace: ws).operations().allSatisfy { $0.state == .undone })
}

@Test func undoingTriasFilingAfterAMoveSkipsAModifiedDocument() throws {   // Review Focus 1
    let dir = try TempDir()
    let ws = try archive(dir)
    let filing = try fileContract(dir, ws)
    _ = move(ws, "4-Correspondencia/Contrato telefonía.pdf", to: "2-Contratos", batch: "b_move")
    try dir.write("2-Contratos/Contrato telefonía.pdf", "contrato firmado")

    let report = try Undoer(workspace: ws).undo(operation: filing.operationID)

    #expect(report.restored.isEmpty)
    #expect(report.skipped == [SkippedUndo(operationID: filing.operationID, reason: .modified)])
    #expect(try contents(dir, "2-Contratos/Contrato telefonía.pdf") == "contrato firmado")
    #expect(!exists(dir, "99-Pendiente/contrato.pdf"))
    #expect(try Journal(workspace: ws).operations().map(\.state) == [.done, .done])
}
