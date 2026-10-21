import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

@Test func secondLockInTheSameWorkspaceFails() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let lock = try WorkspaceLock.acquire(ws)
    #expect(throws: (any Error).self) { try WorkspaceLock.acquire(ws) }
    lock.release()
    let again = try WorkspaceLock.acquire(ws)
    again.release()
}

@Test func staleLockFromDeadProcessIsTakenOver() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let info = #"{"pid":999999,"host":"\#(WorkspaceLock.thisHost)","since":"2026-10-11T10:00:00Z"}"#
    try Data(info.utf8).write(to: ws.lockURL)
    let lock = try WorkspaceLock.acquire(ws)
    lock.release()
}

@Test func oldLockFromAnotherHostIsTakenOver() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try Data(#"{"pid":1,"host":"otro-mac","since":"2020-01-01T00:00:00Z"}"#.utf8).write(to: ws.lockURL)
    let lock = try WorkspaceLock.acquire(ws)
    lock.release()
}

@Test func recentLockFromAnotherHostBlocks() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let since = ISO8601DateFormatter().string(from: Date())
    try Data(#"{"pid":1,"host":"otro-mac","since":"\#(since)"}"#.utf8).write(to: ws.lockURL)
    #expect(throws: (any Error).self) { try WorkspaceLock.acquire(ws) }
}

@Test func aJustCreatedEmptyLockIsRespected() throws {   // otro proceso entre crear el bloqueo y escribirlo
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    FileManager.default.createFile(atPath: ws.lockURL.path, contents: nil)
    #expect(throws: (any Error).self) { try WorkspaceLock.acquire(ws) }
}

@Test func anOldUnreadableLockIsTakenOver() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    FileManager.default.createFile(atPath: ws.lockURL.path, contents: Data("basura".utf8))
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: ws.lockURL.path)
    let lock = try WorkspaceLock.acquire(ws)
    lock.release()
}

/// El nombre del Mac sale de `gethostname()`, no de `ProcessInfo.hostName`: dentro de una app con sandbox y sin permiso
/// de red, `hostName` da «localhos», y el bloqueo de un CLI muerto parecería de otro Mac (se esperaría 12 h).
/// En un Mac con red las dos dan lo mismo, así que esta prueba no ve si alguien vuelve a `hostName`: eso lo ve el paso
/// 13 de la tanda QA (tria-app, `scripts/qa.sh --solo 13`), que corre en el sandbox sin red.
@Test func theLockCarriesTheMachineNameFromGethostname() throws {
    var buffer = [CChar](repeating: 0, count: 256)
    #expect(gethostname(&buffer, buffer.count) == 0)
    let expected = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    #expect(WorkspaceLock.thisHost == expected)

    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let lock = try WorkspaceLock.acquire(ws)
    defer { lock.release() }
    let written = try JSONSerialization.jsonObject(with: Data(contentsOf: ws.lockURL)) as? [String: Any]
    #expect(written?["host"] as? String == expected)
}

// MARK: - Quién tiene el bloqueo, sin tomarlo

/// El fichero del bloqueo tal cual está: mirarlo no puede cambiarlo.
private struct LockFile: Equatable {
    var data: Data
    var modified: Date

    init(_ ws: Workspace) throws {
        data = try Data(contentsOf: ws.lockURL)
        modified = try FileManager.default.attributesOfItem(atPath: ws.lockURL.path)[.modificationDate] as? Date
            ?? .distantPast
    }
}

/// Un bloqueo como el que deja otro proceso: su pid, su Mac y desde cuándo.
private func writeLock(_ ws: Workspace, pid: Int32, host: String = WorkspaceLock.thisHost,
                       since: Date = Date()) throws {
    try FileManager.default.createDirectory(at: ws.stateURL, withIntermediateDirectories: true)
    let since = ISO8601DateFormatter().string(from: since)
    try Data(#"{"pid":\#(pid),"host":"\#(host)","since":"\#(since)"}"#.utf8).write(to: ws.lockURL)
}

@Test func aLockFromAnotherLiveProcessIsHeldAndLookingLeavesItAlone() throws {   // el CLI ordenando en este Mac
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try writeLock(ws, pid: getppid())
    let before = try LockFile(ws)
    let holder = try #require(WorkspaceLock.holder(of: ws))
    #expect(holder.host == WorkspaceLock.thisHost && holder.pid == getppid())
    #expect(!holder.isThisProcess)
    #expect(try LockFile(ws) == before, "Mirarlo no lo toca")
    // Y sigue valiendo para `acquire`.
    #expect(throws: (any Error).self) { try WorkspaceLock.acquire(ws) }
}

@Test func aRecentLockFromAnotherMacIsHeld() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try writeLock(ws, pid: 1, host: "otro-mac")
    let holder = try #require(WorkspaceLock.holder(of: ws))
    #expect(holder.host == "otro-mac" && !holder.isThisProcess)
}

@Test func aLockFromADeadProcessOfThisMacIsNotHeldAndIsNotRemoved() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try writeLock(ws, pid: 999_999)
    let before = try LockFile(ws)
    #expect(WorkspaceLock.holder(of: ws) == nil)
    #expect(try LockFile(ws) == before, "Mirar no retira nada: eso lo hace `acquire`")
}

@Test func aTooOldLockIsNotHeldAndIsNotRemoved() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try writeLock(ws, pid: 1, host: "otro-mac", since: Date().addingTimeInterval(-43_201))
    let before = try LockFile(ws)
    #expect(WorkspaceLock.holder(of: ws) == nil)
    #expect(WorkspaceLock.holder(of: ws, staleAfter: 86_400) != nil, "Con el mismo plazo que `acquire`")
    #expect(try LockFile(ws) == before)
}

@Test func theLockOfThisProcessIsHeldByThisProcess() throws {   // la app leyendo: no es «otro sitio»
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let lock = try WorkspaceLock.acquire(ws)
    defer { lock.release() }
    let holder = try #require(WorkspaceLock.holder(of: ws))
    #expect(holder.isThisProcess)
}

@Test func withoutALockNobodyHoldsItAndNothingIsCreated() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    #expect(WorkspaceLock.holder(of: ws) == nil)
    #expect(!FileManager.default.fileExists(atPath: ws.lockURL.path))
}

@Test func anUnreadableLockIsHeldOnlyWhileItIsRecent() throws {   // las mismas reglas que `acquire`
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    FileManager.default.createFile(atPath: ws.lockURL.path, contents: nil)
    let holder = try #require(WorkspaceLock.holder(of: ws), "Otro proceso que aún no lo ha escrito")
    #expect(!holder.isThisProcess)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)],
                                          ofItemAtPath: ws.lockURL.path)
    let before = try LockFile(ws)
    #expect(WorkspaceLock.holder(of: ws) == nil)
    #expect(try LockFile(ws) == before)
}

@Test func lockedErrorKnowsWhetherThisProcessHoldsIt() throws {   // la app, ordenando a la vez que otra cosa
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let lock = try WorkspaceLock.acquire(ws)
    defer { lock.release() }
    let own = #expect(throws: WorkspaceError.self) { try WorkspaceLock.acquire(ws) }
    #expect(own?.isHeldByThisProcess == true)
    let now = Date()
    #expect(WorkspaceError.locked(host: WorkspaceLock.thisHost, pid: getppid(), since: now).isHeldByThisProcess == false)
    #expect(WorkspaceError.locked(host: "otro-mac", pid: getpid(), since: now).isHeldByThisProcess == false)
    #expect(WorkspaceError.locked(host: "?", pid: 0, since: now).isHeldByThisProcess == false, "Cerrojo ilegible")
    #expect(WorkspaceError.rulesAlreadyExist.isHeldByThisProcess == false)
}
