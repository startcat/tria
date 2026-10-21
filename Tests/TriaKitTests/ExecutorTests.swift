import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private func fakeTrash(_ dir: TempDir) -> Trasher {
    let trash = dir.url.appendingPathComponent("FakeTrash", isDirectory: true)
    return { url in
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let target = trash.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }
}

@Test func movesCreatingFoldersAndJournalsIntentThenDone() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/doc.pdf", "contenido")
    let item = ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/doc.pdf",
                                                 destination: "7-Facturas/Emitidas/2025/1T/Factura.pdf"),
                            sha256: Hashing.sha256("contenido"), confidence: .high, reason: "r")
    let report = Executor(workspace: ws).apply([item], batch: "b_test")

    #expect(report.failed.isEmpty)
    #expect(report.applied.map(\.to) == ["7-Facturas/Emitidas/2025/1T/Factura.pdf"])
    #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("7-Facturas/Emitidas/2025/1T/Factura.pdf").path))
    #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("99-Pendiente/doc.pdf").path))
    #expect(try Journal(workspace: ws).events().map(\.state) == [.intent, .done])
}

@Test func twoItemsWithTheSameDestinationNeverOverwrite() throws {   // Review Focus 4
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/a.pdf", "A")
    try dir.write("99-Pendiente/b.pdf", "B")
    let destination = "7-Facturas/Recibidas/Factura Luz - 2025-01.pdf"
    let report = Executor(workspace: ws).apply([
        ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/a.pdf", destination: destination)),
        ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/b.pdf", destination: destination)),
    ])
    #expect(report.applied.map(\.to) == [destination, "7-Facturas/Recibidas/Factura Luz - 2025-01 (2).pdf"])
    let first = try String(contentsOf: dir.url.appendingPathComponent(destination), encoding: .utf8)
    #expect(first == "A")
}

@Test func missingSourceFailsWithoutTouchingAnything() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let report = Executor(workspace: ws).apply([
        ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/nada.pdf", destination: "7-Facturas/Recibidas/x.pdf")),
    ])
    #expect(report.applied.isEmpty)
    #expect(report.failed.map(\.source) == ["99-Pendiente/nada.pdf"])
}

@Test func duplicatesGoToTheDuplicatesFolderAndTrashUsesTheTrasher() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/dup.pdf")
    try dir.write("99-Pendiente/basura.pdf")
    let report = Executor(workspace: ws, trasher: fakeTrash(dir)).apply([
        ApprovedItem(action: FilingAction(kind: .duplicate, source: "99-Pendiente/dup.pdf", destination: "98-Duplicados/dup.pdf")),
        ApprovedItem(action: FilingAction(kind: .trash, source: "99-Pendiente/basura.pdf", destination: "")),
    ])
    #expect(report.applied.count == 2)
    #expect(report.applied[0].to == "98-Duplicados/dup.pdf")
    #expect(report.applied[1].to.hasPrefix("/"))
    #expect(report.applied[1].to.hasSuffix("FakeTrash/basura.pdf"))
}

@Test func fileChangedAfterTheProposalIsNotMoved() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/doc.pdf", "original")
    let item = ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/doc.pdf",
                                                 destination: "7-Facturas/Recibidas/Doc.pdf"),
                            sha256: Hashing.sha256("original"))
    try dir.write("99-Pendiente/doc.pdf", "cambiado")
    let report = Executor(workspace: ws).apply([item])
    #expect(report.applied.isEmpty)
    #expect(report.failed.map(\.source) == ["99-Pendiente/doc.pdf"])
    #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("99-Pendiente/doc.pdf").path))
}

@Test func executorRefusesDestinationsThatResolveIntoProtectedFolders() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try FileManager.default.createSymbolicLink(at: dir.url.appendingPathComponent("1-Modelos Tributarios/Atajo"),
                                               withDestinationURL: dir.url.appendingPathComponent("7-Facturas/2013/1T"))
    try dir.write("99-Pendiente/doc.pdf", "x")
    let report = Executor(workspace: ws).apply([
        ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/doc.pdf",
                                          destination: "1-Modelos Tributarios/Atajo/Doc.pdf")),
    ])
    #expect(report.applied.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("7-Facturas/2013/1T/Doc.pdf").path))
}

@Test func journalAlwaysRecordsTheHashOfWhatWasMoved() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/doc.pdf", "contenido")
    _ = Executor(workspace: ws).apply([
        ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/doc.pdf", destination: "7-Facturas/Recibidas/Doc.pdf")),
    ])
    #expect(try Journal(workspace: ws).operations().first?.sha256 == Hashing.sha256("contenido"))
}

@Test func aCorrectionAndTheReadCostAreJournaled() throws {   // spec de la app, §9, pieza 5
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/doc.pdf", "contenido")
    let usage = TokenUsage(inputTokens: 1_200, outputTokens: 80, cacheReadTokens: 3_000)
    let item = ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/doc.pdf",
                                                 destination: "7-Facturas/Recibidas/Factura.pdf"),
                            confidence: .high, reason: "r", provider: "anthropic", model: "claude-haiku-5-5",
                            corrected: true, usage: usage)

    let report = Executor(workspace: ws).apply([item], batch: "b_test")

    #expect(report.failed.isEmpty)
    let events = try Journal(workspace: ws).events()
    #expect(events.map(\.state) == [.intent, .done])
    #expect(events.map(\.corrected) == [true, true])
    #expect(events.map(\.usage) == [usage, usage])
    let operation = try #require(try Journal(workspace: ws).operations().first)
    #expect(operation.corrected)
    #expect(operation.usage == usage)
    #expect(operation.model == "claude-haiku-5-5")
}

@Test func aMoveAsProposedWritesTheSameLinesAsBefore() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/doc.pdf", "contenido")
    let item = ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/doc.pdf",
                                                 destination: "7-Facturas/Recibidas/Factura.pdf"),
                            confidence: .high, reason: "r")

    _ = Executor(workspace: ws).apply([item], batch: "b_test")

    let text = try String(contentsOf: ws.journalURL, encoding: .utf8)
    #expect(!text.contains("corrected"))
    #expect(!text.contains("usage"))
    let operation = try #require(try Journal(workspace: ws).operations().first)
    #expect(!operation.corrected)
    #expect(operation.usage == nil)
}
