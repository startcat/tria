import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private func event(_ id: String, _ state: JournalEvent.State, from: String = "99-Pendiente/a.pdf",
                   to: String = "7-Facturas/Recibidas/A.pdf", batch: String = "b_1", ts: Date = Date()) -> JournalEvent {
    JournalEvent(id: id, batch: batch, op: .move, state: state, from: from, to: to, ts: ts)
}

@Test func appendsAndFoldsOperations() throws {
    let dir = try TempDir()
    let journal = Journal(workspace: try WorkspaceFixture.make(in: dir))
    try journal.append(event("op_1", .intent))
    try journal.append(event("op_1", .done, to: "7-Facturas/Recibidas/A (2).pdf"))
    try journal.append(event("op_2", .intent, from: "99-Pendiente/b.pdf"))
    try journal.append(event("op_2", .failed, from: "99-Pendiente/b.pdf"))

    #expect(try journal.events().count == 4)
    let operations = try journal.operations()
    #expect(operations.map(\.id) == ["op_1", "op_2"])
    #expect(operations[0].state == .done)
    #expect(operations[0].to == "7-Facturas/Recibidas/A (2).pdf")
    #expect(operations[1].state == .failed)
}

@Test func undoneKeepsOriginalPathsAndRecordsRestoredLocation() throws {
    let dir = try TempDir()
    let journal = Journal(workspace: try WorkspaceFixture.make(in: dir))
    try journal.append(event("op_1", .done))
    try journal.append(event("op_1", .undone, from: "7-Facturas/Recibidas/A.pdf", to: "99-Pendiente/a (2).pdf"))
    let operation = try #require(try journal.operations().first)
    #expect(operation.state == .undone)
    #expect(operation.from == "99-Pendiente/a.pdf")
    #expect(operation.restoredTo == "99-Pendiente/a (2).pdf")
}

@Test func summarizesBatchesNewestFirst() throws {
    let dir = try TempDir()
    let journal = Journal(workspace: try WorkspaceFixture.make(in: dir))
    let earlier = Date(timeIntervalSince1970: 1_000), later = Date(timeIntervalSince1970: 2_000)
    try journal.append(event("op_1", .done, batch: "b_old", ts: earlier))
    try journal.append(event("op_2", .done, batch: "b_new", ts: later))
    try journal.append(event("op_3", .intent, batch: "b_new", ts: later))
    let batches = try journal.batches()
    #expect(batches.map(\.id) == ["b_new", "b_old"])
    #expect(batches[0].done == 1 && batches[0].interrupted == 1)
}

@Test func reconcileClosesInterruptedOperations() throws {
    let dir = try TempDir()
    let journal = Journal(workspace: try WorkspaceFixture.make(in: dir))
    try dir.write("7-Facturas/Recibidas/movido.pdf")
    try dir.write("99-Pendiente/quieto.pdf")
    try journal.append(event("op_moved", .intent, from: "99-Pendiente/movido.pdf", to: "7-Facturas/Recibidas/movido.pdf"))
    try journal.append(event("op_still", .intent, from: "99-Pendiente/quieto.pdf", to: "7-Facturas/Recibidas/quieto.pdf"))

    let results = try journal.reconcile()
    #expect(results == [ReconcileResult(id: "op_moved", state: .done), ReconcileResult(id: "op_still", state: .failed)])
    #expect(try journal.operations().allSatisfy { $0.state != .intent })
    #expect(try journal.reconcile().isEmpty)
}

@Test func toleratesATruncatedLastLine() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let journal = Journal(workspace: ws)
    try journal.append(event("op_1", .done))
    let handle = try FileHandle(forWritingTo: ws.journalURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"id":"op_2","bat"#.utf8))
    try handle.close()
    #expect(try journal.events().count == 1)
}

@Test func idsHaveExpectedShape() {
    #expect(Journal.newBatchID().hasPrefix("b_"))
    #expect(Journal.newOperationID().hasPrefix("op_"))
    #expect(Journal.newOperationID() != Journal.newOperationID())
}

@Test func appendAfterATruncatedLineKeepsTheNewEvent() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let journal = Journal(workspace: ws)
    try journal.append(event("op_1", .done))
    let handle = try FileHandle(forWritingTo: ws.journalURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"id":"op_2","bat"#.utf8))
    try handle.close()
    try journal.append(event("op_3", .done))
    #expect(try journal.events().map(\.id) == ["op_1", "op_3"])
}

/// Una línea escrita antes de la fase 2 de la app, sin `corrected` ni `usage`: se lee igual y cuenta como «tal cual».
@Test func linesWrittenBeforeCorrectionsStillRead() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let old = #"{"batch":"b_20261001-101500_ab12","confidence":"high","from":"99-Pendiente/a.pdf","id":"op_1","model":"claude-haiku-5-5","op":"move","provider":"anthropic","reason":"Factura de proveedor","sha256":"abc","state":"done","to":"7-Facturas/Recibidas/A.pdf","ts":"2026-10-01T10:15:00Z"}"#
    try Data((old + "\n").utf8).write(to: ws.journalURL)

    let operation = try #require(try Journal(workspace: ws).operations().first)
    #expect(operation.state == .done)
    #expect(operation.confidence == .high)
    #expect(!operation.corrected)
    #expect(operation.usage == nil)
    #expect(operation.model == "claude-haiku-5-5")
}

@Test func correctedAndUsageRoundTrip() throws {
    let dir = try TempDir()
    let journal = Journal(workspace: try WorkspaceFixture.make(in: dir))
    let usage = TokenUsage(inputTokens: 900, outputTokens: 60, cacheReadTokens: 2_000, cacheWriteTokens: 40)
    let written = JournalEvent(id: "op_1", batch: "b_1", op: .move, state: .done, from: "99-Pendiente/a.pdf",
                               to: "7-Facturas/Recibidas/A.pdf", model: "claude-sonnet-5-5", corrected: true,
                               usage: usage, ts: Date(timeIntervalSince1970: 1_000))
    try journal.append(written)

    #expect(try journal.events() == [written])
    let operation = try #require(try journal.operations().first)
    #expect(operation.corrected)
    #expect(operation.usage == usage)
    #expect(operation.model == "claude-sonnet-5-5")
}

@Test func anUncorrectedEventDoesNotWriteTheField() {
    let event = JournalEvent(id: "op_1", batch: "b_1", op: .move, state: .done, from: "a", to: "b", corrected: false)
    #expect(event.corrected == nil)
}
